#import "FCXDRBrightness.h"
#import "DisplayBrightnessHelpers.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <dlfcn.h>

// ── private DisplayServices SPI, reached by dlsym ────────────────────────────
// Signatures confirmed against the shared-cache binary rather than community
// headers. Both brightness calls take a FLOAT, not a double — passing a double
// puts the value in the wrong register and silently sets garbage.
typedef int (*FCDSGetBrightness)(CGDirectDisplayID, float *);
typedef int (*FCDSSetBrightness)(CGDirectDisplayID, float);
typedef int (*FCDSCanChangeBrightness)(CGDirectDisplayID);
typedef int (*FCDSAmbientEnabled)(CGDirectDisplayID, bool *);
typedef int (*FCDSRegisterNotify)(CGDirectDisplayID, void *, void *);

static FCDSGetBrightness       gDSGet;
static FCDSSetBrightness       gDSSet;
static FCDSCanChangeBrightness gDSCanChange;
static FCDSAmbientEnabled      gDSAmbient;
static FCDSRegisterNotify      gDSRegister;
static BOOL                    gSPIResolved;

// The framework file does not exist on disk — since macOS 11 system
// frameworks live only in the dyld shared cache, so `nm` on this path fails
// while dlopen of the very same path succeeds. CoreDisplay, which most write-
// ups name instead, does NOT resolve here and its getters write nothing at any
// out-parameter width; DisplayServices is the only working door.
static void FCResolveBrightnessSPI(void) {
    if (gSPIResolved) return;
    gSPIResolved = YES;
    void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework"
                     "/DisplayServices", RTLD_LAZY);
    if (!h) return;
    gDSGet       = (FCDSGetBrightness)dlsym(h, "DisplayServicesGetBrightness");
    gDSSet       = (FCDSSetBrightness)dlsym(h, "DisplayServicesSetBrightness");
    gDSCanChange = (FCDSCanChangeBrightness)dlsym(h, "DisplayServicesCanChangeBrightness");
    gDSAmbient   = (FCDSAmbientEnabled)dlsym(h, "DisplayServicesAmbientLightCompensationEnabled");
    gDSRegister  = (FCDSRegisterNotify)dlsym(h,
                       "DisplayServicesRegisterForBrightnessChangeNotifications");
}

// ── tuning ──────────────────────────────────────────────────────────────────
static const NSTimeInterval kEngageTick  = 0.4;   // sampling while ramping
static const NSTimeInterval kHoldTick    = 2.0;   // one 1x1 frame to hold EDR
static const double         kSettleEps   = 0.01;  // headroom deemed unchanged
static const int            kSettleHits  = 3;     // consecutive stable reads
static const uint32_t       kRampEntries = 256;
static const double         kTriggerClear = 8.0;  // >1.0 clear colour

@implementation FCBrightnessEngine {
    CGDirectDisplayID _display;

    // EDR trigger. Never retain the NSScreen it sits on — a held NSScreen
    // reports frozen EDR values forever.
    NSWindow            *_trigger;
    CAMetalLayer        *_metalLayer;
    id<MTLCommandQueue>  _queue;
    NSTimer             *_timer;

    // Baseline ramp, captured once per engage cycle and NEVER re-captured
    // while a factor is applied. This is the anti-compounding invariant.
    CGGammaValue _baseR[256], _baseG[256], _baseB[256];
    uint32_t     _baseCount;
    BOOL         _baseValid;

    double _lastHeadroom;
    int    _stableHits;
    double _writtenFactor;   // what we last pushed, to avoid pointless rewrites

    NSInteger _requestedLevel;
    BOOL      _observing;
}

+ (instancetype)shared {
    static FCBrightnessEngine *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[FCBrightnessEngine alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        FCResolveBrightnessSPI();
        _display        = [self builtinDisplay];
        _appliedFactor  = 1.0;
        _writtenFactor  = 1.0;
        _headroom       = 1.0;
        _boostState     = FCBrightnessBoostOff;
        // readSliderPercent returns -1 when the SPI is missing or the display
        // is not controllable (clamshell on an external monitor at launch).
        // Do NOT let that become the level: a negative level would render as
        // "-1%" and make the track's fill fraction negative. Fall back to the
        // hand-over point, which writes nothing until the user acts.
        NSInteger hw = [self readSliderPercent];
        _requestedLevel = (hw >= 0) ? hw : 100;
        _level          = _requestedLevel;

        // Process death already reverts the gamma override — that is the
        // primary safety property and it covers SIGKILL. This atexit hook adds
        // nothing for a crash; it exists so a CLEAN exit restores immediately
        // rather than leaving the panel bright for the moment it takes the
        // window server to notice the process is gone.
        gPanicDisplay = _display;
        atexit(FCPanicRestoreGamma);

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(screensChanged:)
                   name:NSApplicationDidChangeScreenParametersNotification object:nil];
        NSNotificationCenter *wnc = [[NSWorkspace sharedWorkspace] notificationCenter];
        [wnc addObserver:self selector:@selector(willSleep:)
                    name:NSWorkspaceWillSleepNotification object:nil];
        [wnc addObserver:self selector:@selector(didWake:)
                    name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [self releaseBoost];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark Display + screen resolution

- (CGDirectDisplayID)builtinDisplay {
    // Built-in only, deliberately. External panels expose no EDR headroom to
    // unlock, and their backlight lives behind DDC/CI — a different project.
    uint32_t count = 0;
    CGDirectDisplayID ids[16];
    if (CGGetActiveDisplayList(16, ids, &count) != kCGErrorSuccess) return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(ids[i])) return ids[i];
    }
    return kCGNullDirectDisplay;
}

// Always re-resolve; never cache. See the header's stale-NSScreen note.
- (nullable NSScreen *)builtinScreen {
    if (_display == kCGNullDirectDisplay) return nil;
    for (NSScreen *s in [NSScreen screens]) {
        NSNumber *n = s.deviceDescription[@"NSScreenNumber"];
        if ([n isKindOfClass:[NSNumber class]] &&
            (CGDirectDisplayID)n.unsignedIntValue == _display) return s;
    }
    return nil;
}

#pragma mark Capability

- (BOOL)sliderAvailable {
    if (!gDSGet || !gDSSet || _display == kCGNullDirectDisplay) return NO;
    return gDSCanChange ? (gDSCanChange(_display) != 0) : YES;
}

- (BOOL)boostAvailable {
    NSScreen *s = [self builtinScreen];
    if (!s) return NO;
    if (s.maximumPotentialExtendedDynamicRangeColorComponentValue <= 1.01) return NO;

    // REFERENCE-MODE REFUSAL. A non-zero reference EDR value means the panel is
    // in one of Apple's calibrated presets ("Apple XDR Display (P3-1600 nits)",
    // "HDTV Video", and so on), where the whole point is that emitted luminance
    // is a known quantity. Multiplying the gamma ramp there silently destroys
    // the calibration the user deliberately selected — the display still looks
    // brighter, which is exactly what makes it insidious. Measured 0.0 on this
    // machine in its default preset, so this refuses only when it should.
    if (s.maximumReferenceExtendedDynamicRangeColorComponentValue > 0.01) return NO;

    return YES;
}

// Why boost is unavailable, for the UI to explain rather than just grey out.
- (NSString *)boostUnavailableReason {
    NSScreen *s = [self builtinScreen];
    if (!s) return @"no controllable built-in display";
    if (s.maximumPotentialExtendedDynamicRangeColorComponentValue <= 1.01)
        return @"this display has no extra EDR headroom";
    if (s.maximumReferenceExtendedDynamicRangeColorComponentValue > 0.01)
        return @"display is in a calibrated reference preset";
    return nil;
}

- (NSInteger)maximumLevel {
    return [self boostAvailable] ? kFCMaxBoostLevelPercent : 100;
}

- (BOOL)ambientCompensationEnabled {
    if (!gDSAmbient || _display == kCGNullDirectDisplay) return NO;
    bool on = false;
    // (display, bool *) — writes exactly one byte via strb; confirmed by
    // disassembly, not guessed. Returns non-zero on failure.
    return (gDSAmbient(_display, &on) == 0) && on;
}

#pragma mark Slider (0..100)

- (NSInteger)readSliderPercent {
    if (!gDSGet || _display == kCGNullDirectDisplay) return -1;
    float v = -1.0f;
    if (gDSGet(_display, &v) != 0) return -1;
    if (v < 0.0f) return -1;
    return (NSInteger)lround(FCClampBrightness((double)v) * 100.0);
}

- (void)writeSlider:(double)value {
    if (!gDSSet || _display == kCGNullDirectDisplay) return;
    gDSSet(_display, (float)FCClampBrightness(value));
}

#pragma mark Public API

- (NSInteger)setLevel:(NSInteger)level {
    NSInteger clamped = FCClampLevelPercent(level, [self maximumLevel]);
    _requestedLevel = clamped;
    _level = clamped;

    double slider = 1.0;
    FCDecomposeLevel(clamped, _headroom, &slider, NULL);
    [self writeSlider:slider];

    if (clamped > 100) {
        [self engageBoost];
    } else {
        [self releaseBoost];
    }
    [self notifyChanged];
    return clamped;
}

- (void)poll {
    _display = [self builtinDisplay];
    if (_display == kCGNullDirectDisplay) {   // clamshell, or built-in gone
        [self releaseBoost];
        return;
    }
    NSScreen *s = [self builtinScreen];
    _headroom = s ? s.maximumExtendedDynamicRangeColorComponentValue : 1.0;

    NSInteger hw = [self readSliderPercent];
    if (_requestedLevel <= 100) {
        // Follow the hardware so F1/F2 and Control Center move the rail.
        if (hw >= 0 && hw != _level) {
            _level = hw;
            _requestedLevel = hw;
            [self notifyChanged];
        }
        return;
    }

    // Boosted. The slider is pinned at maximum, so a reading below it means
    // the user (or the ambient sensor) moved brightness behind our back —
    // hand control back rather than fighting for it.
    if (hw >= 0 && hw < 99) {
        _requestedLevel = hw;
        _level = hw;
        [self releaseBoost];
        [self notifyChanged];
    }
}

#pragma mark EDR trigger

- (void)buildTrigger {
    if (_trigger) return;
    NSScreen *screen = [self builtinScreen];
    if (!screen) return;

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) return;
    _queue = [dev newCommandQueue];
    if (!_queue) return;

    // 1x1 and invisible. Its pixels are never meant to be seen; its only job
    // is to be EDR content so the compositor grants headroom the gamma ramp
    // can then spend across the whole desktop.
    NSRect r = NSMakeRect(NSMinX(screen.frame), NSMinY(screen.frame), 1, 1);
    _trigger = [[NSWindow alloc] initWithContentRect:r
                                           styleMask:NSWindowStyleMaskBorderless
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
    _trigger.level            = kCGScreenSaverWindowLevel;
    _trigger.backgroundColor  = [NSColor clearColor];
    _trigger.opaque           = NO;
    _trigger.hasShadow        = NO;
    _trigger.ignoresMouseEvents = YES;
    _trigger.releasedWhenClosed = NO;
    _trigger.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary |
                                  NSWindowCollectionBehaviorIgnoresCycle |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    host.wantsLayer = YES;
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device         = dev;
    _metalLayer.pixelFormat    = MTLPixelFormatRGBA16Float;   // half-float carries >1.0
    _metalLayer.framebufferOnly = YES;
    _metalLayer.frame          = CGRectMake(0, 0, 1, 1);
    _metalLayer.drawableSize   = CGSizeMake(1, 1);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    _metalLayer.colorspace = cs;
    if (cs) CGColorSpaceRelease(cs);
    _metalLayer.wantsExtendedDynamicRangeContent = YES;
    [host.layer addSublayer:_metalLayer];
    _trigger.contentView = host;
    [_trigger orderFrontRegardless];
}

// Present one frame above 1.0. Without this the grant never arrives, however
// the layer is configured.
- (void)renderTriggerFrame {
    if (!_metalLayer || !_queue) return;
    @autoreleasepool {
        id<CAMetalDrawable> d = [_metalLayer nextDrawable];
        if (!d) return;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture     = d.texture;
        rp.colorAttachments[0].loadAction  = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor  =
            MTLClearColorMake(kTriggerClear, kTriggerClear, kTriggerClear, 1.0);
        id<MTLCommandBuffer> cb = [_queue commandBuffer];
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        [cb presentDrawable:d];
        [cb commit];
    }
}

- (void)tearDownTrigger {
    [_timer invalidate];
    _timer = nil;
    if (_trigger) {
        _trigger.contentView = nil;
        [_trigger orderOut:nil];
        [_trigger close];
        _trigger = nil;
    }
    _metalLayer = nil;
    _queue = nil;
}

#pragma mark Gamma

// Capture the ramp to scale from. Refuses anything that is not neutral: a
// ramp topping out above 1.01 is one we already boosted, and storing it would
// square the factor on the next apply.
- (BOOL)captureBaseline {
    if (_display == kCGNullDirectDisplay) return NO;
    uint32_t n = 0;
    if (CGGetDisplayTransferByTable(_display, kRampEntries,
                                    _baseR, _baseG, _baseB, &n) != kCGErrorSuccess) {
        _baseValid = NO;
        return NO;
    }
    if (n == 0 || n > kRampEntries) { _baseValid = NO; return NO; }
    if (!FCGammaBaselineIsNeutral((double)_baseR[n - 1])) {
        // Already boosted. Do not trust it; restore and try once more.
        CGDisplayRestoreColorSyncSettings();
        if (CGGetDisplayTransferByTable(_display, kRampEntries,
                                        _baseR, _baseG, _baseB, &n) != kCGErrorSuccess ||
            n == 0 || !FCGammaBaselineIsNeutral((double)_baseR[n - 1])) {
            _baseValid = NO;
            return NO;
        }
    }
    _baseCount = n;
    _baseValid = YES;
    return YES;
}

// LAST-RESORT RESTORE. Registered with atexit() and callable from anywhere.
// Deliberately uses only CoreGraphics C calls and touches no Objective-C
// state, so it remains valid while the process is tearing down.
static CGDirectDisplayID gPanicDisplay = kCGNullDirectDisplay;
static void FCPanicRestoreGamma(void) {
    if (gPanicDisplay != kCGNullDirectDisplay) {
        CGDisplayRestoreColorSyncSettings();
    }
}

// Force the display back to its ColorSync-defined ramp and forget all state.
// Used whenever an invariant fails: the correct response to "I am not sure
// what state the gamma table is in" is always "put it back", never "carry on".
- (void)panicRestore:(NSString *)why {
    (void)why;   // reserved for a future diagnostics channel
    CGDisplayRestoreColorSyncSettings();
    _writtenFactor = 1.0;
    _appliedFactor = 1.0;
    _baseValid     = NO;
    _requestedLevel = MIN(_requestedLevel, (NSInteger)100);
    _level          = _requestedLevel;
    [self tearDownTrigger];
    _boostState = FCBrightnessBoostReleasing;
    [self notifyChanged];
}

- (void)applyGammaFactor:(double)factor {
    if (!_baseValid || _display == kCGNullDirectDisplay) return;
    if (fabs(factor - _writtenFactor) < 0.005) return;   // drift tolerance, not a 2 Hz rewrite

    // Belt and braces on the ceiling. kFCAbsoluteFactorCap is already applied
    // upstream in FCAppliedFactorForLevel, but this is the ONLY place that
    // writes the hardware, so it is the right place to make the cap
    // unbypassable — including by a hand-edited preferences file.
    if (factor > kFCAbsoluteFactorCap) factor = kFCAbsoluteFactorCap;

    if (factor <= 1.0 + 1e-6) {
        CGSetDisplayTransferByTable(_display, _baseCount, _baseR, _baseG, _baseB);
        _writtenFactor = 1.0;
        return;
    }

    CGGammaValue r[256], g[256], b[256];
    for (uint32_t i = 0; i < _baseCount; i++) {
        r[i] = (CGGammaValue)(_baseR[i] * factor);
        g[i] = (CGGammaValue)(_baseG[i] * factor);
        b[i] = (CGGammaValue)(_baseB[i] * factor);
    }
    if (CGSetDisplayTransferByTable(_display, _baseCount, r, g, b) != kCGErrorSuccess) {
        [self panicRestore:@"CGSetDisplayTransferByTable failed"];
        return;
    }

    // VERIFY THE WRITE. Never assume a display API did what it was asked —
    // this whole feature exists because a documented range is not enforced,
    // and the same laxity means a write can land differently than requested.
    CGGammaValue rr[256], gg[256], bb[256];
    uint32_t got = 0;
    if (CGGetDisplayTransferByTable(_display, 256, rr, gg, bb, &got) != kCGErrorSuccess ||
        got != _baseCount) {
        [self panicRestore:@"could not read back the ramp we just wrote"];
        return;
    }
    if (fabs((double)rr[_baseCount - 1] - (double)r[_baseCount - 1]) > 0.05) {
        [self panicRestore:@"ramp readback does not match what was written"];
        return;
    }
    _writtenFactor = factor;
}

#pragma mark Engage / release

- (void)engageBoost {
    if (![self boostAvailable]) return;
    if (_display != kCGNullDirectDisplay && CGDisplayIsAsleep(_display)) return;

    if (_boostState == FCBrightnessBoostOff ||
        _boostState == FCBrightnessBoostReleasing) {
        if (![self captureBaseline]) return;
        _stableHits   = 0;
        _lastHeadroom = -1.0;
        [self buildTrigger];
        if (!_trigger) return;
        _boostState = FCBrightnessBoostEngaging;
        [self scheduleTimer:kEngageTick];
    } else if (_boostState == FCBrightnessBoostActive) {
        // Already up — just re-evaluate the factor for the new request.
        [self applyForCurrentHeadroom];
    }
}

- (void)scheduleTimer:(NSTimeInterval)interval {
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                              target:self
                                            selector:@selector(triggerTick:)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)triggerTick:(NSTimer *)t {
    (void)t;
    [self renderTriggerFrame];

    NSScreen *s = [self builtinScreen];
    double h = s ? s.maximumExtendedDynamicRangeColorComponentValue : 1.0;
    _headroom = h;

    if (_boostState == FCBrightnessBoostEngaging) {
        // Settle gate. The factor is LARGER at lower headroom, so applying
        // during the ramp overshoots and then sags — wait for the reading to
        // stop moving instead of acting on the first crossing.
        if (_lastHeadroom >= 0.0 && fabs(h - _lastHeadroom) < kSettleEps) {
            _stableHits++;
        } else {
            _stableHits = 0;
        }
        _lastHeadroom = h;
        if (_stableHits >= kSettleHits && h > 1.01) {
            _boostState = FCBrightnessBoostActive;
            [self applyForCurrentHeadroom];
            [self scheduleTimer:kHoldTick];   // one 1x1 frame every 2 s holds it
            [self notifyChanged];
        }
        return;
    }

    if (_boostState == FCBrightnessBoostActive) {
        // HEADROOM-COLLAPSE GUARD. If the compositor withdraws the grant while
        // a >1.0 ramp is applied, the excess has nowhere to map and the top of
        // the range clips. Withdrawal can happen for reasons we do not control
        // — the user switching to a reference preset, another client's EDR
        // request ending, a display reconfiguration we have not been told
        // about yet. Treat it as an invariant failure, not as a new operating
        // point to adapt to.
        if (h <= 1.01 && _writtenFactor > 1.0 + 1e-6) {
            [self panicRestore:@"EDR headroom was withdrawn while boosted"];
            return;
        }
        // Headroom is system-wide; another EDR client (an HDR video) moves it
        // underneath us, and the right factor moves with it.
        [self applyForCurrentHeadroom];
        return;
    }

    if (_boostState == FCBrightnessBoostReleasing && h <= 1.01) {
        _boostState = FCBrightnessBoostOff;
        [_timer invalidate];
        _timer = nil;
        [self notifyChanged];
    }
}

- (void)applyForCurrentHeadroom {
    double f = FCAppliedFactorForLevel(_requestedLevel, _headroom);
    [self applyGammaFactor:f];
    if (fabs(f - _appliedFactor) > 1e-6) {
        _appliedFactor = f;
        [self notifyChanged];
    }
}

- (void)releaseBoost {
    if (_boostState == FCBrightnessBoostOff && !_trigger && _writtenFactor <= 1.0) return;

    // Order matters: neutralise the ramp FIRST. Dropping the trigger while a
    // >1.0 ramp is applied leaves the ramp with no headroom to map into.
    [self applyGammaFactor:1.0];
    if (_baseValid) {
        CGSetDisplayTransferByTable(_display, _baseCount, _baseR, _baseG, _baseB);
    }
    CGDisplayRestoreColorSyncSettings();
    _writtenFactor = 1.0;
    _appliedFactor = 1.0;
    _baseValid     = NO;

    [self tearDownTrigger];

    // Headroom keeps decaying for ~15 s; do not let the UI claim "off" yet.
    _boostState = (_headroom > 1.01) ? FCBrightnessBoostReleasing : FCBrightnessBoostOff;
    if (_boostState == FCBrightnessBoostReleasing) [self scheduleTimer:kEngageTick];
    [self notifyChanged];
}

#pragma mark System events

- (void)screensChanged:(NSNotification *)n {
    (void)n;
    CGDirectDisplayID now = [self builtinDisplay];
    if (now != _display) {
        [self releaseBoost];
        _display = now;
    }
}

- (void)willSleep:(NSNotification *)n {
    (void)n;
    [self releaseBoost];
}

- (void)didWake:(NSNotification *)n {
    (void)n;
    // Neutralise and discard the baseline BEFORE anything can re-capture. A
    // baseline re-read while boosted squares the factor every wake; this is
    // the measured 1.2952 -> 1.6776 bug, and the ordering here is the fix.
    [self applyGammaFactor:1.0];
    CGDisplayRestoreColorSyncSettings();
    _baseValid     = NO;
    _writtenFactor = 1.0;
    _appliedFactor = 1.0;
    _boostState    = FCBrightnessBoostOff;

    if (_requestedLevel > 100) {
        // Give the display pipeline a moment to come back before re-engaging.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf engageBoost];
        });
    }
    [self notifyChanged];
}

- (void)notifyChanged {
    if (!self.changeHandler) return;
    if ([NSThread isMainThread]) { self.changeHandler(); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.changeHandler) self.changeHandler();
    });
}

@end
