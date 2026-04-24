#import "FloatingClockSegmentViews.h"
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
    self.layer.backgroundColor = [NSColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.50].CGColor;
    self.layer.cornerRadius = 6.0;

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
    self.layer.backgroundColor = [NSColor colorWithRed:0.02 green:0.08 blue:0.04 alpha:0.50].CGColor;
    self.layer.cornerRadius = 6.0;

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

    // v4 iter-64: NSVisualEffectView for native frosted-glass vibrancy.
    // Blurs desktop/windows behind the segment — macOS's canonical
    // "fanciful" material system. Zero dependencies, zero binary bloat
    // (already in AppKit). Material 'popover' matches what Control
    // Center + menu popovers use — fits an always-on-top clock
    // panel aesthetically.
    NSVisualEffectView *veView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    veView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    veView.material = NSVisualEffectMaterialHUDWindow;
    veView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    veView.state = NSVisualEffectStateActive;
    [self addSubview:veView];

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
