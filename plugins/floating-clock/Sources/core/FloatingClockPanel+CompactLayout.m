// Compact-mode layouts + solar canvas — split from FloatingClockPanel+Layout
// during the 2026-06-12 modularization (Layout.m had breached the 500-line
// cap). This category owns the two LEGACY single-window layouts (local-only
// and single-market — where the window contentView IS the pill) and the
// solar-elevation canvas painter that colors them.
#import "FloatingClockPanel+CompactLayout.h"
#import "FloatingClockPanel+Runtime.h"        // clampFrameToVisibleScreen
#import "FloatingClockPanel+WindowPlacement.h"  // 2026-06-12 split
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../data/SolarEvents.h"               // FCSolarElevationDegrees
#import "../rendering/FontResolver.h"
#import "../rendering/SolarOutlinedTextRenderingView.h"
#import "SegmentBorderSpec.h"                 // spec + FCApplyBorderSpecToLayer
#import "SolarSkyColorRamp.h"                 // FCSolarCanvasColorForElevation

@implementation FloatingClockPanel (CompactLayout)

- (void)applyLocalOnlyLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    _label.font = resolveClockFont(fontSize);

    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *t = themeForId(themeId);
    _label.textColor = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
    self.backgroundColor = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:t->alpha];

    // 2026-06-11 hairline border: in this compact mode the window's
    // contentView IS the pill (rounded in clock.m) — the border lands there.
    // (User report: border showed in three-segment but vanished after the
    // double-click shrink — this path never applied it.)
    FCApplyBorderSpecToLayer(self.contentView.layer,
                         FCSegmentBorderSpecForId([d stringForKey:@"BorderStyle"]),
                         t->bg_r, t->bg_g, t->bg_b);

    // 2026-06-11 solar canvas: when CanvasColorMode is solar-*, override the
    // theme background/border with the live solar-elevation color (painted
    // on the rounded contentView layer). Theme mode must clear any stale
    // solar fill first — refreshSolarCanvas no-ops for "theme".
    self.contentView.layer.backgroundColor = [[NSColor clearColor] CGColor];
    [self refreshSolarCanvasForced:YES];

    _sessionLabel.hidden = YES;
    _localSeg.hidden = YES;
    _activeSeg.hidden = YES;
    _nextSeg.hidden = YES;
    _label.hidden = NO;

    [self tick];

    [_label sizeToFit];
    NSSize textSize = _label.frame.size;

    CGFloat w1 = ceilf(textSize.width), h1 = ceilf(textSize.height);

    CGFloat contentWidth  = w1 + 16;
    CGFloat contentHeight = h1;
    CGFloat windowWidth   = contentWidth + 32;
    CGFloat windowHeight  = contentHeight + 20;

    NSRect oldFrame = self.frame;
    // v4 iter-249: horizontal recenter on screen on every reflow per
    // user directive — widget remains L/R center-aligned as canvas
    // width changes. Vertical position preserved (user Y-drag survives).
    NSScreen *screen249 = self.screen ?: [NSScreen mainScreen];
    CGFloat centerX = NSMidX(screen249.visibleFrame);
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    _label.frame = NSInsetRect(self.contentView.bounds, 8, 8);
}

- (void)applySingleMarketLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    _label.font = resolveClockFont(fontSize);

    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *t = themeForId(themeId);
    _label.textColor = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
    self.backgroundColor = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:t->alpha];

    // 2026-06-11 hairline border on the contentView pill (see local-only note).
    FCApplyBorderSpecToLayer(self.contentView.layer,
                         FCSegmentBorderSpecForId([d stringForKey:@"BorderStyle"]),
                         t->bg_r, t->bg_g, t->bg_b);

    // 2026-06-11 solar canvas (see local-only note).
    self.contentView.layer.backgroundColor = [[NSColor clearColor] CGColor];
    [self refreshSolarCanvasForced:YES];

    NSString *marketId = [d stringForKey:@"SelectedMarket"];
    const ClockMarket *mkt = marketForId(marketId);
    BOOL marketMode = (strlen(mkt->iana) > 0);
    _sessionLabel.hidden = !marketMode;

    _localSeg.hidden = YES;
    _activeSeg.hidden = YES;
    _nextSeg.hidden = YES;
    _label.hidden = NO;

    [self tick];

    [_label sizeToFit];
    NSSize textSize = _label.frame.size;

    NSSize size2 = NSZeroSize;
    if (marketMode) {
        [_sessionLabel sizeToFit];
        size2 = _sessionLabel.frame.size;
    }

    CGFloat w1 = ceilf(textSize.width), h1 = ceilf(textSize.height);
    CGFloat w2 = ceilf(size2.width), h2 = ceilf(size2.height);

    CGFloat contentWidth  = MAX(w1, w2) + 16;
    CGFloat contentHeight = marketMode ? (h1 + h2 + 4) : h1;
    CGFloat windowWidth   = contentWidth + 32;
    CGFloat windowHeight  = contentHeight + 20;

    NSRect oldFrame = self.frame;
    // v4 iter-249: horizontal recenter on screen on every reflow per
    // user directive — widget remains L/R center-aligned as canvas
    // width changes. Vertical position preserved (user Y-drag survives).
    NSScreen *screen249 = self.screen ?: [NSScreen mainScreen];
    CGFloat centerX = NSMidX(screen249.visibleFrame);
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    if (marketMode) {
        _sessionLabel.frame = NSMakeRect(16, 10, contentWidth, h2);
        _label.frame = NSMakeRect(16, 10 + h2 + 4, contentWidth, h1);
    } else {
        _label.frame = NSInsetRect(self.contentView.bounds, 8, 8);
    }
}

#pragma mark - Solar canvas (2026-06-11 user directive: colorful, not transparent)

// Continuous solar-elevation color for the compact modes' canvas.
// Locality: the CoreLocation fix cached by FCLocationProvider — the SAME
// Latitude/Longitude defaults the sky glyph reads, so glyph and canvas can
// never disagree about where the sun is. Color: FCSolarCanvasColorForElevation
// (OKLab ramp keyed to international twilight standards — nothing scheduled
// by clock hours). Pre-first-fix fallback: a coarse local-hour sinusoid so
// the canvas is colorful from first launch; replaced when coordinates land.
- (void)refreshSolarCanvasForced:(BOOL)force {
    // Tick path: compact modes only. In solar compact the outlined renderer
    // replaces _label (which hides), so EITHER being visible means compact.
    // Forced calls come exclusively from the compact layout passes, where
    // neither may be un-hidden yet — skip the guard there.
    if (!force && _label.hidden && _labelOutline.hidden) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *mode = [d stringForKey:@"CanvasColorMode"];
    if (![mode hasPrefix:@"solar"]) return;

    double elev;
    BOOL haveLoc = [d objectForKey:@"LocationFetchedAt"] != nil
                 && ([d doubleForKey:@"Latitude"] != 0.0 || [d doubleForKey:@"Longitude"] != 0.0);
    if (haveLoc) {
        elev = FCSolarElevationDegrees([NSDate date],
                                       [d doubleForKey:@"Latitude"],
                                       [d doubleForKey:@"Longitude"]);
    } else {
        NSDateComponents *c = [[NSCalendar currentCalendar]
            components:(NSCalendarUnitHour | NSCalendarUnitMinute)
              fromDate:[NSDate date]];
        double h = (double)c.hour + (double)c.minute / 60.0;
        elev = 60.0 * sin((h - 7.0) / 24.0 * 2.0 * M_PI);  // rough: rise ~07, peak ~13
    }

    FCSolarCanvasColor sc = FCSolarCanvasColorForElevation(elev, mode);

    // Quantize to 8-bit and skip redundant AppKit writes at 1Hz — the sun
    // moves ~0.004°/s, so the visible color changes every minute or two.
    static int lastKey = -1;
    int key = ((int)lround(sc.r * 255) << 16)
            | ((int)lround(sc.g * 255) << 8)
            |  (int)lround(sc.b * 255);
    if (!force && key == lastKey) return;
    lastKey = key;

    // Solid canvas — NO transparency (explicit user directive). Paint the
    // ROUNDED contentView layer, NOT the square window background: the
    // window rect extends past the corner radius, and a solid bright fill
    // there shows as rectangular patches outside the rounded pill
    // (user-caught 2026-06-11; dark translucent themes had hidden it).
    self.backgroundColor = [NSColor clearColor];
    self.contentView.layer.backgroundColor =
        [[NSColor colorWithRed:sc.r green:sc.g blue:sc.b alpha:1.0] CGColor];
    [self invalidateShadow];   // window shadow tracks the new opaque shape
    // Text legibility is handled by the outlined attributed string in
    // tickLegacy (white fill + black stroke) — works on every ramp color.
    // Border adapts to the live canvas color (luminance-aware helper).
    FCApplyBorderSpecToLayer(self.contentView.layer,
                         FCSegmentBorderSpecForId([d stringForKey:@"BorderStyle"]),
                         sc.r, sc.g, sc.b);
}

@end
