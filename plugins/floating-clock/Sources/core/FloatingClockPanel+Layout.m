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

    CGFloat topRowHeight    = localHeight  + 24;
    CGFloat bottomRowHeight = MAX(activeHeight, nextHeight) + 24;

    CGFloat activeSegWidth = ceilf(activeSize.width) + 32;
    CGFloat nextSegWidth   = ceilf(nextSize.width) + 32;
    CGFloat bottomRowInnerWidth = activeSegWidth + 4 + nextSegWidth;
    CGFloat topRowWidth = MAX(ceilf(localSize.width) + 32, bottomRowInnerWidth);

    CGFloat windowWidth  = topRowWidth + 24;
    CGFloat windowHeight = topRowHeight + 4 + bottomRowHeight + 24;

    NSRect oldFrame = self.frame;
    if (fabs(oldFrame.size.width  - windowWidth)  < 0.5 &&
        fabs(oldFrame.size.height - windowHeight) < 0.5) {
        return;
    }

    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    CGFloat bottomY = 12;
    CGFloat topY    = 12 + bottomRowHeight + 4;

    _localSeg.frame = NSMakeRect(12, topY, topRowWidth, topRowHeight);

    CGFloat bottomPairX = 12 + (topRowWidth - bottomRowInnerWidth) / 2.0;
    _activeSeg.frame = NSMakeRect(bottomPairX, bottomY, activeSegWidth, bottomRowHeight);
    _nextSeg.frame   = NSMakeRect(bottomPairX + activeSegWidth + 4, bottomY, nextSegWidth, bottomRowHeight);

    // LOCAL label height = ascender + |descender| + 25% slack for caps/diacritics.
    CGFloat ascDesc = primaryFont.ascender + fabs(primaryFont.descender);
    CGFloat localLabelH = ceilf(ascDesc + primaryFont.ascender * 0.25);
    CGFloat localLabelY = floorf((topRowHeight - localLabelH) / 2.0);
    _localSeg.timeLabel.frame     = NSMakeRect(8, localLabelY, topRowWidth - 16, localLabelH);
    _activeSeg.contentLabel.frame = NSMakeRect(8, 0, activeSegWidth - 16, bottomRowHeight);
    _nextSeg.contentLabel.frame   = NSMakeRect(8, 0, nextSegWidth - 16, bottomRowHeight);

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
