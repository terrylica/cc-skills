#import "FloatingClockPanel+Layout.h"
#import "FloatingClockPanel+Runtime.h"
#import "../rendering/AttributedStringLayoutMeasurer.h"
#import "../rendering/FontResolver.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"
#import "../actions/FloatingClockPanel+ActionHandlers.h"  // applyTheme:

@implementation FloatingClockPanel (Layout)

- (void)applyDisplaySettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *mode = [d stringForKey:@"DisplayMode"];
    if (!mode) mode = @"three-segment";

    // Canvas-only transparency. User directive: text must stay fully
    // opaque, only backgrounds dim. Panel.alphaValue always 1.0; the
    // per-theme bg alpha is multiplied by CanvasOpacity in applyTheme.
    self.alphaValue = 1.0;

    if ([mode isEqualToString:@"three-segment"]) {
        [self applyThreeSegmentLayout];
    } else if ([mode isEqualToString:@"local-only"]) {
        [self applyLocalOnlyLayout];
    } else {
        [self applySingleMarketLayout];
    }
}

- (void)applyThreeSegmentLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (!_localSeg) {
        _localSeg = [[LocalSegmentView alloc] initWithFrame:NSZeroRect];
        _localSeg.panel = self;
        [self.contentView addSubview:_localSeg];
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
    _activeSeg.hidden = NO;
    _nextSeg.hidden = NO;

    const ClockTheme *tLocal  = themeForId([d stringForKey:@"LocalTheme"]);
    const ClockTheme *tActive = themeForId([d stringForKey:@"ActiveTheme"]);
    const ClockTheme *tNext   = themeForId([d stringForKey:@"NextTheme"]);

    [self applyTheme:tLocal  toSegmentView:_localSeg  textField:_localSeg.timeLabel];
    [self applyTheme:tActive toSegmentView:_activeSeg textField:_activeSeg.contentLabel];
    [self applyTheme:tNext   toSegmentView:_nextSeg   textField:_nextSeg.contentLabel];

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
    NSFont *activeFont = [NSFont monospacedSystemFontOfSize:activeFS weight:NSFontWeightMedium];
    NSFont *nextFont   = [NSFont monospacedSystemFontOfSize:nextFS   weight:NSFontWeightMedium];
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
    // v4 iter-61: NEXT layout now renders 2 lines per market (iter-60). The
    // measurer underestimates by ~1 line-height when the trailing content
    // isn't terminated by a newline (our last market has none). Add a
    // safety margin so VerticallyCenteredTextFieldCell doesn't pixel-clip
    // the last bottom line.
    NSFont *nextMeasureFont = [nextAttrs objectForKey:NSFontAttributeName] ?: [NSFont systemFontOfSize:11];
    CGFloat nextLineHeight = [[[NSLayoutManager alloc] init] defaultLineHeightForFont:nextMeasureFont];
    nextSize.height = ceilf(nextSize.height + nextLineHeight * 1.2);

    CGFloat localHeight  = ceilf(localSize.height);
    CGFloat activeHeight = ceilf(activeSize.height);
    CGFloat nextHeight   = ceilf(nextSize.height);

    // v4 iter-35: Density profile — scales inner-row padding.
    //   compact      12pt (half of default)
    //   default      24pt (baseline, matches prior hardcoded padding)
    //   comfortable  36pt
    //   spacious     48pt
    NSString *densityId = [d stringForKey:@"Density"];
    CGFloat pad = 24;
    if      ([densityId isEqualToString:@"compact"])     pad = 12;
    else if ([densityId isEqualToString:@"comfortable"]) pad = 36;
    else if ([densityId isEqualToString:@"spacious"])    pad = 48;

    CGFloat localRowHeight  = localHeight  + pad;
    CGFloat marketRowHeight = MAX(activeHeight, nextHeight) + pad;

    CGFloat localInnerWidth  = ceilf(localSize.width) + pad + 8;
    CGFloat activeSegWidth   = ceilf(activeSize.width) + pad + 8;
    CGFloat nextSegWidth     = ceilf(nextSize.width) + pad + 8;

    // v4 iter-29: SegmentGap pref — controls inter-segment breathing room.
    NSString *gapId = [d stringForKey:@"SegmentGap"];
    CGFloat gap = 4;  // "normal" default
    if      ([gapId isEqualToString:@"tight"])    gap = 2;
    else if ([gapId isEqualToString:@"snug"])     gap = 3;
    else if ([gapId isEqualToString:@"airy"])     gap = 8;
    else if ([gapId isEqualToString:@"spacious"]) gap = 14;

    CGFloat marketRowInnerWidth = activeSegWidth + gap + nextSegWidth;

    // v4 iter-28: LayoutMode picks the high-level arrangement.
    //   stacked-local-top    (default) — LOCAL top row, ACTIVE+NEXT below
    //   stacked-local-bottom          — ACTIVE+NEXT top row, LOCAL bottom
    //   horizontal-triptych           — LOCAL | ACTIVE | NEXT on a single row
    NSString *layoutMode = [d stringForKey:@"LayoutMode"];
    if (layoutMode.length == 0) layoutMode = @"stacked-local-top";

    CGFloat windowWidth = 0, windowHeight = 0;
    CGFloat localX = 0, localY = 0, localW = 0, localH = 0;
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
        windowHeight = localRowHeight + gap + marketRowHeight + 24;
        BOOL localOnTop = ![layoutMode isEqualToString:@"stacked-local-bottom"];
        CGFloat localRowY  = localOnTop ? (12 + marketRowHeight + gap) : 12;
        CGFloat marketRowY = localOnTop ? 12 : (12 + localRowHeight + gap);

        localX = 12; localY = localRowY; localW = rowWidth; localH = localRowHeight;
        CGFloat pairX = 12 + (rowWidth - marketRowInnerWidth) / 2.0;
        activeX = pairX;                 activeY = marketRowY; activeW = activeSegWidth; activeH = marketRowHeight;
        nextX = pairX + activeW + gap;   nextY = marketRowY;   nextW = nextSegWidth;     nextH = marketRowHeight;
    }

    NSRect oldFrame = self.frame;
    if (fabs(oldFrame.size.width  - windowWidth)  < 0.5 &&
        fabs(oldFrame.size.height - windowHeight) < 0.5 &&
        fabs(_localSeg.frame.origin.y - localY) < 0.5) {
        return;
    }

    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    _localSeg.frame  = NSMakeRect(localX,  localY,  localW,  localH);
    _activeSeg.frame = NSMakeRect(activeX, activeY, activeW, activeH);
    _nextSeg.frame   = NSMakeRect(nextX,   nextY,   nextW,   nextH);

    // v4 iter-30: CornerStyle applies to all three segments uniformly.
    //   sharp     0pt
    //   rounded   6pt  (default, matches prior hardcoded radius)
    //   squircle  14pt
    //   pill      half the segment's shorter axis (fully rounded ends)
    NSString *cornerId = [d stringForKey:@"CornerStyle"];
    CGFloat (^cornerRadiusFor)(CGFloat, CGFloat) = ^CGFloat(CGFloat w, CGFloat h) {
        if ([cornerId isEqualToString:@"sharp"])    return 0.0;
        if ([cornerId isEqualToString:@"squircle"]) return 14.0;
        if ([cornerId isEqualToString:@"pill"])     return MIN(w, h) / 2.0;
        return 6.0;  // "rounded" default
    };
    _localSeg.layer.cornerRadius  = cornerRadiusFor(localW, localH);
    _activeSeg.layer.cornerRadius = cornerRadiusFor(activeW, activeH);
    _nextSeg.layer.cornerRadius   = cornerRadiusFor(nextW, nextH);

    // v4 iter-31: ShadowStyle — adds depth / glow around each segment.
    //   none    (default) — flat, no shadow
    //   subtle  — faint drop shadow beneath
    //   lifted  — stronger drop shadow (card-like)
    //   glow    — outer glow using the segment's foreground color
    // Segments' own layers don't set masksToBounds so their shadows
    // render outside their bounds; contentView's masksToBounds does
    // clip at the window edge, but the 12pt margin gives headroom.
    NSString *shadowId = [d stringForKey:@"ShadowStyle"];
    const ClockTheme *tLocal2  = themeForId([d stringForKey:@"LocalTheme"]);
    const ClockTheme *tActive2 = themeForId([d stringForKey:@"ActiveTheme"]);
    const ClockTheme *tNext2   = themeForId([d stringForKey:@"NextTheme"]);
    void (^applyShadow)(CALayer *, const ClockTheme *) = ^(CALayer *layer, const ClockTheme *t) {
        if ([shadowId isEqualToString:@"subtle"]) {
            layer.shadowColor = [NSColor blackColor].CGColor;
            layer.shadowOpacity = 0.35;
            layer.shadowOffset = CGSizeMake(0, -2);
            layer.shadowRadius = 3;
        } else if ([shadowId isEqualToString:@"lifted"]) {
            layer.shadowColor = [NSColor blackColor].CGColor;
            layer.shadowOpacity = 0.55;
            layer.shadowOffset = CGSizeMake(0, -4);
            layer.shadowRadius = 6;
        } else if ([shadowId isEqualToString:@"glow"]) {
            NSColor *fg = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
            layer.shadowColor = fg.CGColor;
            layer.shadowOpacity = 0.6;
            layer.shadowOffset = CGSizeMake(0, 0);
            layer.shadowRadius = 6;
        } else {
            layer.shadowOpacity = 0.0;
        }
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
    _activeSeg.contentLabel.frame = NSMakeRect(8, 0, activeW - 16, activeH);
    _nextSeg.contentLabel.frame   = NSMakeRect(8, 0, nextW - 16, nextH);

    _localSeg.timeLabel.font      = primaryFont;
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
    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
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
    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
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
