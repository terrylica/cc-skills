// Three segment NSView subclasses that compose the three-segment layout:
//   LocalSegmentView   — always on the top row, shows local time (timeLabel)
//   ActiveSegmentView  — bottom-left, shows currently-open markets (contentLabel)
//   NextSegmentView    — bottom-right, shows upcoming opens (contentLabel)
//
// Plus ClockContentView — the panel's contentView; routes right-click events
// to the menu attached by the panel.
//
// v4 iter-199: UI-NAMING CAMPAIGN. Each segment view now carries a stable
// canonical `nameID` (LOCAL / ACTIVE / NEXT) that appears in corner-
// overlay debug labels and NSToolTips when the user toggles the
// `ShowDebugLabels` NSUserDefaults key. The naming registry is the
// Canonical UI Names table in plugins/floating-clock/CLAUDE.md —
// adding a newly-labeled UI element means adding a row there too,
// so names stay stable across iters and the user can reference them
// precisely in feedback ("the label in bottom-right of ACTIVE called
// [COUNTDOWN] is 2pt too small").
//
// Each segment's `menuForEvent:` delegates to its panel's segment-specific
// menu builder (buildLocalSegmentMenu / buildActiveSegmentMenu /
// buildNextSegmentMenu). FloatingClockPanel is forward-declared here and
// accessed via an informal selector — keeps this module decoupled until
// FloatingClockPanel itself is extracted.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FloatingClockPanel;

// v4 iter-199: shared protocol surface for named segment views.
@protocol FCNamedSegment <NSObject>
/// Canonical stable short name shown in the debug-label overlay
/// ("LOCAL" / "ACTIVE" / "NEXT"). Used as the user-visible pointer
/// for feedback — never change a live name without updating the
/// Canonical UI Names table in CLAUDE.md.
- (NSString *)fcNameID;
/// Full human-readable description used as the NSToolTip text.
- (NSString *)fcFullName;
/// Show/hide the corner-overlay debug label based on the
/// `ShowDebugLabels` NSUserDefaults key. Idempotent.
- (void)fcRefreshDebugLabel;
@end

@interface ClockContentView : NSView <NSMenuDelegate>
@property (weak) FloatingClockPanel *panel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface LocalSegmentView : NSView <FCNamedSegment>
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *timeLabel;
@property (strong) NSTextField *debugLabel;  // iter-199 corner overlay
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface ActiveSegmentView : NSView <FCNamedSegment>
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
@property (strong) NSTextField *debugLabel;  // iter-199 corner overlay
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface NextSegmentView : NSView <FCNamedSegment>
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
@property (strong) NSTextField *debugLabel;  // iter-199 corner overlay
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

NS_ASSUME_NONNULL_END
