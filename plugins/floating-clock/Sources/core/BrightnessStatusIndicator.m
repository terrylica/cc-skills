#import "BrightnessStatusIndicator.h"
#import "BrightnessBarZoneView.h"
#import "FCXDRBrightness.h"
#import "DisplayBrightnessHelpers.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import "ClockChildWindowAttachment.h"
#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "VPNStatusIndicator.h"
#import "NetworkStatusIndicator.h"

// Matches the other overlay rails so the stack reads as one column.
static const CGFloat kBrightBarHeight = 20.0;
static const CGFloat kBrightBarGap    = 3.0;
static const CGFloat kMinBarW         = 132.0;   // track needs room to be a track

// Safety valve. A boost holds the mini-LED array above its normal duty cycle,
// which costs power and heat, and an accidental scroll is easy on a 7 pt
// track. After this long without the user touching the control, drop back to
// 100 %. The ordinary 0..100 range is NOT timed out — only the boost.
static const NSTimeInterval kBoostIdleTimeout = 30.0 * 60.0;

@implementation FCBrightnessStatusIndicator {
    __weak NSPanel        *_clock;
    NSPanel               *_bar;
    FCBrightnessZoneView  *_zone;
    CGFloat                _contentNeed;
    CGFloat                _lastBarW;
    CFAbsoluteTime         _lastUserTouch;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // Belt and braces — the gamma override also reverts on process death.
    [[FCBrightnessEngine shared] releaseBoost];
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _lastBarW = -1.0;
        _lastUserTouch = CFAbsoluteTimeGetCurrent();
        [self buildBar];

        // Repaint the instant the engine's state moves rather than waiting up
        // to a second for the next tick — EDR engagement takes ~2 s and the
        // user should see it progressing.
        __weak typeof(self) weakSelf = self;
        [FCBrightnessEngine shared].changeHandler = ^{ [weakSelf renderFromEngine]; };

        // Any peer overlay growing or shrinking changes the agreed stack
        // width, and this bar may already have positioned for the old one.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification
                                                   object:nil];
        [self refresh];
    }
    return self;
}

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BrightnessBarEnabled"];
}

- (BOOL)isShowing { return [self enabled]; }

#pragma mark Bar window

- (void)buildBar {
    NSRect r = NSMakeRect(0, 0, 200, kBrightBarHeight);
    _bar = FCCreateOverlayPanel(_clock, r.size, NO);   // interactive

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    // Same dual-layer treatment as the other bars: hairline border defines
    // the edge on pure black where the panel shadow is invisible, elevated
    // surface separates the fill from #000.
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth     = 1.0;
    bg.layer.borderColor     = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _bar.contentView         = bg;

    _zone = [[FCBrightnessZoneView alloc] initWithFrame:r owner:self];
    _zone.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [bg addSubview:_zone];

    [_bar orderOut:nil];   // shown on first refresh when enabled
}

#pragma mark Refresh

- (void)refresh {
    if (![self enabled]) {
        FCHideOverlay(_bar);
        // Stop widening the stack while hidden, or the other rails stay
        // padded to a width nothing is using.
        [[FCOverlayWidthConsensus shared] clearOverlay:NSStringFromClass(self.class)];
        return;
    }

    FCBrightnessEngine *e = [FCBrightnessEngine shared];
    [e poll];

    // Idle safety valve — see kBoostIdleTimeout.
    if (e.level > 100 &&
        (CFAbsoluteTimeGetCurrent() - _lastUserTouch) > kBoostIdleTimeout) {
        [e setLevel:100];
    }

    [self renderFromEngine];
}

- (void)renderFromEngine {
    if (![self enabled]) return;
    FCBrightnessEngine *e = [FCBrightnessEngine shared];

    BOOL available = e.sliderAvailable;
    BOOL engaging  = (e.boostState == FCBrightnessBoostEngaging);
    // "Clamped" means the panel could not deliver what was asked for. Showing
    // it beats silently under-delivering and letting the number lie.
    BOOL clamped   = (e.level > 100) &&
                     (e.appliedFactor + 1e-6 < (double)e.level / 100.0) &&
                     !engaging;

    BOOL changed = [_zone renderLevel:e.level
                             maxLevel:e.maximumLevel
                              clamped:clamped
                             engaging:engaging
                            available:available];

    // Re-measure ONLY when the zone actually redrew. naturalContentWidth runs
    // a text layout pass, and this bar's content changes just when the user
    // touches it — so an unconditional 1 Hz measurement was most of the rail's
    // CPU cost for no benefit. Measured from what the zone actually drew, so
    // the published need can never drift from the rendered content. Published
    // here in -refresh and NOT inside syncPosition, because setNeed: posts the
    // consensus change notification, which would re-enter syncPosition.
    if (changed || _contentNeed <= 0.0) {
        _contentNeed = [_zone naturalContentWidth];
        if (_contentNeed < kMinBarW) _contentNeed = kMinBarW;
        [[FCOverlayWidthConsensus shared] setNeed:_contentNeed
                                       forOverlay:NSStringFromClass(self.class)];
    }
    // syncPosition still runs every tick: the clock resizes and recenters on
    // its own schedule and the bar must stay glued to it. It is frame
    // arithmetic with an early-out on an unchanged rect, not a layout pass.
    [self syncPosition];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || ![self enabled]) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    // TOP of the indicator stack: shift up one slot per visible junior, so
    // none of the existing four need to learn about this one. Stacking POLICY
    // lives here; the geometry SSoT is OverlayStackingPositioner.
    CGFloat slot = kBrightBarHeight + kBrightBarGap;
    CGFloat offset = 0.0;
    if (self.audioIndicator   && [self.audioIndicator   isShowing]) offset += slot;
    if (self.micIndicator     && [self.micIndicator     isShowing]) offset += slot;
    if (self.vpnIndicator     && [self.vpnIndicator     isShowing]) offset += slot;
    if (self.networkIndicator && [self.networkIndicator isShowing]) offset += slot;

    // Width is the STACK's agreed width, not this bar's own need, so every
    // rail shares one left and right edge. See OverlayWidthConsensus.h.
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kBrightBarHeight, offset,
                                              kBrightBarGap, agreed);
    if (!NSEqualRects(f, _bar.frame)) [_bar setFrame:f display:YES];
    if (fabs(f.size.width - _lastBarW) >= 0.5) {
        _lastBarW = f.size.width;
        _zone.frame = NSMakeRect(0, 0, f.size.width, kBrightBarHeight);
        _zone.needsLayout = YES;
        _zone.needsDisplay = YES;
    }
    if (!_bar.visible) [_bar orderFront:nil];
    [_bar orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _bar);   // drag-welding; idempotent
}

#pragma mark User actions

- (void)setLevel:(NSInteger)level {
    _lastUserTouch = CFAbsoluteTimeGetCurrent();
    [[FCBrightnessEngine shared] setLevel:level];
    [self renderFromEngine];
}

- (void)adjustLevelBy:(NSInteger)delta {
    FCBrightnessEngine *e = [FCBrightnessEngine shared];
    [self setLevel:FCApplyLevelDelta(e.level, delta, e.maximumLevel)];
}

// Click anywhere outside the track and the control cells cycles the presets —
// preserving the audio bar's "click the wide part to advance" muscle memory.
- (void)cyclePreset {
    FCBrightnessEngine *e = [FCBrightnessEngine shared];
    NSArray<NSNumber *> *stops = [self presetStops];
    NSInteger current = e.level;
    for (NSNumber *n in stops) {
        if (n.integerValue > current + 1) { [self setLevel:n.integerValue]; return; }
    }
    [self setLevel:stops.firstObject.integerValue];
}

- (NSArray<NSNumber *> *)presetStops {
    FCBrightnessEngine *e = [FCBrightnessEngine shared];
    NSMutableArray *a = [@[ @25, @50, @75, @100 ] mutableCopy];
    if (e.maximumLevel > 100) [a addObject:@(e.maximumLevel)];
    return a;
}

- (NSMenu *)presetMenu {
    FCBrightnessEngine *e = [FCBrightnessEngine shared];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Brightness"];

    NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"DISPLAY BRIGHTNESS"
                                                 action:NULL keyEquivalent:@""];
    hdr.enabled = NO;
    [m addItem:hdr];

    if (!e.sliderAvailable) {
        NSMenuItem *none = [[NSMenuItem alloc]
            initWithTitle:@"No controllable built-in display" action:NULL keyEquivalent:@""];
        none.enabled = NO;
        [m addItem:none];
        return m;
    }

    for (NSNumber *n in [self presetStops]) {
        NSInteger v = n.integerValue;
        NSString *title = (v > 100)
            ? [NSString stringWithFormat:@"%ld%%  (XDR boost)", (long)v]
            : [NSString stringWithFormat:@"%ld%%", (long)v];
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title
                                                    action:@selector(menuPickLevel:)
                                             keyEquivalent:@""];
        it.target = self;
        it.representedObject = n;
        it.state = (labs((long)(e.level - v)) <= 1) ? NSControlStateValueOn
                                                    : NSControlStateValueOff;
        [m addItem:it];
    }

    [m addItem:[NSMenuItem separatorItem]];

    if (e.maximumLevel <= 100) {
        NSMenuItem *why = [[NSMenuItem alloc]
            initWithTitle:@"No XDR headroom on this display" action:NULL keyEquivalent:@""];
        why.enabled = NO;
        [m addItem:why];
    } else {
        NSString *s;
        switch (e.boostState) {
            case FCBrightnessBoostEngaging:
                s = @"XDR: engaging…"; break;
            case FCBrightnessBoostActive:
                s = [NSString stringWithFormat:@"XDR: active — %.2fx (headroom %.2fx)",
                               e.appliedFactor, e.headroom]; break;
            case FCBrightnessBoostReleasing:
                s = @"XDR: releasing…"; break;
            default:
                s = [NSString stringWithFormat:@"XDR: off (headroom %.2fx available)",
                               e.headroom]; break;
        }
        NSMenuItem *st = [[NSMenuItem alloc] initWithTitle:s action:NULL keyEquivalent:@""];
        st.enabled = NO;
        [m addItem:st];
    }

    // Auto-brightness silently walks the slider back, so say so rather than
    // letting the user think the control is broken. Deliberately NOT changed
    // for them — that would be a second, undeclared system mutation.
    if (e.ambientCompensationEnabled) {
        NSMenuItem *alc = [[NSMenuItem alloc]
            initWithTitle:@"⚠︎ Auto-brightness is on — it may override this"
                   action:NULL keyEquivalent:@""];
        alc.enabled = NO;
        [m addItem:alc];
    }
    return m;
}

- (void)menuPickLevel:(NSMenuItem *)sender {
    if (![sender.representedObject isKindOfClass:[NSNumber class]]) return;
    [self setLevel:[(NSNumber *)sender.representedObject integerValue]];
}

@end
