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

// v4 iter-199: shared factory for the bottom-left corner debug label.
// 8pt monospace caps, semi-transparent white, pinned to bottom-left
// inside an 8pt inset. Hidden by default — `fcRefreshDebugLabel`
// toggles visibility based on NSUserDefaults "ShowDebugLabels".
// Accepts the nameID string (e.g. @"LOCAL") as display text.
//
// v4 iter-200: moved from top-left to bottom-left per user feedback —
// top-left was blocking the LOCAL segment's time-label top cap. The
// bottom-left inset has more dead space across all three segments
// (ACTIVE + NEXT draw content top-down, LOCAL's time is vertically
// centered).
static NSTextField *fcMakeDebugLabel(NSString *nameID) {
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 0, 80, 12)];
    lbl.stringValue = [NSString stringWithFormat:@"[%@]", nameID];
    lbl.editable = NO;
    lbl.selectable = NO;
    lbl.bezeled = NO;
    lbl.drawsBackground = NO;
    lbl.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.55];
    lbl.font = [NSFont monospacedSystemFontOfSize:8.5 weight:NSFontWeightMedium];
    // Bottom-left pin: hug left + bottom edges (hence MaxX + MaxY margins grow).
    lbl.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    lbl.hidden = YES;
    return lbl;
}

// v4 iter-199/200: anchor the debug label to the bottom-left on
// every layout. 4pt inset from left + bottom. Called from `layout`
// overrides below so the overlay stays pinned when the segment
// resizes.
static void fcAnchorDebugLabelBottomLeft(NSTextField *lbl, NSRect bounds) {
    NSRect r = lbl.frame;
    r.origin.x = 6.0;
    r.origin.y = 4.0;
    lbl.frame = r;
    (void)bounds;  // not needed once we anchor bottom-relative
}

// v4 iter-199: shared refresh logic — read ShowDebugLabels pref and
// toggle visibility. Called from panel tick + menu toggle action.
static void fcApplyDebugLabelVisibility(NSTextField *lbl) {
    BOOL show = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDebugLabels"];
    lbl.hidden = !show;
}

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
    // v4 iter-203: sub-element name surfaced via NSToolTip only — no
    // corner overlay (too much visual noise for a label that already
    // fills most of the segment). Named [TIME] so user feedback can
    // target the time text distinctly from the surrounding LOCAL
    // segment chrome (e.g. "[TIME]'s font size is too small").
    label.toolTip = @"[TIME] — user-local time display inside [LOCAL] (updates every second; formatting controlled by TimeFormat / TimeSeparator / ShowSeconds prefs)";

    // v4 iter-199: canonical name overlay. Stable ID "LOCAL".
    _debugLabel = fcMakeDebugLabel([self fcNameID]);
    [self addSubview:_debugLabel];
    self.toolTip = [self fcFullName];

    return self;
}

- (void)layout {
    [super layout];
    fcAnchorDebugLabelBottomLeft(_debugLabel, self.bounds);
}

- (NSString *)fcNameID { return @"LOCAL"; }
- (NSString *)fcFullName { return @"LOCAL — top segment, current user-local time"; }
- (void)fcRefreshDebugLabel { fcApplyDebugLabelVisibility(_debugLabel); }

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

    // v4 iter-199: canonical name overlay. Stable ID "ACTIVE".
    _debugLabel = fcMakeDebugLabel([self fcNameID]);
    [self addSubview:_debugLabel];
    self.toolTip = [self fcFullName];

    return self;
}

- (void)layout {
    [super layout];
    fcAnchorDebugLabelBottomLeft(_debugLabel, self.bounds);
}

- (NSString *)fcNameID { return @"ACTIVE"; }
- (NSString *)fcFullName { return @"ACTIVE — bottom-left segment, currently-open markets with progress bars"; }
- (void)fcRefreshDebugLabel { fcApplyDebugLabelVisibility(_debugLabel); }

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

    // v4 iter-199: canonical name overlay. Stable ID "NEXT".
    _debugLabel = fcMakeDebugLabel([self fcNameID]);
    [self addSubview:_debugLabel];
    self.toolTip = [self fcFullName];

    return self;
}

- (void)layout {
    [super layout];
    fcAnchorDebugLabelBottomLeft(_debugLabel, self.bounds);
}

- (NSString *)fcNameID { return @"NEXT"; }
- (NSString *)fcFullName { return @"NEXT — bottom-right segment, upcoming-open markets with landing countdowns"; }
- (void)fcRefreshDebugLabel { fcApplyDebugLabelVisibility(_debugLabel); }

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [(id)self.panel buildNextSegmentMenu];
}

@end
