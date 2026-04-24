#import "FloatingClockSegmentViews.h"
#import "../vendor/RMBlurredView/RMBlurredView.h"
#import "../rendering/VerticallyCenteredTextFieldCell.h"

// Informal protocol the panel implements. Declared here so the segment
// views can call the menu builders without importing the full panel
// header (avoids a circular include during incremental modularization).
@interface NSObject (FloatingClockSegmentMenuBuilder)
- (NSMenu *)buildLocalSegmentMenu;
- (NSMenu *)buildActiveSegmentMenu;
- (NSMenu *)buildNextSegmentMenu;
@end

@implementation ClockContentView

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeOtherMouseDown) {
        return self.menu;
    }
    return [super menuForEvent:event];
}

@end

@implementation LocalSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6.0;
    self.layer.masksToBounds = YES;

    // v4 iter-67: RMBlurredView frosted glass (iter-65 consistency pass).
    // Slightly lower saturation and neutral tint — LOCAL is the calm
    // anchor row; heavy saturation would steal focus from ACTIVE/NEXT.
    RMBlurredView *blurView = [[RMBlurredView alloc] initWithFrame:self.bounds];
    blurView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    blurView.blurRadius = 16.0;
    blurView.saturationFactor = 1.8;
    blurView.tintColor = [NSColor colorWithCalibratedWhite:0.06 alpha:0.40];
    [self addSubview:blurView];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    VerticallyCenteredTextFieldCell *cell = [[VerticallyCenteredTextFieldCell alloc] initTextCell:@""];
    cell.editable = NO;
    cell.selectable = NO;
    cell.bezeled = NO;
    cell.drawsBackground = NO;
    cell.alignment = NSTextAlignmentCenter;
    label.cell = cell;
    [self addSubview:label];
    _timeLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [(id)self.panel buildLocalSegmentMenu];
}

@end

@implementation ActiveSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6.0;
    self.layer.masksToBounds = YES;

    // v4 iter-67: RMBlurredView frosted glass (iter-65 consistency pass).
    // Green-tinted — matches the live-markets energy and differentiates
    // from NEXT's neutral dark tint.
    RMBlurredView *activeBlur = [[RMBlurredView alloc] initWithFrame:self.bounds];
    activeBlur.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    activeBlur.blurRadius = 20.0;
    activeBlur.saturationFactor = 2.4;
    activeBlur.tintColor = [NSColor colorWithCalibratedRed:0.04 green:0.12 blue:0.06 alpha:0.40];
    [self addSubview:activeBlur];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    VerticallyCenteredTextFieldCell *cell = [[VerticallyCenteredTextFieldCell alloc] initTextCell:@""];
    cell.editable = NO;
    cell.selectable = NO;
    cell.bezeled = NO;
    cell.drawsBackground = NO;
    cell.alignment = NSTextAlignmentLeft;
    cell.wraps = NO;
    cell.lineBreakMode = NSLineBreakByTruncatingTail;
    label.cell = cell;
    label.usesSingleLineMode = NO;
    [self addSubview:label];
    _contentLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [(id)self.panel buildActiveSegmentMenu];
}

@end

@implementation NextSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6.0;
    self.layer.masksToBounds = YES;

    // v4 iter-65: RMBlurredView (CIFilter + CALayer.backgroundFilters).
    // Stronger Gaussian blur than NSVisualEffectView's material system,
    // with saturation boost — closer to the user's request for a
    // "fanciful frosted-glass library". ~115 LoC vendored under
    // Sources/vendor/RMBlurredView/ per the plugin's no-external-deps
    // stance; MIT-licensed from github.com/raffael/RMBlurredView.
    RMBlurredView *blurView = [[RMBlurredView alloc] initWithFrame:self.bounds];
    blurView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    blurView.blurRadius = 18.0;
    blurView.saturationFactor = 2.2;
    blurView.tintColor = [NSColor colorWithCalibratedWhite:0.10 alpha:0.35];
    [self addSubview:blurView];

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    VerticallyCenteredTextFieldCell *cell = [[VerticallyCenteredTextFieldCell alloc] initTextCell:@""];
    cell.editable = NO;
    cell.selectable = NO;
    cell.bezeled = NO;
    cell.drawsBackground = NO;
    cell.alignment = NSTextAlignmentLeft;
    cell.wraps = NO;
    label.cell = cell;
    label.usesSingleLineMode = NO;
    [self addSubview:label];
    _contentLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [(id)self.panel buildNextSegmentMenu];
}

@end
