#import "BrightnessBarZoneView.h"
#import "BrightnessStatusIndicator.h"
#import "DisplayBrightnessHelpers.h"

// Fixed-width control cells (points), mirroring the audio bar's geometry so
// the two rails feel identical under the pointer.
static const CGFloat kGlyphW  = 14.0;   // − and + hit cells
static const CGFloat kLevelW  = 38.0;   // "137%" needs more than audio's "100"
static const CGFloat kSunW    = 16.0;
static const CGFloat kPadX    = 6.0;
static const CGFloat kTrackMinW = 54.0; // below this the track stops reading as one
static const CGFloat kLabelH  = 14.0;
static const CGFloat kTrackH  = 7.0;

@implementation FCBrightnessZoneView {
    NSTextField *_sunLabel;
    NSTextField *_minusLabel;
    NSTextField *_levelLabel;
    NSTextField *_plusLabel;

    NSString *_renderKey;
    NSInteger _level;
    NSInteger _maxLevel;
    BOOL      _clamped;
    BOOL      _engaging;
    BOOL      _available;
    BOOL      _dragging;
}

static NSTextField *FCBrightLabel(NSFont *font, NSColor *color, NSTextAlignment align) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSZeroRect];
    l.editable = NO; l.selectable = NO; l.bezeled = NO; l.drawsBackground = NO;
    l.font = font; l.textColor = color; l.alignment = align;
    return l;
}

- (instancetype)initWithFrame:(NSRect)frame owner:(FCBrightnessStatusIndicator *)owner {
    if ((self = [super initWithFrame:frame])) {
        _owner     = owner;
        _maxLevel  = 100;
        _available = YES;

        NSFont *glyphFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightHeavy];
        NSFont *levelFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
        NSColor *dim = [NSColor colorWithWhite:1.0 alpha:0.55];

        _sunLabel   = FCBrightLabel(glyphFont, dim, NSTextAlignmentCenter);
        _minusLabel = FCBrightLabel(glyphFont, dim, NSTextAlignmentCenter);
        _levelLabel = FCBrightLabel(levelFont, [NSColor whiteColor], NSTextAlignmentCenter);
        _plusLabel  = FCBrightLabel(glyphFont, dim, NSTextAlignmentCenter);
        _sunLabel.stringValue   = @"☀";
        _minusLabel.stringValue = @"−";
        _plusLabel.stringValue  = @"+";

        _sunLabel.toolTip   = @"Display brightness — drag the track to set, right-click for presets";
        _minusLabel.toolTip = @"Dimmer (scroll for fine adjust)";
        _plusLabel.toolTip  = @"Brighter — past 100% unlocks XDR headroom the slider cannot reach";
        _levelLabel.toolTip = @"Current brightness; above 100% is EDR boost";

        [self addSubview:_sunLabel];
        [self addSubview:_minusLabel];
        [self addSubview:_levelLabel];
        [self addSubview:_plusLabel];
    }
    return self;
}

// Route every click here — the NSTextField subviews would otherwise swallow
// hits, exactly as they did on the audio bar's device-name label (which
// silently no-opped until it was caught). Labels are display-only.
- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return v ? self : nil;
}

#pragma mark Rendering

- (BOOL)renderLevel:(NSInteger)level
           maxLevel:(NSInteger)maxLevel
            clamped:(BOOL)clamped
           engaging:(BOOL)engaging
          available:(BOOL)available {
    NSString *key = [NSString stringWithFormat:@"%ld|%ld|%d|%d|%d",
                     (long)level, (long)maxLevel, clamped, engaging, available];
    if ([key isEqualToString:_renderKey]) return NO;   // steady-state tick does nothing
    _renderKey = key;

    _level     = level;
    _maxLevel  = maxLevel;
    _clamped   = clamped;
    _engaging  = engaging;
    _available = available;

    BOOL boosting = (level > 100);
    NSColor *amber = [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0];
    NSColor *warn  = [NSColor colorWithSRGBRed:1.00 green:0.58 blue:0.20 alpha:1.0];

    if (!available) {
        _levelLabel.stringValue = @"--";
        _levelLabel.textColor   = [NSColor colorWithWhite:1.0 alpha:0.35];
    } else {
        _levelLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)level];
        _levelLabel.textColor   = clamped ? warn
                                : (boosting ? amber : [NSColor whiteColor]);
    }
    // The sun turns amber the moment we are past the normal maximum, and
    // half-lit while the panel is still ramping into HDR mode — so "engaging"
    // is visible rather than looking like a stuck value.
    _sunLabel.textColor = !available ? [NSColor colorWithWhite:1.0 alpha:0.25]
                        : boosting ? (engaging ? [amber colorWithAlphaComponent:0.55] : amber)
                        : [NSColor colorWithWhite:1.0 alpha:0.55];

    CGFloat glyphAlpha = available ? 0.55 : 0.18;
    _minusLabel.textColor = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];
    _plusLabel.textColor  = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];

    self.needsDisplay = YES;
    return YES;
}

- (NSRect)trackRect {
    NSRect b = self.bounds;
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;
    CGFloat x0 = kPadX + kSunW + 4.0;
    CGFloat w  = xMinus - 4.0 - x0;
    if (w < 8.0) w = 8.0;
    return NSMakeRect(x0, floor((NSHeight(b) - kTrackH) / 2.0), w, kTrackH);
}

- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    NSRect t = [self trackRect];
    if (NSWidth(t) <= 0.0) return;

    CGFloat radius = kTrackH / 2.0;
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:t
                                                      xRadius:radius
                                                      yRadius:radius];
    [[NSColor colorWithWhite:1.0 alpha:0.14] setFill];
    [bg fill];
    if (!_available) return;

    NSInteger maxL = (_maxLevel < 100) ? 100 : _maxLevel;
    double frac = (double)_level / (double)maxL;
    if (frac < 0.0) frac = 0.0;
    if (frac > 1.0) frac = 1.0;

    // Fill. Past 100 % the fill changes colour, so the two mechanisms are
    // distinguishable without reading the number.
    CGFloat fillW = floor(NSWidth(t) * frac);
    if (fillW > 0.0) {
        NSRect f = NSMakeRect(NSMinX(t), NSMinY(t), MAX(fillW, kTrackH), kTrackH);
        NSBezierPath *fp = [NSBezierPath bezierPathWithRoundedRect:f
                                                          xRadius:radius
                                                          yRadius:radius];
        NSColor *c = (_level > 100)
            ? (_clamped ? [NSColor colorWithSRGBRed:1.00 green:0.58 blue:0.20 alpha:0.95]
                        : [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:0.95])
            : [NSColor colorWithWhite:1.0 alpha:0.80];
        [c setFill];
        [fp fill];
    }

    // The 100 % boundary. Everything right of this tick is headroom that the
    // macOS brightness slider cannot reach at all — the whole point of the
    // control, so it gets a visible mark rather than an implied one.
    if (maxL > 100) {
        CGFloat x = NSMinX(t) + NSWidth(t) * (100.0 / (double)maxL);
        NSRect tick = NSMakeRect(floor(x) - 0.5, NSMinY(t) - 2.0, 1.0, kTrackH + 4.0);
        [[NSColor colorWithWhite:1.0 alpha:0.55] setFill];
        NSRectFill(tick);
    }
}

- (CGFloat)naturalContentWidth {
    // Measured from the cells actually laid out, so the published width need
    // can never drift from what is drawn.
    CGFloat levelW = kLevelW;
    NSString *s = _levelLabel.stringValue;
    if (s.length) {
        CGFloat measured = ceil([s sizeWithAttributes:@{NSFontAttributeName : _levelLabel.font}].width) + 6.0;
        if (measured > levelW) levelW = measured;
    }
    return kPadX + kSunW + 4.0 + kTrackMinW + 4.0 + kGlyphW + levelW + kGlyphW + kPadX;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat y = floor((NSHeight(b) - kLabelH) / 2.0);
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;

    _sunLabel.frame   = NSMakeRect(kPadX, y, kSunW, kLabelH);
    _minusLabel.frame = NSMakeRect(xMinus, y, kGlyphW, kLabelH);
    _levelLabel.frame = NSMakeRect(xLevel, y, kLevelW, kLabelH);
    _plusLabel.frame  = NSMakeRect(xPlus, y, kGlyphW, kLabelH);
}

#pragma mark Interaction

- (NSInteger)levelForTrackX:(CGFloat)x {
    NSRect t = [self trackRect];
    if (NSWidth(t) <= 0.0) return _level;
    double frac = (x - NSMinX(t)) / NSWidth(t);
    if (frac < 0.0) frac = 0.0;
    if (frac > 1.0) frac = 1.0;
    NSInteger maxL = (_maxLevel < 100) ? 100 : _maxLevel;
    return (NSInteger)lround(frac * (double)maxL);
}

- (void)mouseDown:(NSEvent *)event {
    if (!_available) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger step = [FCBrightnessZoneView stepPercent];

    if (p.x >= NSMinX(_minusLabel.frame) && p.x < NSMaxX(_minusLabel.frame)) {
        [self.owner adjustLevelBy:-step];
    } else if (p.x >= NSMinX(_plusLabel.frame)) {
        [self.owner adjustLevelBy:step];
    } else if (p.x >= NSMinX(_levelLabel.frame) && p.x < NSMaxX(_levelLabel.frame)) {
        // Same affordance as the audio bar's number cell: top half up,
        // bottom half down.
        [self.owner adjustLevelBy:(p.y >= NSMidY(self.bounds) ? step : -step)];
    } else if (p.x >= NSMinX([self trackRect]) - 4.0 &&
               p.x <= NSMaxX([self trackRect]) + 4.0) {
        _dragging = YES;
        [self.owner setLevel:[self levelForTrackX:p.x]];
    } else {
        [self.owner cyclePreset];
    }
}

// Scrubbing. The rail is only 7 pt tall, so tracking the drag rather than
// requiring the pointer to stay inside it is what makes it usable.
- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging || !_available) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self.owner setLevel:[self levelForTrackX:p.x]];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    _dragging = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    if (!_available) return;
    CGFloat dy = event.scrollingDeltaY;
    if (dy == 0.0) return;
    [self.owner adjustLevelBy:(dy > 0 ? 2 : -2)];
}

// AppKit routes right-click, ctrl-click AND two-finger tap here.
- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return [self.owner presetMenu];
}

+ (NSInteger)stepPercent {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:@"BrightnessBarStep"];
    return FCBrightnessStepPercent(raw);
}

@end
