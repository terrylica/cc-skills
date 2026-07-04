#import "VPNStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "AudioStatusIndicator.h"   // stack offset above the audio I/O bar (2026-06-11)
#import "ClockChildWindowAttachment.h"  // drag-welding (2026-06-12)
#import "OverlayPanelFactory.h"         // shared overlay construction (DRY 2026-06-12)
#import "OverlayStackingPositioner.h"   // shared stacking geometry (DRY 2026-06-12)

// Banner geometry — matches the mic-mute bar so the two stack cleanly.
static const CGFloat kVPNBannerHeight = 20.0;
static const CGFloat kVPNBannerGap    = 3.0;

@implementation FCVPNStatusIndicator {
    __weak NSPanel           *_clock;
    __weak FCMicMuteIndicator *_mic;
    NSPanel                  *_banner;
    NSTextField              *_label;
    NSView                   *_bg;
    BOOL                      _active;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel
                      micIndicator:(FCMicMuteIndicator *)micIndicator {
    if ((self = [super init])) {
        _clock  = clockPanel;
        _mic    = micIndicator;
        _active = NO;
        [self buildBanner];
        [self refresh];   // initial read; positions itself if already active
    }
    return self;
}

#pragma mark - Defaults-backed config (generic; no embedded specifics)

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"VPNIndicatorEnabled"];
}

- (NSString *)stateFilePath {
    NSString *p = [[NSUserDefaults standardUserDefaults] stringForKey:@"VPNIndicatorStateFile"];
    if (p.length == 0) p = @"~/.config/floating-clock/vpn-active";
    return [p stringByExpandingTildeInPath];
}

- (NSString *)labelText {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"VPNIndicatorLabel"];
    return s.length ? s : @"VPN";
}

- (NSColor *)barColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:@"VPNIndicatorColorHex"];
    NSColor *c = [self colorFromHex:(hex.length ? hex : @"#8B2FE6")];
    return c ?: [NSColor colorWithSRGBRed:0.55 green:0.18 blue:0.92 alpha:0.96]; // violet fallback
}

- (NSColor *)colorFromHex:(NSString *)hex {
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6) return nil;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return nil;
    CGFloat r = ((v >> 16) & 0xFF) / 255.0;
    CGFloat g = ((v >>  8) & 0xFF) / 255.0;
    CGFloat b = ( v        & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:0.96];
}

#pragma mark - Banner window

- (void)buildBanner {
    NSRect r = NSMakeRect(0, 0, 160, kVPNBannerHeight);
    _banner = FCCreateOverlayPanel(_clock, r.size, YES);   // detection-only

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    bg.layer.backgroundColor = [[self barColor] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _banner.contentView      = bg;
    _bg                      = bg;

    NSTextField *label = FCCreateBannerLabel(kVPNBannerHeight, r.size.width, [self labelText]);
    [bg addSubview:label];
    _label = label;

    [_banner orderOut:nil];   // hidden until active
}

#pragma mark - State + visibility

// 1 Hz driver. Keep label/color live with defaults edits, then show/hide
// based on the external state file (only when the feature is enabled).
- (void)refresh {
    _label.stringValue           = [self labelText];
    _bg.layer.backgroundColor    = [[self barColor] CGColor];

    BOOL active = ([self enabled] &&
                   [[NSFileManager defaultManager] fileExistsAtPath:[self stateFilePath]]);
    _active = active;
    if (active) {
        [self syncPosition];
    } else {
        FCHideOverlay(_banner);   // detach-then-hide ceremony
    }
}

- (void)syncPosition {
    if (!_clock || !_active) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    // Stack above mic-mute + audio bars when showing; geometry SSoT:
    // OverlayStackingPositioner. The stacking POLICY stays here.
    CGFloat micOffset   = (_mic && [_mic isShowing]) ? (kVPNBannerHeight + kVPNBannerGap) : 0.0;
    CGFloat audioOffset = (self.audioIndicator && [self.audioIndicator isShowing])
                          ? (kVPNBannerHeight + kVPNBannerGap) : 0.0;
    [_banner setFrame:FCComputeOverlayFrame(c, vf, kVPNBannerHeight,
                                            micOffset + audioOffset, kVPNBannerGap)
              display:YES];
    [_banner orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _banner);   // drag-welding (2026-06-12)
}

@end
