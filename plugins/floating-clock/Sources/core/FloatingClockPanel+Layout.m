#import "FloatingClockPanel+Layout.h"
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
    NSFont *contentFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSDictionary *primaryAttrs = @{NSFontAttributeName: primaryFont};
    NSDictionary *contentAttrs = @{NSFontAttributeName: contentFont};

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
    if (activeSize.height < 10) activeSize = [@"ACTIVE (—)" sizeWithAttributes:contentAttrs];

    NSSize nextSize = FCMeasureAttributedUnwrapped(_nextSeg.contentLabel.attributedStringValue);
    if (nextSize.height < 10) nextSize = [@"NEXT TO OPEN" sizeWithAttributes:contentAttrs];

    CGFloat localHeight  = ceilf(localSize.height);
    CGFloat activeHeight = ceilf(activeSize.height);
    CGFloat nextHeight   = ceilf(nextSize.height);

    CGFloat localRowHeight  = localHeight  + 24;
    CGFloat marketRowHeight = MAX(activeHeight, nextHeight) + 24;

    CGFloat localInnerWidth  = ceilf(localSize.width) + 32;
    CGFloat activeSegWidth   = ceilf(activeSize.width) + 32;
    CGFloat nextSegWidth     = ceilf(nextSize.width) + 32;
    CGFloat marketRowInnerWidth = activeSegWidth + 4 + nextSegWidth;

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
        // Single row: LOCAL | ACTIVE | NEXT — each as-tall-as-needed, shared height.
        CGFloat rowHeight = MAX(MAX(localHeight, activeHeight), nextHeight) + 24;
        windowWidth  = localInnerWidth + 4 + activeSegWidth + 4 + nextSegWidth + 24;  // 12pt L+R
        windowHeight = rowHeight + 24;  // 12pt T+B
        localX = 12;               localY = 12; localW = localInnerWidth;  localH = rowHeight;
        activeX = localX + localW + 4; activeY = 12; activeW = activeSegWidth; activeH = rowHeight;
        nextX = activeX + activeW + 4; nextY = 12; nextW = nextSegWidth;   nextH = rowHeight;
    } else {
        // Two-row stacked. Top/bottom order varies by mode.
        CGFloat rowWidth = MAX(localInnerWidth, marketRowInnerWidth);
        windowWidth  = rowWidth + 24;
        windowHeight = localRowHeight + 4 + marketRowHeight + 24;
        BOOL localOnTop = ![layoutMode isEqualToString:@"stacked-local-bottom"];
        CGFloat localRowY  = localOnTop ? (12 + marketRowHeight + 4) : 12;
        CGFloat marketRowY = localOnTop ? 12 : (12 + localRowHeight + 4);

        localX = 12; localY = localRowY; localW = rowWidth; localH = localRowHeight;
        CGFloat pairX = 12 + (rowWidth - marketRowInnerWidth) / 2.0;
        activeX = pairX;               activeY = marketRowY; activeW = activeSegWidth; activeH = marketRowHeight;
        nextX = pairX + activeW + 4;   nextY = marketRowY;   nextW = nextSegWidth;     nextH = marketRowHeight;
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

    // LOCAL label centered inside its row (ascender + |descender| + 25% slack).
    // Use boundingRectForFont for the true glyph bounding box — NSFont.ascender
    // clips cap-height extensions for many fonts (F, A, uppercase digits),
    // causing top-shave at small-to-mid sizes. boundingRectForFont.height
    // gives the full outline box; pad 6pt more for extra safety margin.
    CGFloat boundingH = primaryFont.boundingRectForFont.size.height;
    CGFloat ascDesc   = primaryFont.ascender + fabs(primaryFont.descender);
    CGFloat localLabelH = ceilf(MAX(boundingH, ascDesc) + 6);
    CGFloat localLabelY = floorf((localH - localLabelH) / 2.0);
    _localSeg.timeLabel.frame     = NSMakeRect(8, localLabelY, localW - 16, localLabelH);
    _activeSeg.contentLabel.frame = NSMakeRect(8, 0, activeW - 16, activeH);
    _nextSeg.contentLabel.frame   = NSMakeRect(8, 0, nextW - 16, nextH);

    _localSeg.timeLabel.font      = primaryFont;
    _activeSeg.contentLabel.font  = contentFont;
    _nextSeg.contentLabel.font    = contentFont;
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
