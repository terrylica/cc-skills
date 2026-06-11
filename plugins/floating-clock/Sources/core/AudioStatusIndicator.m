#import "AudioStatusIndicator.h"
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
@interface FCAudioZoneView : NSView
@property (nonatomic, weak) FCAudioStatusIndicator *owner;
@property (nonatomic, assign) BOOL isInput;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *minusLabel;
@property (nonatomic, strong) NSTextField *levelLabel;
@property (nonatomic, strong) NSTextField *plusLabel;
@end

@implementation FCAudioZoneView

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
    // Last-rendered state — labels are only touched when a value changes,
    // keeping the 1Hz refresh free of layout/alloc churn.
    NSString        *_lastInName;
    NSString        *_lastOutName;
    NSInteger        _lastInPct;
    NSInteger        _lastOutPct;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock      = clockPanel;
        _lastInPct  = NSIntegerMin;
        _lastOutPct = NSIntegerMin;
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
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.11 green:0.11 blue:0.125 alpha:0.94] CGColor];
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
    [self renderZone:_inZone isInput:YES  lastName:&_lastInName  lastPct:&_lastInPct];
    [self renderZone:_outZone isInput:NO lastName:&_lastOutName lastPct:&_lastOutPct];
    [self syncPosition];
}

- (void)renderZone:(FCAudioZoneView *)zone
           isInput:(BOOL)isInput
          lastName:(NSString * __strong *)lastName
           lastPct:(NSInteger *)lastPct {
    AudioObjectID dev = FCDefaultDevice(isInput);
    NSString *name = FCAudioDeviceName(dev) ?: @"(no device)";
    float vol = FCReadVolume(dev, isInput);
    NSInteger pct = (vol < 0.0f) ? -1 : (NSInteger)lroundf(vol * 100.0f);

    if (![name isEqualToString:*lastName]) {
        *lastName = name;
        NSString *prefix = isInput ? @"IN " : @"OUT ";
        NSColor *tint = isInput
            ? [NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0]   // green — capture
            : [NSColor colorWithSRGBRed:0.38 green:0.78 blue:1.00 alpha:1.0];  // blue  — playback
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
        [s appendAttributedString:[[NSAttributedString alloc]
            initWithString:prefix
                attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy],
                              NSForegroundColorAttributeName: tint }]];
        [s appendAttributedString:[[NSAttributedString alloc]
            initWithString:name
                attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
                              NSForegroundColorAttributeName: [NSColor whiteColor] }]];
        zone.nameLabel.attributedStringValue = s;
        zone.nameLabel.toolTip = [NSString stringWithFormat:@"%@ — click to switch to the next available %@ device",
                                  name, isInput ? @"input" : @"output"];
    }
    if (pct != *lastPct) {
        *lastPct = pct;
        zone.levelLabel.stringValue = (pct < 0) ? @"--" : [NSString stringWithFormat:@"%ld", (long)pct];
        BOOL adjustable = (pct >= 0);
        zone.minusLabel.textColor = [NSColor colorWithWhite:1.0 alpha:adjustable ? 0.55 : 0.18];
        zone.plusLabel.textColor  = [NSColor colorWithWhite:1.0 alpha:adjustable ? 0.55 : 0.18];
    }
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
