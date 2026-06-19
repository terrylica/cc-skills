#import "AudioStatusIndicator.h"
#import "AudioDeviceSelectionMenuController.h"  // pull-out menus (2026-06-11)
#import "AudioBarZoneView.h"                    // zone halves (2026-06-12 split)
#import "CoreAudioDeviceHALHelpers.h"           // HAL reads/writes (2026-06-12 split)
#import "ClockChildWindowAttachment.h"          // drag-welding (2026-06-12)
#import "OverlayPanelFactory.h"                 // shared overlay construction (DRY 2026-06-12)
#import "OverlayStackingPositioner.h"           // shared stacking geometry (DRY 2026-06-12)
#import "MicMuteIndicator.h"   // -isShowing feeds the IN zone's red mute state
#import <CoreAudio/CoreAudio.h>

// Bar geometry — matches the mic-mute / VPN bars so the stack reads as one
// coherent column of 20pt rails above the clock.
static const CGFloat kAudioBarHeight = 20.0;
static const CGFloat kAudioBarGap    = 3.0;

// Everything in a zone that is NOT the name label: left pad + 2pt name→glyph
// gap + the −/level/+ control cells + right pad. MUST equal the chrome
// FCAudioZoneView -layout reserves (kPadX 6 + nameW + 2 + kGlyphW 14 +
// kLevelW 30 + kGlyphW 14 + kPadX 6), so a zone of (name width + kZoneChromeW)
// shows the name in full. 6 + 2 + 14 + 30 + 14 + 6 = 72. The per-cell
// constants themselves live in FCAudioZoneView (the only place that lays them
// out); this file needs only their sum.
static const CGFloat kZoneChromeW = 72.0;
// Floor per zone so a short name (or "(no device)") next to a long one never
// looks cramped; the bar-width floor (clock width) handles the both-short case.
static const CGFloat kMinZoneW = 92.0;

#pragma mark - Indicator

@implementation FCAudioStatusIndicator {
    __weak NSPanel  *_clock;
    NSPanel         *_bar;
    FCAudioZoneView *_inZone;
    FCAudioZoneView *_outZone;
    NSView          *_divider;
    // Render caching lives inside each FCAudioZoneView (2026-06-11 extras
    // refactor) — the indicator just feeds fresh HAL values once per tick.

    // Pull-out menu support (2026-06-11). One controller for both zones;
    // transient ⏳/✗ status per scope ([0]=input, [1]=output) rendered in
    // place of the device name while a Bluetooth connect is in flight.
    FCAudioDeviceSelectionMenuController *_menuController;
    NSString       *_transientText[2];
    CFAbsoluteTime  _transientUntil[2];

    // Content-width sizing (2026-06-14). Each refresh stashes the width each
    // zone needs to show its prefix+name in full; syncPosition turns those
    // into the bar width and the asymmetric zone split. _lastInW/_lastBarW
    // cache the applied layout so the steady-state 1Hz tick re-flows nothing.
    CGFloat _inZoneNeed;
    CGFloat _outZoneNeed;
    CGFloat _lastInW;
    CGFloat _lastBarW;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _lastInW = _lastBarW = -1.0;   // force the first zone layout to apply
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
    // ignoresMouse:NO — this overlay carries interactive controls.
    _bar = FCCreateOverlayPanel(_clock, r.size, NO);

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

// Width a zone needs to show its prefix+name in full: the rendered composite
// measured at the SAME fonts FCAudioZoneView -renderDevice: uses, plus the
// fixed control chrome, floored at kMinZoneW. Strikethrough (muted) doesn't
// change advance, so only the prefix glyph matters ("IN⊘ "/"OUT⊘ " when muted
// vs "IN "/"OUT ") — measured with the SAME muted state the zone will render so
// the widened bar always fits the ⊘.
- (CGFloat)zoneWidthForName:(NSString *)name isInput:(BOOL)isInput muted:(BOOL)muted {
    NSString *prefix = isInput ? (muted ? @"IN⊘ " : @"IN ") : (muted ? @"OUT⊘ " : @"OUT ");
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:prefix
        attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy] }]];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:(name ?: @"")
        attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium] }]];
    // +3 absorbs sub-pixel rounding (the label's own nameW subtracts 2) so the
    // last glyph never clips into an ellipsis.
    CGFloat w = ceil(s.size.width) + 3.0 + kZoneChromeW;
    return w < kMinZoneW ? kMinZoneW : w;
}

// Lay the two zones into a bar of width `w` using the stashed per-zone needs.
//   · bar ≥ content → split the slack evenly (names left-align, trailing pad).
//   · bar < content (capped at screen width) → shrink proportionally; the
//     name labels truncate as a last resort.
// Caches the applied split so the 1Hz tick re-flows nothing at steady state.
- (void)layoutZonesInBarWidth:(CGFloat)w {
    CGFloat avail = w - 1.0;                       // minus the 1pt divider
    CGFloat need  = _inZoneNeed + _outZoneNeed;
    CGFloat inW;
    if (need <= 0.0) {
        inW = floor(avail / 2.0);
    } else if (avail >= need) {
        inW = _inZoneNeed + (avail - need) / 2.0;  // even slack split
    } else {
        inW = round(_inZoneNeed / need * avail);   // proportional shrink
    }
    inW = floor(inW);
    if (inW < 1.0)          inW = 1.0;
    if (inW > avail - 1.0)  inW = avail - 1.0;
    CGFloat outW = avail - inW;

    if (fabs(inW - _lastInW) < 0.5 && fabs(w - _lastBarW) < 0.5) return;  // unchanged
    _lastInW  = inW;
    _lastBarW = w;

    _inZone.frame  = NSMakeRect(0, 0, inW, kAudioBarHeight);
    _divider.frame = NSMakeRect(inW, 3, 1, kAudioBarHeight - 6);
    _outZone.frame = NSMakeRect(inW + 1, 0, outW, kAudioBarHeight);
    _inZone.needsLayout  = YES;
    _outZone.needsLayout = YES;
}

#pragma mark Refresh (1Hz tick driver)

- (void)refresh {
    if (![self enabled]) {
        FCHideOverlay(_bar);   // detach-then-hide ceremony (welding contract)
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
    // Output (playback) mute is a pure property read on the default output —
    // no analog-button/silence-meter path exists for outputs, so unlike the IN
    // zone there is nothing to OR in (FCReadOutputMute IS the whole signal).
    BOOL outMuted = FCReadOutputMute(outDev);

    // Transient ⏳/✗ status (BT connect in flight) overrides the device name.
    NSString *inName  = [self transientForInput:YES]
                      ?: (FCAudioDeviceName(inDev)  ?: @"(no device)");
    NSString *outName = [self transientForInput:NO]
                      ?: (FCAudioDeviceName(outDev) ?: @"(no device)");

    [_inZone  renderDevice:inName
              levelPercent:(inVol  < 0.0f ? -1 : (NSInteger)lroundf(inVol  * 100.0f))
                     muted:inMuted];
    [_outZone renderDevice:outName
              levelPercent:(outVol < 0.0f ? -1 : (NSInteger)lroundf(outVol * 100.0f))
                     muted:outMuted];

    // Stash the width each zone needs so the (possibly wider) bar fits both
    // full names — consumed by syncPosition. Device names change rarely, so
    // this measurement is effectively idle most ticks.
    _inZoneNeed  = [self zoneWidthForName:inName  isInput:YES muted:inMuted];
    _outZoneNeed = [self zoneWidthForName:outName isInput:NO  muted:outMuted];

    [self syncPosition];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || ![self enabled]) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    // Bottom of the stack: stackOffset 0 (geometry SSoT: OverlayStackingPositioner).
    // Bar widens past the clock when a device name needs it (centered, capped
    // at screen width); never narrower than the clock.
    CGFloat desired = _inZoneNeed + 1.0 + _outZoneNeed;   // +1 divider
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kAudioBarHeight, 0.0,
                                              kAudioBarGap, desired);
    if (!NSEqualRects(f, _bar.frame)) {
        [_bar setFrame:f display:YES];
    }
    // Re-flow zones from the stashed needs (a name swap can change the split
    // without changing total width); the method caches and no-ops when stable.
    [self layoutZonesInBarWidth:f.size.width];
    if (!_bar.visible) [_bar orderFront:nil];
    [_bar orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    // Drag-welding (2026-06-12): as a child window the bar moves ATOMICALLY
    // with the clock during drags — no chase lag. Idempotent.
    FCAttachOverlayToClock(_clock, _bar);
}

#pragma mark User actions

- (void)cycleDeviceForInput:(BOOL)isInput {
    // Explicit user choice — cancel any hijack guard watching this scope
    // (nil controller ⇒ no menu ever opened ⇒ no guard running).
    [_menuController noteExplicitDeviceSelectionForInput:isInput];
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

#pragma mark Device-selection menu support (2026-06-11 pull-out menus)

- (NSMenu *)deviceSelectionMenuForInput:(BOOL)isInput {
    if (!_menuController) {
        _menuController = [[FCAudioDeviceSelectionMenuController alloc]
                              initWithIndicator:self];
    }
    return [_menuController menuForInput:isInput];
}

- (NSArray<NSDictionary<NSString *, id> *> *)liveDevicesForInput:(BOOL)isInput {
    NSArray<NSNumber *> *ids = FCDevicesForScope(isInput);
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:ids.count];
    for (NSNumber *n in ids) {
        NSString *name = FCAudioDeviceName((AudioObjectID)n.unsignedIntValue);
        if (!name.length) continue;
        [out addObject:@{ @"id": n, @"name": name }];
    }
    return out;
}

- (AudioObjectID)currentDefaultDeviceForInput:(BOOL)isInput {
    return FCDefaultDevice(isInput);
}

- (void)selectDeviceID:(AudioObjectID)devID forInput:(BOOL)isInput {
    if (devID == kAudioObjectUnknown) return;
    FCSetDefaultDevice(devID, isInput);
    [self refresh];              // instant feedback
}

- (AudioObjectID)liveDeviceIDMatchingName:(NSString *)name forInput:(BOOL)isInput {
    if (!name.length) return 0;
    for (NSNumber *n in FCDevicesForScope(isInput)) {
        NSString *liveName = FCAudioDeviceName((AudioObjectID)n.unsignedIntValue);
        if (!liveName.length) continue;
        if ([liveName caseInsensitiveCompare:name] == NSOrderedSame ||
            [liveName rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:liveName options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (AudioObjectID)n.unsignedIntValue;
        }
    }
    return 0;
}

- (BOOL)deviceIDStillExists:(AudioObjectID)devID {
    // Name-property probe: readable on every live AudioObject regardless of
    // transport (real, virtual, aggregate); fails for reassigned/dead IDs.
    return devID != kAudioObjectUnknown && FCAudioDeviceName(devID) != nil;
}

- (void)setTransientStatus:(NSString *)status forInput:(BOOL)isInput seconds:(NSTimeInterval)seconds {
    int i = isInput ? 0 : 1;
    _transientText[i]  = [status copy];
    _transientUntil[i] = status ? (CFAbsoluteTimeGetCurrent() + seconds) : 0;
    [self refresh];              // render ⏳/✗ (or restore the device name) now
}

// Active transient text for the scope, or nil when none/expired. Expiry is
// lazy — the 1Hz tick calls refresh anyway, so no timers needed.
- (NSString *)transientForInput:(BOOL)isInput {
    int i = isInput ? 0 : 1;
    if (!_transientText[i]) return nil;
    if (CFAbsoluteTimeGetCurrent() >= _transientUntil[i]) {
        _transientText[i] = nil;
        return nil;
    }
    return _transientText[i];
}

@end
