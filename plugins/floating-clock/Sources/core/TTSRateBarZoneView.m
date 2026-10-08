#import "TTSRateBarZoneView.h"
#import "TTSRateStatusIndicator.h"
#import "TTSRateHelpers.h"

// Geometry mirrors the brightness rail so the stack reads as one column.
static const CGFloat kGlyphW    = 14.0;   // − and + hit cells
static const CGFloat kLevelW    = 42.0;   // "1.25×"
static const CGFloat kIconW     = 18.0;
static const CGFloat kPadX      = 6.0;
static const CGFloat kTrackMinW = 70.0;   // seven detents need room to read as seven
static const CGFloat kLabelH    = 14.0;
static const CGFloat kTrackH    = 7.0;

@implementation FCTTSRateZoneView {
    NSTextField *_iconLabel;
    NSTextField *_minusLabel;
    NSTextField *_levelLabel;
    NSTextField *_plusLabel;
    NSString    *_renderKey;
    double       _rate;
    BOOL         _dragging;
    CGFloat      _scrollAcc;
}

// A trackpad swipe delivers dozens of precise scroll events; one 0.05 step per
// event would race to 3x. Accumulate precise deltas and step once per this many
// points. A wheel mouse (not precise) steps once per notch.
static const CGFloat kScrollPointsPerStep = 8.0;

static NSTextField *FCTTSLabel(NSFont *font, NSColor *color, NSTextAlignment align) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSZeroRect];
    l.editable = NO; l.selectable = NO; l.bezeled = NO; l.drawsBackground = NO;
    l.font = font; l.textColor = color; l.alignment = align;
    return l;
}

- (instancetype)initWithFrame:(NSRect)frame owner:(FCTTSRateStatusIndicator *)owner {
    if ((self = [super initWithFrame:frame])) {
        _owner = owner;
        _rate  = FCTTSRateMin;
        NSFont *glyphFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightHeavy];
        NSFont *levelFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
        NSColor *dim = [NSColor colorWithWhite:1.0 alpha:0.55];

        _iconLabel  = FCTTSLabel([NSFont systemFontOfSize:11], dim, NSTextAlignmentCenter);
        _minusLabel = FCTTSLabel(glyphFont, dim, NSTextAlignmentCenter);
        _levelLabel = FCTTSLabel(levelFont, [NSColor whiteColor], NSTextAlignmentCenter);
        _plusLabel  = FCTTSLabel(glyphFont, dim, NSTextAlignmentCenter);
        _iconLabel.stringValue  = @"🔊";
        _minusLabel.stringValue = @"−";
        _plusLabel.stringValue  = @"+";

        _iconLabel.toolTip  = @"Text-to-speech speed — drag the track to a detent, right-click for presets";
        _minusLabel.toolTip = @"Slower (scroll for 0.05 steps); never below normal speed";
        _plusLabel.toolTip  = @"Faster (scroll for 0.05 steps), up to 3×";
        _levelLabel.toolTip = @"Playback rate; 1× is the reader's normal speed. Applies mid-sentence.";

        [self addSubview:_iconLabel];
        [self addSubview:_minusLabel];
        [self addSubview:_levelLabel];
        [self addSubview:_plusLabel];
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return v ? self : nil;
}

#pragma mark Rendering

- (BOOL)renderRate:(double)rate {
    NSString *key = [NSString stringWithFormat:@"%.2f", rate];
    if ([key isEqualToString:_renderKey]) return NO;   // steady-state tick does nothing
    _renderKey = key;
    _rate = rate;
    _levelLabel.stringValue = FCTTSRateLabel(rate);
    // Teal once faster than normal, so "sped up" reads at a glance.
    NSColor *teal = [NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.85 alpha:1.0];
    BOOL fast = rate > FCTTSRateMin + 1e-6;
    _levelLabel.textColor = fast ? teal : [NSColor whiteColor];
    _iconLabel.textColor  = fast ? teal : [NSColor colorWithWhite:1.0 alpha:0.55];
    self.needsDisplay = YES;
    return YES;
}

- (NSRect)trackRect {
    NSRect b = self.bounds;
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;
    CGFloat x0 = kPadX + kIconW + 4.0;
    CGFloat w  = xMinus - 6.0 - x0;
    if (w < 8.0) w = 8.0;
    return NSMakeRect(x0, floor((NSHeight(b) - kTrackH) / 2.0), w, kTrackH);
}

- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    NSRect t = [self trackRect];
    if (NSWidth(t) <= 0.0) return;
    CGFloat radius = kTrackH / 2.0;
    [[NSColor colorWithWhite:1.0 alpha:0.14] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:t xRadius:radius yRadius:radius] fill];

    double frac = FCTTSFractionForRate(_rate);
    CGFloat fillW = floor(NSWidth(t) * frac);
    if (fillW > 0.0) {
        NSRect f = NSMakeRect(NSMinX(t), NSMinY(t), MAX(fillW, kTrackH), kTrackH);
        [[NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.85 alpha:0.85] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:f xRadius:radius yRadius:radius] fill];
    }

    // Detent ticks: where a drag lands. Evenly spaced by construction.
    NSUInteger n = 0;
    FCTTSRateDetents(&n);
    for (NSUInteger i = 1; i + 1 < n; i++) {
        CGFloat x = NSMinX(t) + NSWidth(t) * ((double)i / (double)(n - 1));
        NSRect tick = NSMakeRect(floor(x) - 0.5, NSMinY(t) - 2.0, 1.0, kTrackH + 4.0);
        [[NSColor colorWithWhite:1.0 alpha:0.40] setFill];
        NSRectFill(tick);
    }
    // Knob at the current position.
    CGFloat kx = NSMinX(t) + NSWidth(t) * frac;
    NSRect knob = NSMakeRect(kx - 4.5, NSMidY(t) - 4.5, 9.0, 9.0);
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
}

- (CGFloat)naturalContentWidth {
    CGFloat levelW = kLevelW;
    NSString *s = _levelLabel.stringValue;
    if (s.length) {
        CGFloat m = ceil([s sizeWithAttributes:@{NSFontAttributeName : _levelLabel.font}].width) + 6.0;
        if (m > levelW) levelW = m;
    }
    return kPadX + kIconW + 4.0 + kTrackMinW + 6.0 + kGlyphW + levelW + kGlyphW + kPadX;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat y = floor((NSHeight(b) - kLabelH) / 2.0);
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;
    _iconLabel.frame  = NSMakeRect(kPadX, y, kIconW, kLabelH);
    _minusLabel.frame = NSMakeRect(xMinus, y, kGlyphW, kLabelH);
    _levelLabel.frame = NSMakeRect(xLevel, y, kLevelW, kLabelH);
    _plusLabel.frame  = NSMakeRect(xPlus, y, kGlyphW, kLabelH);
}

#pragma mark Interaction

- (double)detentForTrackX:(CGFloat)x {
    NSRect t = [self trackRect];
    if (NSWidth(t) <= 0.0) return _rate;
    double frac = (x - NSMinX(t)) / NSWidth(t);
    return FCTTSRateNearestDetent(FCTTSRateForFraction(frac));
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (p.x >= NSMinX(_minusLabel.frame) && p.x < NSMaxX(_minusLabel.frame)) {
        [self.owner adjustRateBy:-FCTTSRateStep];
    } else if (p.x >= NSMinX(_plusLabel.frame)) {
        [self.owner adjustRateBy:FCTTSRateStep];
    } else if (p.x >= NSMinX(_levelLabel.frame) && p.x < NSMaxX(_levelLabel.frame)) {
        [self.owner adjustRateBy:(p.y >= NSMidY(self.bounds) ? FCTTSRateStep : -FCTTSRateStep)];
    } else if (p.x >= NSMinX([self trackRect]) - 6.0 && p.x <= NSMaxX([self trackRect]) + 6.0) {
        _dragging = YES;
        [self.owner setRate:[self detentForTrackX:p.x]];
    } else {
        [self.owner setRate:FCTTSRateMin];   // the icon: one click back to normal speed
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self.owner setRate:[self detentForTrackX:p.x]];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    _dragging = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat dy = event.scrollingDeltaY;
    if (dy == 0.0) return;
    if (!event.hasPreciseScrollingDeltas) {
        [self.owner adjustRateBy:(dy > 0 ? FCTTSRateFine : -FCTTSRateFine)];
        return;
    }
    if ((dy > 0) != (_scrollAcc > 0)) _scrollAcc = 0.0;   // direction change restarts
    _scrollAcc += dy;
    while (fabs(_scrollAcc) >= kScrollPointsPerStep) {
        BOOL up = _scrollAcc > 0;
        [self.owner adjustRateBy:(up ? FCTTSRateFine : -FCTTSRateFine)];
        _scrollAcc += up ? -kScrollPointsPerStep : kScrollPointsPerStep;
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return [self.owner presetMenu];
}

@end
