#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"   // -isShowing feeds the IN zone's red mute state
#import <CoreAudio/CoreAudio.h>

// Bar geometry — matches the mic-mute / VPN bars so the stack reads as one
// coherent column of 20pt rails above the clock.
static const CGFloat kAudioBarHeight = 20.0;
static const CGFloat kAudioBarGap    = 3.0;

// Fixed-width control cells inside each zone (points).
static const CGFloat kGlyphW = 14.0;   // − and + hit cells
// Numeric level cell. "100" at 11pt monospaced-bold ≈ 20pt of glyphs, but
// NSTextField adds ~2pt internal padding per side — 24pt truncated "100"
// to "…" (verified on-screen 2026-06-11), so size for glyphs + padding.
static const CGFloat kLevelW = 30.0;
static const CGFloat kPadX   = 6.0;    // zone inner horizontal padding

#pragma mark - CoreAudio helpers (stack-allocated, no per-call heap churn)

static AudioObjectID FCDefaultDevice(BOOL input) {
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID dev = kAudioObjectUnknown;
    UInt32 sz = sizeof(dev);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev) != noErr) {
        return kAudioObjectUnknown;
    }
    return dev;
}

static void FCSetDefaultDevice(AudioObjectID dev, BOOL input) {
    if (dev == kAudioObjectUnknown) return;
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL,
                               sizeof(dev), &dev);
}

static NSString *FCAudioDeviceName(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return nil;
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; UInt32 sz = sizeof(cf);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &cf) != noErr || !cf) return nil;
    return (__bridge_transfer NSString *)cf;
}

static BOOL FCDeviceHasChannels(AudioObjectID dev, BOOL input) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
                                     input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &sz) != noErr || sz == 0) return NO;
    // Stack buffer — AudioBufferList for a handful of streams is tiny.
    UInt8 buf[sz];
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, buf) != noErr) return NO;
    const AudioBufferList *abl = (const AudioBufferList *)buf;
    if (abl->mNumberBuffers == 0) return NO;
    UInt32 ch = 0;
    for (UInt32 i = 0; i < abl->mNumberBuffers; i++) ch += abl->mBuffers[i].mNumberChannels;
    return ch > 0;
}

// Software mute flag on the device's input scope (the analog hardware-button
// mute on the Antlion is invisible here — FCMicMuteIndicator's silence meter
// covers that path; the IN zone ORs both signals).
static BOOL FCReadInputMute(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return NO;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                     kAudioDevicePropertyScopeInput,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 v = 0, sz = sizeof(v);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) != noErr) return NO;
    return v != 0;
}

// Volume as 0.0–1.0, or -1 when the device exposes no volume control
// (e.g. HDMI/DisplayPort sinks). Tries the virtual main element first,
// then channel 1 (left) — the common pattern for BT and USB devices.
static float FCReadVolume(AudioObjectID dev, BOOL input) {
    if (dev == kAudioObjectUnknown) return -1.0f;
    AudioObjectPropertyScope scope = input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput;
    const UInt32 elements[2] = { kAudioObjectPropertyElementMain, 1 };
    for (int i = 0; i < 2; i++) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyVolumeScalar, scope, elements[i] };
        if (!AudioObjectHasProperty(dev, &a)) continue;
        Float32 v = 0; UInt32 sz = sizeof(v);
        if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) == noErr) return v;
    }
    return -1.0f;
}

// Write volume to the main element when available, else to channels 1+2.
// Returns YES if at least one element accepted the write.
static BOOL FCWriteVolume(AudioObjectID dev, BOOL input, float v) {
    if (dev == kAudioObjectUnknown) return NO;
    if (v < 0.0f) v = 0.0f;
    if (v > 1.0f) v = 1.0f;
    AudioObjectPropertyScope scope = input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput;
    Float32 vol = v;
    // Main element governs all channels — prefer it.
    AudioObjectPropertyAddress main = { kAudioDevicePropertyVolumeScalar, scope,
                                        kAudioObjectPropertyElementMain };
    Boolean settable = false;
    if (AudioObjectHasProperty(dev, &main) &&
        AudioObjectIsPropertySettable(dev, &main, &settable) == noErr && settable) {
        return AudioObjectSetPropertyData(dev, &main, 0, NULL, sizeof(vol), &vol) == noErr;
    }
    BOOL ok = NO;
    for (UInt32 ch = 1; ch <= 2; ch++) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyVolumeScalar, scope, ch };
        settable = false;
        if (AudioObjectHasProperty(dev, &a) &&
            AudioObjectIsPropertySettable(dev, &a, &settable) == noErr && settable &&
            AudioObjectSetPropertyData(dev, &a, 0, NULL, sizeof(vol), &vol) == noErr) {
            ok = YES;
        }
    }
    return ok;
}

// Virtual / aggregate transports are routing constructs (BackgroundMusic,
// Lark loopback, multi-output sets), not devices a human toggles between.
// Verified 2026-06-11: with them in the ring, cycling wedged on
// "Background Music" — its UI-Sounds sibling refuses main-default, so the
// ring never visibly advanced. The bar still DISPLAYS a virtual default
// truthfully; it just won't cycle INTO one.
static BOOL FCDeviceIsVirtual(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyTransportType,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 t = 0, sz = sizeof(t);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &t) != noErr) return NO;
    return t == kAudioDeviceTransportTypeVirtual
        || t == kAudioDeviceTransportTypeAggregate;
}

// All REAL devices with channels in the given scope (virtual/aggregate
// excluded — see FCDeviceIsVirtual), name-sorted for a stable, predictable
// cycling order. Returns AudioObjectID values boxed as NSNumber.
static NSArray<NSNumber *> *FCDevicesForScope(BOOL input) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr || sz == 0) {
        return @[];
    }
    UInt32 count = sz / (UInt32)sizeof(AudioObjectID);
    AudioObjectID ids[count];   // stack allocation — device lists are small
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, ids) != noErr) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *named = [NSMutableArray arrayWithCapacity:count];
    for (UInt32 i = 0; i < count; i++) {
        if (!FCDeviceHasChannels(ids[i], input)) continue;
        if (FCDeviceIsVirtual(ids[i])) continue;
        NSString *name = FCAudioDeviceName(ids[i]);
        if (!name.length) continue;
        [named addObject:@{ @"id": @(ids[i]), @"name": name }];
    }
    [named sortUsingComparator:^NSComparisonResult(NSDictionary *l, NSDictionary *r) {
        return [l[@"name"] localizedCaseInsensitiveCompare:r[@"name"]];
    }];
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:named.count];
    for (NSDictionary *d in named) [out addObject:d[@"id"]];
    return out;
}

#pragma mark - Zone view (one half of the bar: IN or OUT)

@class FCAudioStatusIndicator;

// Interactive half of the bar. Hit regions, left→right:
//   [prefix+device name ........][−][level][+]
// name click → cycle device · −/+ click → step volume · scroll → fine adjust.
//
// The zone OWNS its render state (2026-06-11 extras refactor): caching,
// the change-flash deadlines, and the muted tint all live here so the
// indicator just feeds it fresh HAL values once per tick.
@interface FCAudioZoneView : NSView
@property (nonatomic, weak) FCAudioStatusIndicator *owner;
@property (nonatomic, assign) BOOL isInput;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *minusLabel;
@property (nonatomic, strong) NSTextField *levelLabel;
@property (nonatomic, strong) NSTextField *plusLabel;

// Apply fresh state. Internally cached — labels only redraw when the
// rendered composite (name/pct/muted/flash-phase) actually changes.
- (void)renderDevice:(NSString *)name levelPercent:(NSInteger)pct muted:(BOOL)muted;
@end

@implementation FCAudioZoneView {
    // Render cache + flash state (2026-06-11 extras). _renderKey encodes the
    // full visible composite; when unchanged, the 1Hz tick touches nothing.
    NSString      *_renderKey;
    NSString      *_lastName;       // nil → first render (no flash on launch)
    NSInteger      _lastPct;
    CFAbsoluteTime _nameFlashUntil;
    CFAbsoluteTime _levelFlashUntil;
}

// Flash duration after a device/level change (user-selected extra): long
// enough to survive 1-2 ticks of the 1Hz refresh, short enough to read as
// a blink, not a state.
static const CFTimeInterval kFlashSecs = 1.4;

static NSTextField *FCBarLabel(NSFont *font, NSColor *color, NSTextAlignment align) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSZeroRect];
    l.editable = NO; l.selectable = NO; l.bezeled = NO; l.drawsBackground = NO;
    l.font = font; l.textColor = color; l.alignment = align;
    l.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return l;
}

- (instancetype)initWithFrame:(NSRect)frame isInput:(BOOL)isInput owner:(FCAudioStatusIndicator *)owner {
    if ((self = [super initWithFrame:frame])) {
        _isInput = isInput;
        _owner   = owner;

        NSFont *nameFont  = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
        NSFont *levelFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
        NSFont *glyphFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightHeavy];
        NSColor *dim      = [NSColor colorWithWhite:1.0 alpha:0.55];

        _nameLabel  = FCBarLabel(nameFont, [NSColor whiteColor], NSTextAlignmentLeft);
        _minusLabel = FCBarLabel(glyphFont, dim, NSTextAlignmentCenter);
        _levelLabel = FCBarLabel(levelFont, [NSColor whiteColor], NSTextAlignmentCenter);
        _plusLabel  = FCBarLabel(glyphFont, dim, NSTextAlignmentCenter);
        _minusLabel.stringValue = @"−";
        _plusLabel.stringValue  = @"+";

        NSString *cat = isInput ? @"input" : @"output";
        _nameLabel.toolTip  = [NSString stringWithFormat:@"Current %@ device — click to switch to the next available %@ device", cat, cat];
        _minusLabel.toolTip = [NSString stringWithFormat:@"Lower %@ level (scroll for fine adjust)", cat];
        _plusLabel.toolTip  = [NSString stringWithFormat:@"Raise %@ level (scroll for fine adjust)", cat];
        _levelLabel.toolTip = [NSString stringWithFormat:@"Current %@ level (0–100)", cat];

        [self addSubview:_nameLabel];
        [self addSubview:_minusLabel];
        [self addSubview:_levelLabel];
        [self addSubview:_plusLabel];
    }
    return self;
}

// Route EVERY click inside the zone to this view's mouseDown — the
// NSTextField subviews would otherwise swallow hits (verified 2026-06-11:
// clicks on the device-name label never reached mouseDown, so device
// cycling silently no-opped). Labels are display-only; the zone owns all
// interaction.
- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return v ? self : nil;
}

#pragma mark Zone rendering (cache + mute tint + change flash)

- (void)renderDevice:(NSString *)name levelPercent:(NSInteger)pct muted:(BOOL)muted {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL first = (_lastName == nil);
    if (!first) {
        if (![name isEqualToString:_lastName]) _nameFlashUntil  = now + kFlashSecs;
        if (pct != _lastPct)                   _levelFlashUntil = now + kFlashSecs;
    }
    BOOL nameFlash   = now < _nameFlashUntil;
    BOOL levelFlash  = now < _levelFlashUntil;
    BOOL nameChanged = first || ![name isEqualToString:_lastName];
    _lastName = [name copy];
    _lastPct  = pct;

    // Composite of everything visible — skip ALL label work when unchanged
    // (the 1Hz tick path must stay allocation/layout-free at steady state).
    NSString *key = [NSString stringWithFormat:@"%@|%ld|%d|%d|%d",
                     name, (long)pct, muted, nameFlash, levelFlash];
    if ([key isEqualToString:_renderKey]) return;
    _renderKey = key;

    NSColor *amber = [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0]; // change blink
    NSColor *red   = [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0]; // muted
    NSColor *tint  = muted ? red
                   : (self.isInput
                       ? [NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0]   // green — capture
                       : [NSColor colorWithSRGBRed:0.38 green:0.78 blue:1.00 alpha:1.0]); // blue  — playback
    NSColor *nameColor = muted ? red : (nameFlash ? amber : [NSColor whiteColor]);

    NSMutableDictionary *nameAttrs = [@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: nameColor,
    } mutableCopy];
    if (muted) nameAttrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);

    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    [s appendAttributedString:[[NSAttributedString alloc]
        initWithString:(self.isInput ? (muted ? @"IN⊘ " : @"IN ") : @"OUT ")
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy],
                          NSForegroundColorAttributeName: tint }]];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:name
                                                               attributes:nameAttrs]];
    self.nameLabel.attributedStringValue = s;
    if (nameChanged) {
        self.nameLabel.toolTip = [NSString stringWithFormat:@"%@ — click to switch to the next available %@ device",
                                  name, self.isInput ? @"input" : @"output"];
    }

    self.levelLabel.stringValue = (pct < 0) ? @"--" : [NSString stringWithFormat:@"%ld", (long)pct];
    self.levelLabel.textColor   = muted ? red : (levelFlash ? amber : [NSColor whiteColor]);
    BOOL adjustable = (pct >= 0);
    CGFloat glyphAlpha = adjustable ? 0.55 : 0.18;
    self.minusLabel.textColor = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];
    self.plusLabel.textColor  = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat h = 14.0;
    CGFloat y = (b.size.height - h) / 2.0;
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;
    CGFloat nameW  = xMinus - kPadX - 2.0;
    if (nameW < 10.0) nameW = 10.0;
    self.nameLabel.frame  = NSMakeRect(kPadX, y, nameW, h);
    self.minusLabel.frame = NSMakeRect(xMinus, y, kGlyphW, h);
    self.levelLabel.frame = NSMakeRect(xLevel, y, kLevelW, h);
    self.plusLabel.frame  = NSMakeRect(xPlus, y, kGlyphW, h);
}

// Hit zones use the control frames padded to the full bar height so the
// 20pt-tall rail is easy to hit despite 14pt-tall labels.
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger step = [FCAudioZoneView stepPercent];
    if (p.x >= NSMinX(self.minusLabel.frame) && p.x < NSMaxX(self.minusLabel.frame)) {
        [self.owner adjustVolumeForInput:self.isInput byPercent:-step];
    } else if (p.x >= NSMinX(self.plusLabel.frame)) {
        [self.owner adjustVolumeForInput:self.isInput byPercent:step];
    } else if (p.x >= NSMinX(self.levelLabel.frame) && p.x < NSMaxX(self.levelLabel.frame)) {
        // The number itself: top half nudges up, bottom half nudges down —
        // "adjustable directly on the number" per the user requirement.
        BOOL topHalf = p.y >= NSMidY(self.bounds);
        [self.owner adjustVolumeForInput:self.isInput byPercent:(topHalf ? step : -step)];
    } else {
        [self.owner cycleDeviceForInput:self.isInput];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat dy = event.scrollingDeltaY;
    if (dy == 0.0) return;
    [self.owner adjustVolumeForInput:self.isInput byPercent:(dy > 0 ? 2 : -2)];
}

+ (NSInteger)stepPercent {
    NSInteger s = [[NSUserDefaults standardUserDefaults] integerForKey:@"AudioBarStep"];
    if (s < 1)  s = 5;     // unset/garbage → default
    if (s > 25) s = 25;
    return s;
}

@end

#pragma mark - Indicator

@implementation FCAudioStatusIndicator {
    __weak NSPanel  *_clock;
    NSPanel         *_bar;
    FCAudioZoneView *_inZone;
    FCAudioZoneView *_outZone;
    NSView          *_divider;
    // Render caching lives inside each FCAudioZoneView (2026-06-11 extras
    // refactor) — the indicator just feeds fresh HAL values once per tick.
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        [self buildBar];
        [self refresh];
    }
    return self;
}

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"AudioBarEnabled"];
}

- (BOOL)isShowing { return [self enabled]; }

#pragma mark Bar window

- (void)buildBar {
    NSRect r = NSMakeRect(0, 0, 320, kAudioBarHeight);
    _bar = [[NSPanel alloc] initWithContentRect:r
                                      styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
    _bar.level                  = (_clock ? _clock.level : NSFloatingWindowLevel) + 1;
    _bar.opaque                 = NO;
    _bar.backgroundColor        = [NSColor clearColor];
    _bar.hasShadow              = YES;
    _bar.ignoresMouseEvents     = NO;    // interactive — toggle + level controls
    _bar.becomesKeyOnlyIfNeeded = YES;
    _bar.hidesOnDeactivate      = NO;
    _bar.movableByWindowBackground = NO; // clicks are controls, not drags
    _bar.collectionBehavior     = NSWindowCollectionBehaviorCanJoinAllSpaces
                                | NSWindowCollectionBehaviorStationary
                                | NSWindowCollectionBehaviorIgnoresCycle;

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    // 2026-06-11 contrast fix (research-converged "dual-layer" treatment used
    // by macOS HUDs / launcher panels): the pill must read on BOTH light and
    // pure-black backgrounds with zero per-frame sampling.
    //   1. Hairline white border — defines the edge on black (the NSPanel
    //      shadow is invisible there); near-invisible on light backgrounds
    //      where the dark fill already contrasts.
    //   2. Elevated surface — Material-style dark-elevation lift from
    //      0.11 → 0.16 gray so the fill itself separates from #000.
    //   3. NSPanel hasShadow (outer shadow) keeps doing the work on light.
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth     = 1.0;
    bg.layer.borderColor     = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _bar.contentView         = bg;

    _inZone  = [[FCAudioZoneView alloc] initWithFrame:NSZeroRect isInput:YES  owner:self];
    _outZone = [[FCAudioZoneView alloc] initWithFrame:NSZeroRect isInput:NO owner:self];
    _divider = [[NSView alloc] initWithFrame:NSZeroRect];
    _divider.wantsLayer = YES;
    _divider.layer.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.16] CGColor];
    [bg addSubview:_inZone];
    [bg addSubview:_outZone];
    [bg addSubview:_divider];

    [_bar orderOut:nil];   // shown on first refresh when enabled
}

- (void)layoutZonesForWidth:(CGFloat)w {
    CGFloat half = floor((w - 1.0) / 2.0);
    _inZone.frame  = NSMakeRect(0, 0, half, kAudioBarHeight);
    _divider.frame = NSMakeRect(half, 3, 1, kAudioBarHeight - 6);
    _outZone.frame = NSMakeRect(half + 1, 0, w - half - 1, kAudioBarHeight);
    _inZone.needsLayout  = YES;
    _outZone.needsLayout = YES;
}

#pragma mark Refresh (1Hz tick driver)

- (void)refresh {
    if (![self enabled]) {
        [_bar orderOut:nil];
        return;
    }
    AudioObjectID inDev  = FCDefaultDevice(YES);
    AudioObjectID outDev = FCDefaultDevice(NO);
    float inVol  = FCReadVolume(inDev, YES);
    float outVol = FCReadVolume(outDev, NO);
    // Mute = software mute flag on the current default input OR the mic
    // indicator's banner state (which adds the Antlion's analog hardware
    // button via its silence meter).
    BOOL inMuted = FCReadInputMute(inDev)
                || (self.micIndicator && [self.micIndicator isShowing]);

    [_inZone  renderDevice:(FCAudioDeviceName(inDev) ?: @"(no device)")
              levelPercent:(inVol  < 0.0f ? -1 : (NSInteger)lroundf(inVol  * 100.0f))
                     muted:inMuted];
    [_outZone renderDevice:(FCAudioDeviceName(outDev) ?: @"(no device)")
              levelPercent:(outVol < 0.0f ? -1 : (NSInteger)lroundf(outVol * 100.0f))
                     muted:NO];
    [self syncPosition];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || ![self enabled]) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    CGFloat w = c.size.width;
    CGFloat x = c.origin.x;
    CGFloat aboveY = NSMaxY(c) + kAudioBarGap;
    CGFloat y;
    if (aboveY + kAudioBarHeight <= NSMaxY(vf)) {
        y = aboveY;                                          // preferred: above the clock
    } else {
        y = c.origin.y - kAudioBarGap - kAudioBarHeight;     // fallback: below (clock at top edge)
    }
    if (x + w > NSMaxX(vf)) x = NSMaxX(vf) - w;
    if (x < vf.origin.x)    x = vf.origin.x;

    NSRect f = NSMakeRect(x, y, w, kAudioBarHeight);
    if (!NSEqualRects(f, _bar.frame)) {
        [_bar setFrame:f display:YES];
        [self layoutZonesForWidth:w];
    }
    if (!_bar.visible) [_bar orderFront:nil];
    [_bar orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
}

#pragma mark User actions

- (void)cycleDeviceForInput:(BOOL)isInput {
    NSArray<NSNumber *> *devs = FCDevicesForScope(isInput);
    if (devs.count == 0) return;
    AudioObjectID cur = FCDefaultDevice(isInput);
    NSUInteger idx = [devs indexOfObject:@(cur)];
    // Current default not in the real-device ring (e.g. a virtual device
    // grabbed it) → jump to the FIRST real device instead of wedging.
    NSUInteger next = (idx == NSNotFound) ? 0 : ((idx + 1) % devs.count);
    AudioObjectID target = (AudioObjectID)devs[next].unsignedIntValue;
    if (target == cur) return;   // single device — nothing to toggle to
    FCSetDefaultDevice(target, isInput);
    [self refresh];              // instant feedback
}

- (void)adjustVolumeForInput:(BOOL)isInput byPercent:(NSInteger)deltaPercent {
    AudioObjectID dev = FCDefaultDevice(isInput);
    float vol = FCReadVolume(dev, isInput);
    if (vol < 0.0f) return;      // device has no volume control
    FCWriteVolume(dev, isInput, vol + (float)deltaPercent / 100.0f);
    [self refresh];              // instant feedback
}

@end
