#import "VPNStatusIndicator.h"
#import "MicMuteIndicator.h"

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
    _banner = [[NSPanel alloc] initWithContentRect:r
                                         styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _banner.level                  = (_clock ? _clock.level : NSFloatingWindowLevel) + 1;
    _banner.opaque                 = NO;
    _banner.backgroundColor        = [NSColor clearColor];
    _banner.hasShadow              = YES;
    _banner.ignoresMouseEvents     = YES;   // detection-only
    _banner.becomesKeyOnlyIfNeeded = YES;
    _banner.hidesOnDeactivate      = NO;
    _banner.collectionBehavior     = NSWindowCollectionBehaviorCanJoinAllSpaces
                                   | NSWindowCollectionBehaviorStationary
                                   | NSWindowCollectionBehaviorIgnoresCycle;

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    bg.layer.backgroundColor = [[self barColor] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _banner.contentView      = bg;
    _bg                      = bg;

    CGFloat labelH = 16.0;
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, (kVPNBannerHeight - labelH) / 2.0, r.size.width, labelH)];
    label.editable        = NO;
    label.selectable      = NO;
    label.bezeled         = NO;
    label.drawsBackground = NO;
    label.alignment       = NSTextAlignmentCenter;
    label.textColor       = [NSColor whiteColor];
    label.font            = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightBold];
    label.stringValue     = [self labelText];
    label.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
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
        [_banner orderOut:nil];
    }
}

- (void)syncPosition {
    if (!_clock || !_active) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    CGFloat w = c.size.width;
    CGFloat x = c.origin.x;

    // Stack above the mic-mute bar when it's visible; otherwise above the clock.
    CGFloat micOffset = (_mic && [_mic isShowing]) ? (kVPNBannerHeight + kVPNBannerGap) : 0.0;
    CGFloat aboveY    = NSMaxY(c) + kVPNBannerGap + micOffset;
    CGFloat y;
    if (aboveY + kVPNBannerHeight <= NSMaxY(vf)) {
        y = aboveY;                                                        // preferred: above
    } else {
        y = c.origin.y - kVPNBannerGap - kVPNBannerHeight - micOffset;     // fallback: below
    }
    if (x + w > NSMaxX(vf)) x = NSMaxX(vf) - w;
    if (x < vf.origin.x)    x = vf.origin.x;

    [_banner setFrame:NSMakeRect(x, y, w, kVPNBannerHeight) display:YES];
    [_banner orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
}

@end
