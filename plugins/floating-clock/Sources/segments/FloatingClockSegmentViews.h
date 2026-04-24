// Three segment NSView subclasses that compose the three-segment layout:
//   LocalSegmentView   — always on the top row, shows local time (timeLabel)
//   ActiveSegmentView  — bottom-left, shows currently-open markets (contentLabel)
//   NextSegmentView    — bottom-right, shows upcoming opens (contentLabel)
//
// Plus ClockContentView — the panel's contentView; routes right-click events
// to the menu attached by the panel.
//
// Each segment's `menuForEvent:` delegates to its panel's segment-specific
// menu builder (buildLocalSegmentMenu / buildActiveSegmentMenu /
// buildNextSegmentMenu). FloatingClockPanel is forward-declared here and
// accessed via an informal selector — keeps this module decoupled until
// FloatingClockPanel itself is extracted.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FloatingClockPanel;

@interface ClockContentView : NSView <NSMenuDelegate>
@property (weak) FloatingClockPanel *panel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface LocalSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *timeLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface ActiveSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface NextSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

NS_ASSUME_NONNULL_END
