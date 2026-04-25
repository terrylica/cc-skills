#import "FloatingClockPanel+Layout.h"
#import "FloatingClockPanel+Runtime.h"
#import "../segments/LocalLayoutConstants.h"  // iter-242: SSoT for LOCAL layout
#import "../rendering/AttributedStringLayoutMeasurer.h"
#import "../rendering/FontResolver.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"
#import "../actions/FloatingClockPanel+ActionHandlers.h"  // applyTheme:
#import "SegmentGap.h"                                      // FCSegmentGapPoints
#import "DensityPad.h"                                      // FCDensityPadPoints
#import "CornerRadius.h"                                    // FCCornerRadiusPoints
#import "ShadowSpec.h"                                      // FCShadowSpecForId

@implementation FloatingClockPanel (Layout)

- (void)applyDisplaySettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *mode = [d stringForKey:@"DisplayMode"];
    if (!mode) mode = @"three-segment";

    // Canvas-only transparency. User directive: text must stay fully
    // opaque, only backgrounds dim. Panel.alphaValue always 1.0; the
    // per-theme bg alpha is multiplied by CanvasOpacity in applyTheme.
    self.alphaValue = 1.0;

    // v4 iter-206: double-click-to-collapse. When user has collapsed
    // via double-click on LOCAL, treat three-segment as local-only
    // until they double-click again to restore. DisplayMode pref
    // stays at "three-segment" — SegmentsCollapsed is a transient
    // presentation toggle, not a permanent mode change.
    BOOL collapsed = [d boolForKey:@"SegmentsCollapsed"];
    if ([mode isEqualToString:@"three-segment"] && collapsed) {
        [self applyLocalOnlyLayout];
    } else if ([mode isEqualToString:@"three-segment"]) {
        [self applyThreeSegmentLayout];
    } else if ([mode isEqualToString:@"local-only"]) {
        [self applyLocalOnlyLayout];
    } else {
        [self applySingleMarketLayout];
    }

    // v4 iter-199: refresh debug-label overlays on every display pass.
    // Each segment view has a [LOCAL]/[ACTIVE]/[NEXT] corner label
    // gated by the "ShowDebugLabels" NSUserDefaults key — cheap
    // setHidden: call, safe to fire on every tick.
    [(id<FCNamedSegment>)_localSeg  fcRefreshDebugLabel];
    [(id<FCNamedSegment>)_activeSeg fcRefreshDebugLabel];
    [(id<FCNamedSegment>)_nextSeg   fcRefreshDebugLabel];
}

- (void)applyThreeSegmentLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (!_localSeg) {
        _localSeg = [[LocalSegmentView alloc] initWithFrame:NSZeroRect];
        _localSeg.panel = self;
        [self.contentView addSubview:_localSeg];
    }
    // v4 iter-251: WEEK segment lazily created — own block, sibling to LOCAL.
    if (!_weekSeg) {
        _weekSeg = [[WeekSegmentView alloc] initWithFrame:NSZeroRect];
        _weekSeg.panel = self;
        [self.contentView addSubview:_weekSeg];
    }
    if (!_activeSeg) {
        _activeSeg = [[ActiveSegmentView alloc] initWithFrame:NSZeroRect];
        _activeSeg.panel = self;
        [self.contentView addSubview:_activeSeg];
    }
    if (!_nextSeg) {
        _nextSeg = [[NextSegmentView alloc] initWithFrame:NSZeroRect];
        _nextSeg.panel = self;
        [self.contentView addSubview:_nextSeg];
    }

    _label.hidden = YES;
    _sessionLabel.hidden = YES;
    _localSeg.hidden = NO;
    BOOL showWeek = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowWeekProgress"];
    _weekSeg.hidden = !showWeek;
    _activeSeg.hidden = NO;
    _nextSeg.hidden = NO;

    const ClockTheme *tLocal  = themeForId([d stringForKey:@"LocalTheme"]);
    const ClockTheme *tActive = themeForId([d stringForKey:@"ActiveTheme"]);
    const ClockTheme *tNext   = themeForId([d stringForKey:@"NextTheme"]);

    [self applyTheme:tLocal  toSegmentView:_localSeg  textField:_localSeg.timeLabel      opacityKey:@"LocalOpacity"];
    // WEEK shares LOCAL's theme — they're a paired block visually.
    [self applyTheme:tLocal  toSegmentView:_weekSeg   textField:_weekSeg.weekBarLabel    opacityKey:@"LocalOpacity"];
    [self applyTheme:tActive toSegmentView:_activeSeg textField:_activeSeg.contentLabel  opacityKey:@"ActiveOpacity"];
    [self applyTheme:tNext   toSegmentView:_nextSeg   textField:_nextSeg.contentLabel    opacityKey:@"NextOpacity"];

    // Trigger tick to populate content (tickThreeSegment itself calls
    // relayoutThreeSegmentIfNeeded and does the sizing pass).
    [self tick];
}

- (void)relayoutThreeSegmentIfNeeded {
    if (!_activeSeg || !_nextSeg || !_localSeg) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    NSFont *primaryFont = resolveClockFont(fontSize);
    // Per-segment font sizes (v4 iter-33). Legacy deployments without
    // the key fall back to 11pt.
    CGFloat activeFS = [d doubleForKey:@"ActiveFontSize"];
    if (activeFS < 6) activeFS = 11;
    CGFloat nextFS = [d doubleForKey:@"NextFontSize"];
    if (nextFS < 6) nextFS = 11;
    // v4 iter-88: FontWeight lever applies to system-monospaced paths
    // (ACTIVE + NEXT). LOCAL primary font is iTerm2 / named-font first,
    // so weight can't drive it via API — documented limitation.
    // v4 iter-89: per-segment overrides (ActiveWeight / NextWeight)
    // fall back to the global FontWeight when unset.
    NSFont *activeFont = FCResolveMonoFont(activeFS, FCResolveSegmentWeight(@"ActiveWeight"));
    NSFont *nextFont   = FCResolveMonoFont(nextFS,   FCResolveSegmentWeight(@"NextWeight"));
    NSDictionary *primaryAttrs = @{NSFontAttributeName: primaryFont};
    NSDictionary *activeAttrs  = @{NSFontAttributeName: activeFont};
    NSDictionary *nextAttrs    = @{NSFontAttributeName: nextFont};

    _localSeg.timeLabel.font = primaryFont;
    NSString *localStr = _localSeg.timeLabel.stringValue.length > 0
        ? _localSeg.timeLabel.stringValue : @"HH:MM:SS";
    NSAttributedString *localAttr = [[NSAttributedString alloc]
        initWithString:localStr attributes:primaryAttrs];
    NSSize localSize = FCMeasureAttributedUnwrapped(localAttr);
    if (localSize.height < 10) localSize = [localStr sizeWithAttributes:primaryAttrs];
    localSize.height = ceilf(localSize.height + primaryFont.ascender * 0.3);
    _localSeg.timeLabel.alignment = NSTextAlignmentCenter;
    _localSeg.timeLabel.cell.alignment = NSTextAlignmentCenter;
    _localSeg.timeLabel.usesSingleLineMode = YES;

    NSSize activeSize = FCMeasureAttributedUnwrapped(_activeSeg.contentLabel.attributedStringValue);
    if (activeSize.height < 10) activeSize = [@"ACTIVE (—)" sizeWithAttributes:activeAttrs];

    NSSize nextSize = FCMeasureAttributedUnwrapped(_nextSeg.contentLabel.attributedStringValue);
    if (nextSize.height < 10) nextSize = [@"NEXT TO OPEN" sizeWithAttributes:nextAttrs];
    // v4 iter-205: OBSOLETE iter-61 NEXT safety margin removed.
    // Was: nextSize.height += 1.2 * lineHeight to avoid pixel-clip.
    // Why it's no longer needed: iter-205 sizes the contentLabel frame
    // EXACTLY to the measured content height (not the block height),
    // so there's no cell heightDelta to distribute — the measurer's
    // value is the frame size directly. Also removes the top-margin
    // asymmetry between ACTIVE (no safety margin) and NEXT (with),
    // which user reported as "different top blank heights" in
    // iter-204 screenshot. FCMeasureAttributedUnwrapped already
    // compensates for the terminal-newline case internally.
    (void)nextAttrs;  // suppress unused-after-safety-margin-removal

    CGFloat localHeight  = ceilf(localSize.height);
    CGFloat activeHeight = ceilf(activeSize.height);
    CGFloat nextHeight   = ceilf(nextSize.height);

    // v4 iter-35 + iter-99 + iter-116: 6 Density presets. Dispatcher
    // lives in Sources/core/DensityPad.{h,m}; test locks the catalog.
    CGFloat pad = FCDensityPadPoints([d stringForKey:@"Density"]);

    // v4 iter-231..iter-242: LOCAL height when week-progress is on.
    // Constants live in Sources/segments/LocalLayoutConstants.{h,m} —
    // editing any of them updates BOTH this calculation AND
    // LocalSegmentView.layout's frame placement in lockstep.
    // v4 iter-251: LOCAL is now a pure timestamp block. Week machinery
    // moved to its own WEEK block (sibling, separate row). When
    // ShowWeekProgress=YES, the WEEK block contributes its own row.
    BOOL hasWeekBar = [d boolForKey:@"ShowWeekProgress"]
                      && (_weekSeg.weekBarLabel.stringValue.length > 0
                          || _weekSeg.weekBarLabel.attributedStringValue.length > 0);
    CGFloat weekRowHeight   = hasWeekBar ? kFCLocalWeekFeatureRowHeight : 0.0;
    // v4 iter-252c: tight-fit LOCAL block to text height — no padding.
    // The mixed-font (mono + emoji) text baseline math made centering
    // unreliable inside a padded block. Eliminating the pad eliminates
    // the empty-space asymmetry the user reported.
    CGFloat localRowHeight  = localHeight;
    // v4 iter-204: per-segment heights — ACTIVE and NEXT each size to
    // their own measured content instead of sharing MAX. `marketRow`
    // height (the row the two sit in) still uses MAX because the
    // window is a single rectangle, but the two segments keep
    // individual heights so the shorter one doesn't over-pad.
    // `activeOwnHeight` / `nextOwnHeight` are the intrinsic block
    // heights; they align at the top of the row so the legend /
    // hrule lines stay horizontally aligned between the two blocks.
    CGFloat activeOwnHeight = activeHeight + pad;
    CGFloat nextOwnHeight   = nextHeight   + pad;
    CGFloat marketRowHeight = MAX(activeOwnHeight, nextOwnHeight);

    CGFloat localInnerWidth  = ceilf(localSize.width) + pad + 8;
    CGFloat activeSegWidth   = ceilf(activeSize.width) + pad + 8;
    CGFloat nextSegWidth     = ceilf(nextSize.width) + pad + 8;

    // v4 iter-29 + iter-108 + iter-115: 7 SegmentGap presets (flush /
    // tight / snug / normal / airy / spacious / cavernous). Dispatcher
    // lives in Sources/core/SegmentGap.{h,m} so iter-108's catalog is
    // locked by the test suite.
    CGFloat gap = FCSegmentGapPoints([d stringForKey:@"SegmentGap"]);

    CGFloat marketRowInnerWidth = activeSegWidth + gap + nextSegWidth;

    // v4 iter-28: LayoutMode picks the high-level arrangement.
    //   stacked-local-top    (default) — LOCAL top row, ACTIVE+NEXT below
    //   stacked-local-bottom          — ACTIVE+NEXT top row, LOCAL bottom
    //   horizontal-triptych           — LOCAL | ACTIVE | NEXT on a single row
    NSString *layoutMode = [d stringForKey:@"LayoutMode"];
    if (layoutMode.length == 0) layoutMode = @"stacked-local-top";

    CGFloat windowWidth = 0, windowHeight = 0;
    CGFloat localX = 0, localY = 0, localW = 0, localH = 0;
    CGFloat weekX = 0, weekY = 0, weekW = 0, weekH = 0;
    CGFloat activeX = 0, activeY = 0, activeW = 0, activeH = 0;
    CGFloat nextX = 0, nextY = 0, nextW = 0, nextH = 0;

    if ([layoutMode isEqualToString:@"horizontal-triptych"]) {
        CGFloat rowHeight = MAX(MAX(localHeight, activeHeight), nextHeight) + pad;
        windowWidth  = localInnerWidth + gap + activeSegWidth + gap + nextSegWidth + 24;
        windowHeight = rowHeight + 24;
        localX = 12;                     localY = 12; localW = localInnerWidth;  localH = rowHeight;
        activeX = localX + localW + gap; activeY = 12; activeW = activeSegWidth; activeH = rowHeight;
        nextX = activeX + activeW + gap; nextY = 12; nextW = nextSegWidth;       nextH = rowHeight;
    } else {
        CGFloat rowWidth = MAX(localInnerWidth, marketRowInnerWidth);
        windowWidth  = rowWidth + 24;
        // v4 iter-251: 4-block stacking when ShowWeekProgress=YES.
        //   localOnTop:   [LOCAL] / [WEEK] / [ACTIVE+NEXT] (top→bottom)
        //   localOnBottom: [ACTIVE+NEXT] / [WEEK] / [LOCAL]
        // weekRowHeight is 0 when the bar is empty / pref off; the
        // associated gap is also suppressed so the layout collapses
        // back to the original 2-row arrangement.
        CGFloat weekGap   = (weekRowHeight > 0) ? gap : 0.0;
        CGFloat weekTotal = weekRowHeight + weekGap;
        windowHeight = localRowHeight + gap + marketRowHeight + 24 + weekTotal;
        BOOL localOnTop = ![layoutMode isEqualToString:@"stacked-local-bottom"];
        CGFloat localRowY, weekRowY, marketRowY;
        if (localOnTop) {
            marketRowY = 12;
            weekRowY   = 12 + marketRowHeight + gap;
            localRowY  = weekRowY + weekTotal;
        } else {
            localRowY  = 12;
            weekRowY   = 12 + localRowHeight + gap;
            marketRowY = weekRowY + weekTotal;
        }

        localX = 12; localY = localRowY; localW = rowWidth; localH = localRowHeight;
        weekX  = 12; weekY  = weekRowY;  weekW  = rowWidth; weekH  = weekRowHeight;
        CGFloat pairX = 12 + (rowWidth - marketRowInnerWidth) / 2.0;
        // v4 iter-204: per-segment dynamic heights. ACTIVE + NEXT each
        // take their own measured height (activeOwnHeight /
        // nextOwnHeight) instead of both inflating to the row max.
        // Top-aligned so the legend + hrule rows stay on the same
        // horizontal line across the two blocks — much cleaner than
        // bottom-align, which would leave a ragged top edge. The
        // marketRowY anchors the row's TOP edge; each block's bottom
        // edge is (row_top - own_height).
        CGFloat marketRowTopY = marketRowY + marketRowHeight;
        activeX = pairX;               activeY = marketRowTopY - activeOwnHeight; activeW = activeSegWidth; activeH = activeOwnHeight;
        nextX   = pairX + activeW + gap; nextY = marketRowTopY - nextOwnHeight;   nextW = nextSegWidth;     nextH = nextOwnHeight;
    }

    NSRect oldFrame = self.frame;
    if (fabs(oldFrame.size.width  - windowWidth)  < 0.5 &&
        fabs(oldFrame.size.height - windowHeight) < 0.5 &&
        fabs(_localSeg.frame.origin.y - localY) < 0.5) {
        return;
    }

    // v4 iter-249: horizontal recenter on screen on every reflow per
    // user directive — widget remains L/R center-aligned as canvas
    // width changes. Vertical position preserved (user Y-drag survives).
    NSScreen *screen249 = self.screen ?: [NSScreen mainScreen];
    CGFloat centerX = NSMidX(screen249.visibleFrame);
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];

    // v4 iter-204: smooth animated resize. Before this iter, frame
    // changes on market-count deltas (open-close boundary, a new
    // exchange entering ACTIVE, etc.) snapped instantly. Now wrap
    // in NSAnimationContext with a short duration so the user sees
    // the window + segments glide into their new sizes. 150ms is
    // short enough to feel responsive (not laggy) but long enough
    // to be perceptible as intentional motion. Guard against runaway
    // animation stacking: if the size delta is tiny (< 1pt) skip the
    // animation and use instant setFrame.
    BOOL isMajorResize = fabs(oldFrame.size.width - windowWidth) > 1.0
                      || fabs(oldFrame.size.height - windowHeight) > 1.0;
    if (isMajorResize) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.15;
            ctx.allowsImplicitAnimation = YES;
            [self.animator setFrame:newFrame display:YES];
            self->_localSeg.animator.frame  = NSMakeRect(localX,  localY,  localW,  localH);
            self->_weekSeg.animator.frame   = NSMakeRect(weekX,   weekY,   weekW,   weekH);
            self->_activeSeg.animator.frame = NSMakeRect(activeX, activeY, activeW, activeH);
            self->_nextSeg.animator.frame   = NSMakeRect(nextX,   nextY,   nextW,   nextH);
        } completionHandler:nil];
    } else {
        [self setFrame:newFrame display:YES animate:NO];
        _localSeg.frame  = NSMakeRect(localX,  localY,  localW,  localH);
        _weekSeg.frame   = NSMakeRect(weekX,   weekY,   weekW,   weekH);
        _activeSeg.frame = NSMakeRect(activeX, activeY, activeW, activeH);
        _nextSeg.frame   = NSMakeRect(nextX,   nextY,   nextW,   nextH);
    }

    // v4 iter-30 / iter-97 / iter-117: 8 CornerStyle presets. Dispatcher
    // lives in Sources/core/CornerRadius.{h,m}; test locks the catalog.
    NSString *cornerId = [d stringForKey:@"CornerStyle"];
    _localSeg.layer.cornerRadius  = FCCornerRadiusPoints(cornerId, localW,  localH);
    _weekSeg.layer.cornerRadius   = FCCornerRadiusPoints(cornerId, weekW,   weekH);
    _activeSeg.layer.cornerRadius = FCCornerRadiusPoints(cornerId, activeW, activeH);
    _nextSeg.layer.cornerRadius   = FCCornerRadiusPoints(cornerId, nextW,   nextH);

    // v4 iter-31 / iter-93: ShadowStyle — adds depth / glow around each segment.
    //   none       (default) — flat, no shadow
    //   subtle     — faint drop shadow beneath
    //   lifted     — stronger drop shadow (card-like)
    //   glow       — outer glow using the segment's foreground color
    //   crisp      — iter-93: sharp pixel-hard drop, radius 0 (stamp feel)
    //   plinth     — iter-93: deep dramatic drop (stage / pedestal)
    //   halo       — iter-93: background-tinted ambient bloom
    // Segments' own layers don't set masksToBounds so their shadows
    // render outside their bounds; contentView's masksToBounds does
    // clip at the window edge, but the 12pt margin gives headroom.
    // v4 iter-120: numeric spec extracted to Sources/core/ShadowSpec.{h,m};
    // caller owns the CALayer write + theme-color substitution.
    FCShadowSpec ss = FCShadowSpecForId([d stringForKey:@"ShadowStyle"]);
    const ClockTheme *tLocal2  = themeForId([d stringForKey:@"LocalTheme"]);
    const ClockTheme *tActive2 = themeForId([d stringForKey:@"ActiveTheme"]);
    const ClockTheme *tNext2   = themeForId([d stringForKey:@"NextTheme"]);
    void (^applyShadow)(CALayer *, const ClockTheme *) = ^(CALayer *layer, const ClockTheme *t) {
        if (!ss.enabled) { layer.shadowOpacity = 0; return; }
        NSColor *col;
        switch (ss.colorSource) {
            case FCShadowColorThemeForeground:
                col = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
                break;
            case FCShadowColorThemeBackground:
                col = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:1.0];
                break;
            default:
                col = [NSColor blackColor];
        }
        layer.shadowColor   = col.CGColor;
        layer.shadowOpacity = ss.opacity;
        layer.shadowOffset  = CGSizeMake(ss.offsetX, ss.offsetY);
        layer.shadowRadius  = ss.radius;
    };
    applyShadow(_localSeg.layer,  tLocal2);
    applyShadow(_activeSeg.layer, tActive2);
    applyShadow(_nextSeg.layer,   tNext2);

    // Optical centering for LOCAL.
    //
    // Fonts are asymmetric around the baseline: ascender (~19pt at size 24)
    // is bigger than |descender| (~5pt). The bounding-box geometric center
    // places baseline ABOVE the middle of the box — so most ink (which
    // lives between the baseline and cap-height, above the baseline) drifts
    // upward. "Fri Apr 24 01:57:23" has only one descender (p in 'Apr'),
    // so the visible mass is strongly top-biased.
    //
    // Compensate by shifting the frame DOWN (smaller y in unflipped
    // view coords) by half the asymmetry. Result: visible ink lies on the
    // row's midline to the eye, not just in its metric center.
    CGFloat boundingH2 = primaryFont.boundingRectForFont.size.height;
    CGFloat leading = primaryFont.leading > 0 ? primaryFont.leading : primaryFont.ascender * 0.2;
    CGFloat localLabelH = ceilf(boundingH2 + leading * 2);
    CGFloat asymmetry = primaryFont.ascender - fabs(primaryFont.descender);
    CGFloat localLabelY = floorf((localH - localLabelH) / 2.0 - asymmetry / 2.0);
    _localSeg.timeLabel.frame     = NSMakeRect(8, localLabelY, localW - 16, localLabelH);
    // v4 iter-205: size contentLabel frame EXACTLY to measured content
    // height + position with uniform pad/2 top inset inside the block.
    // Block height = contentHeight + pad (iter-204); label height =
    // contentHeight; label y = pad/2 → identical top inset on ACTIVE
    // and NEXT regardless of their content heights. Fully dynamic:
    // derives from measured content + user-chosen Density pad, zero
    // hard-coded magic numbers. Eliminates the "different top blank"
    // asymmetry user reported against iter-204.
    CGFloat halfPad = pad / 2.0;
    _activeSeg.contentLabel.frame = NSMakeRect(8, halfPad, activeW - 16, ceilf(activeSize.height));
    _nextSeg.contentLabel.frame   = NSMakeRect(8, halfPad, nextW - 16, ceilf(nextSize.height));

    _localSeg.timeLabel.font      = primaryFont;
    // v4 iter-231: week-bar uses the smaller monospace font (matches
    // ACTIVE/NEXT scale) so the day-tick separators line up cleanly
    // with the dot/block glyphs and the row stays compact below
    // the larger primary timestamp.
    _weekSeg.weekBarLabel.font           = activeFont;
    // v4 iter-234: day-letters use SAME font as bar so the cellsPerDay
    // slots have identical widths in both rows — letters land directly
    // above their day-group's center column.
    _weekSeg.weekDayLabelsLabel.font     = activeFont;
    _activeSeg.contentLabel.font  = activeFont;
    _nextSeg.contentLabel.font    = nextFont;
}

- (void)applyLocalOnlyLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    _label.font = resolveClockFont(fontSize);

    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *t = themeForId(themeId);
    _label.textColor = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
    self.backgroundColor = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:t->alpha];

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

@end
