#import "NetworkBarZoneView.h"
#import "NetworkStatusIndicator.h"

static const CGFloat kPadX = 6.0;
static const CFTimeInterval kFlashSecs = 1.4;

// Labels are laid out at this fixed height and centred in the bar, rather than
// being stretched to the full bar height. An NSTextField centres its glyphs
// inside its own frame using font metrics that include leading, so a
// full-height field parks the text visibly above centre — that was the
// misalignment against the audio rail. The audio bar solved it the same way
// (AudioBarZoneView -layout), and matching the constant is what keeps the two
// rails' baselines identical.
static const CGFloat kLabelH = 14.0;

// Gap between the service name and the telemetry group, so a long name never
// collides with the right-hand fields.
static const CGFloat kGroupGap = 10.0;

// -[NSAttributedString size].width UNDER-measures what NSTextField needs to
// draw, so a frame set to exactly that width loses the final glyph to the
// truncation ellipsis — "Wi-Fi" renders as "Wi-". The audio bar hit this first
// and absorbs it with the same 3pt of slack (AudioStatusIndicator
// -zoneWidthForName:); matching the constant keeps the two rails consistent.
static const CGFloat kMeasureSlack = 3.0;

// Width a label needs to draw its current content in full. Zero-width content
// gets no slack, so an empty telemetry group contributes nothing at all.
static CGFloat FCNetLabelWidth(NSTextField *label) {
    CGFloat w = ceil(label.attributedStringValue.size.width);
    return (w > 0.0) ? w + kMeasureSlack : 0.0;
}

@implementation FCNetworkZoneView {
    NSString      *_lastName;
    NSString      *_renderKey;
    CFAbsoluteTime _nameFlashUntil;
}

static NSTextField *FCNetBarLabel(NSFont *font, NSColor *color) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSZeroRect];
    l.editable = NO; l.selectable = NO; l.bezeled = NO; l.drawsBackground = NO;
    l.font = font; l.textColor = color; l.alignment = NSTextAlignmentLeft;
    l.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return l;
}

- (instancetype)initWithFrame:(NSRect)frame owner:(FCNetworkStatusIndicator *)owner {
    if ((self = [super initWithFrame:frame])) {
        _owner = owner;
        _nameLabel = FCNetBarLabel([NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
                                   [NSColor whiteColor]);
        _nameLabel.toolTip = @"Network service currently carrying internet traffic — "
                              "click to switch to the next one, right-click to choose";
        [self addSubview:_nameLabel];

        _statsLabel = FCNetBarLabel([NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
                                    [NSColor colorWithWhite:1.0 alpha:0.75]);
        _statsLabel.alignment = NSTextAlignmentRight;
        _statsLabel.toolTip = @"Address on this interface · downstream and upstream "
                               "throughput · Wi-Fi signal and link rate";
        [self addSubview:_statsLabel];
    }
    return self;
}

// Route EVERY click inside the zone to this view's mouseDown. The NSTextField
// subview would otherwise swallow hits — the exact bug verified on the audio
// bar 2026-06-11, where clicks on the device-name label never reached
// mouseDown and switching silently no-opped.
- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return v ? self : nil;
}

#pragma mark Rendering (cache + change flash)

- (void)renderService:(NSString *)name
             degraded:(BOOL)degraded
                stats:(NSAttributedString *)stats {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSString *shown = name.length ? name : @"(none)";
    if (_lastName && ![shown isEqualToString:_lastName]) {
        _nameFlashUntil = now + kFlashSecs;   // route moved — catch the eye
    }
    BOOL flash = now < _nameFlashUntil;
    _lastName = [shown copy];

    // Composite of everything visible — skip all label work when unchanged so
    // the 1 Hz tick stays allocation-free at steady state. The stats string is
    // part of the key because throughput changes every tick; when traffic is
    // idle the whole composite is stable and no work happens at all.
    NSString *key = [NSString stringWithFormat:@"%@|%d|%d|%@",
                     shown, degraded, flash, stats.string ?: @""];
    if ([key isEqualToString:_renderKey]) return;
    _renderKey = key;

    _statsLabel.attributedStringValue = stats ?: [[NSAttributedString alloc] initWithString:@""];

    NSColor *amber = [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0];
    NSColor *red   = [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0];
    NSColor *cyan  = [NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.95 alpha:1.0];

    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    [s appendAttributedString:
        [[NSAttributedString alloc] initWithString:@"NET "
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy],
                          NSForegroundColorAttributeName: degraded ? red : cyan }]];
    [s appendAttributedString:
        [[NSAttributedString alloc] initWithString:shown
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium],
                          NSForegroundColorAttributeName: degraded ? red
                                                        : (flash ? amber : [NSColor whiteColor]) }]];
    _nameLabel.attributedStringValue = s;
    self.needsLayout = YES;
}

- (CGFloat)naturalContentWidth {
    CGFloat nameW  = FCNetLabelWidth(_nameLabel);
    CGFloat statsW = FCNetLabelWidth(_statsLabel);
    CGFloat gap    = (statsW > 0.0) ? kGroupGap : 0.0;
    return kPadX + nameW + gap + statsW + kPadX;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat y = floor((NSHeight(b) - kLabelH) / 2.0);   // vertical centring, see kLabelH

    CGFloat avail = NSWidth(b) - kPadX * 2.0;
    if (avail < 0.0) avail = 0.0;

    CGFloat nameW  = FCNetLabelWidth(_nameLabel);
    CGFloat statsW = FCNetLabelWidth(_statsLabel);

    // The identity of the route matters more than its metrics, so when the bar
    // is too narrow for both the telemetry group yields first — the name keeps
    // its full measured width and only the stats are squeezed.
    if (nameW + kGroupGap + statsW > avail) {
        statsW = avail - nameW - kGroupGap;
        if (statsW < 0.0) statsW = 0.0;
        if (nameW > avail) nameW = avail;
    }

    _nameLabel.frame  = NSMakeRect(kPadX, y, nameW, kLabelH);
    _statsLabel.frame = NSMakeRect(NSMaxX(b) - kPadX - statsW, y, statsW, kLabelH);
}

#pragma mark Interaction

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    [self.owner cycleService];
}

// Right-click / two-finger tap / ctrl-click all arrive here for free.
- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return [self.owner serviceSelectionMenu];
}

@end
