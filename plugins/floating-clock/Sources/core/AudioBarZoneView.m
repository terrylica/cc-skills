#import "AudioBarZoneView.h"
#import "AudioStatusIndicator.h"   // owner action methods + menu hook

// Fixed-width control cells inside each zone (points).
static const CGFloat kGlyphW = 14.0;   // − and + hit cells
// Numeric level cell — see AudioStatusIndicator history for the sizing note.
static const CGFloat kLevelW = 30.0;
static const CGFloat kPadX   = 6.0;    // zone inner horizontal padding

@implementation FCAudioZoneView {
    // Render cache + flash state (2026-06-11 extras). _renderKey encodes the
    // full visible composite; when unchanged, the 1Hz tick touches nothing.
    NSString      *_renderKey;
    NSString      *_lastName;       // nil → first render (no flash on launch)
    NSInteger      _lastPct;
    CFAbsoluteTime _nameFlashUntil;
    CFAbsoluteTime _levelFlashUntil;
}

// Flash duration after a device/level change (user-selected extra): long
// enough to survive 1-2 ticks of the 1Hz refresh, short enough to read as
// a blink, not a state.
static const CFTimeInterval kFlashSecs = 1.4;

static NSTextField *FCBarLabel(NSFont *font, NSColor *color, NSTextAlignment align) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSZeroRect];
    l.editable = NO; l.selectable = NO; l.bezeled = NO; l.drawsBackground = NO;
    l.font = font; l.textColor = color; l.alignment = align;
    l.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return l;
}

- (instancetype)initWithFrame:(NSRect)frame isInput:(BOOL)isInput owner:(FCAudioStatusIndicator *)owner {
    if ((self = [super initWithFrame:frame])) {
        _isInput = isInput;
        _owner   = owner;

        NSFont *nameFont  = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
        NSFont *levelFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightBold];
        NSFont *glyphFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightHeavy];
        NSColor *dim      = [NSColor colorWithWhite:1.0 alpha:0.55];

        _nameLabel  = FCBarLabel(nameFont, [NSColor whiteColor], NSTextAlignmentLeft);
        _minusLabel = FCBarLabel(glyphFont, dim, NSTextAlignmentCenter);
        _levelLabel = FCBarLabel(levelFont, [NSColor whiteColor], NSTextAlignmentCenter);
        _plusLabel  = FCBarLabel(glyphFont, dim, NSTextAlignmentCenter);
        _minusLabel.stringValue = @"−";
        _plusLabel.stringValue  = @"+";

        NSString *cat = isInput ? @"input" : @"output";
        _nameLabel.toolTip  = [NSString stringWithFormat:@"Current %@ device — click to switch to the next available %@ device", cat, cat];
        _minusLabel.toolTip = [NSString stringWithFormat:@"Lower %@ level (scroll for fine adjust)", cat];
        _plusLabel.toolTip  = [NSString stringWithFormat:@"Raise %@ level (scroll for fine adjust)", cat];
        _levelLabel.toolTip = [NSString stringWithFormat:@"Current %@ level (0–100)", cat];

        [self addSubview:_nameLabel];
        [self addSubview:_minusLabel];
        [self addSubview:_levelLabel];
        [self addSubview:_plusLabel];
    }
    return self;
}

// Route EVERY click inside the zone to this view's mouseDown — the
// NSTextField subviews would otherwise swallow hits (verified 2026-06-11:
// clicks on the device-name label never reached mouseDown, so device
// cycling silently no-opped). Labels are display-only; the zone owns all
// interaction.
- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return v ? self : nil;
}

#pragma mark Zone rendering (cache + mute tint + change flash)

- (void)renderDevice:(NSString *)name levelPercent:(NSInteger)pct muted:(BOOL)muted {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL first = (_lastName == nil);
    if (!first) {
        if (![name isEqualToString:_lastName]) _nameFlashUntil  = now + kFlashSecs;
        if (pct != _lastPct)                   _levelFlashUntil = now + kFlashSecs;
    }
    BOOL nameFlash   = now < _nameFlashUntil;
    BOOL levelFlash  = now < _levelFlashUntil;
    BOOL nameChanged = first || ![name isEqualToString:_lastName];
    _lastName = [name copy];
    _lastPct  = pct;

    // Composite of everything visible — skip ALL label work when unchanged
    // (the 1Hz tick path must stay allocation/layout-free at steady state).
    NSString *key = [NSString stringWithFormat:@"%@|%ld|%d|%d|%d",
                     name, (long)pct, muted, nameFlash, levelFlash];
    if ([key isEqualToString:_renderKey]) return;
    _renderKey = key;

    NSColor *amber = [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0]; // change blink
    NSColor *red   = [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0]; // muted
    NSColor *tint  = muted ? red
                   : (self.isInput
                       ? [NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0]   // green — capture
                       : [NSColor colorWithSRGBRed:0.38 green:0.78 blue:1.00 alpha:1.0]); // blue  — playback
    NSColor *nameColor = muted ? red : (nameFlash ? amber : [NSColor whiteColor]);

    NSMutableDictionary *nameAttrs = [@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: nameColor,
    } mutableCopy];
    if (muted) nameAttrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);

    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    [s appendAttributedString:[[NSAttributedString alloc]
        initWithString:(self.isInput ? (muted ? @"IN⊘ " : @"IN ") : @"OUT ")
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy],
                          NSForegroundColorAttributeName: tint }]];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:name
                                                               attributes:nameAttrs]];
    self.nameLabel.attributedStringValue = s;
    if (nameChanged) {
        self.nameLabel.toolTip = [NSString stringWithFormat:@"%@ — click to switch to the next available %@ device",
                                  name, self.isInput ? @"input" : @"output"];
    }

    self.levelLabel.stringValue = (pct < 0) ? @"--" : [NSString stringWithFormat:@"%ld", (long)pct];
    self.levelLabel.textColor   = muted ? red : (levelFlash ? amber : [NSColor whiteColor]);
    BOOL adjustable = (pct >= 0);
    CGFloat glyphAlpha = adjustable ? 0.55 : 0.18;
    self.minusLabel.textColor = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];
    self.plusLabel.textColor  = [NSColor colorWithWhite:1.0 alpha:glyphAlpha];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat h = 14.0;
    CGFloat y = (b.size.height - h) / 2.0;
    CGFloat xPlus  = NSMaxX(b) - kPadX - kGlyphW;
    CGFloat xLevel = xPlus - kLevelW;
    CGFloat xMinus = xLevel - kGlyphW;
    CGFloat nameW  = xMinus - kPadX - 2.0;
    if (nameW < 10.0) nameW = 10.0;
    self.nameLabel.frame  = NSMakeRect(kPadX, y, nameW, h);
    self.minusLabel.frame = NSMakeRect(xMinus, y, kGlyphW, h);
    self.levelLabel.frame = NSMakeRect(xLevel, y, kLevelW, h);
    self.plusLabel.frame  = NSMakeRect(xPlus, y, kGlyphW, h);
}

// Hit zones use the control frames padded to the full bar height so the
// 20pt-tall rail is easy to hit despite 14pt-tall labels.
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger step = [FCAudioZoneView stepPercent];
    if (p.x >= NSMinX(self.minusLabel.frame) && p.x < NSMaxX(self.minusLabel.frame)) {
        [self.owner adjustVolumeForInput:self.isInput byPercent:-step];
    } else if (p.x >= NSMinX(self.plusLabel.frame)) {
        [self.owner adjustVolumeForInput:self.isInput byPercent:step];
    } else if (p.x >= NSMinX(self.levelLabel.frame) && p.x < NSMaxX(self.levelLabel.frame)) {
        // The number itself: top half nudges up, bottom half nudges down —
        // "adjustable directly on the number" per the user requirement.
        BOOL topHalf = p.y >= NSMidY(self.bounds);
        [self.owner adjustVolumeForInput:self.isInput byPercent:(topHalf ? step : -step)];
    } else {
        [self.owner cycleDeviceForInput:self.isInput];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat dy = event.scrollingDeltaY;
    if (dy == 0.0) return;
    [self.owner adjustVolumeForInput:self.isInput byPercent:(dy > 0 ? 2 : -2)];
}

// Pull-out device-selection menu (2026-06-11). AppKit calls -menuForEvent:
// for right-click, two-finger trackpad tap, AND ctrl-click — covering every
// activation gesture in the directive. Built fresh per invocation so the
// device list (live + paired-offline Bluetooth) is always current. IN and
// OUT zones each ask for their own scope — fully independent menus.
- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self.owner deviceSelectionMenuForInput:self.isInput];
}

+ (NSInteger)stepPercent {
    NSInteger s = [[NSUserDefaults standardUserDefaults] integerForKey:@"AudioBarStep"];
    if (s < 1)  s = 5;     // unset/garbage → default
    if (s > 25) s = 25;
    return s;
}

@end
