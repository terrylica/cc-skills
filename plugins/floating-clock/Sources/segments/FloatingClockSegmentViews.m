#import "FloatingClockSegmentViews.h"
#import "LocalLayoutConstants.h"  // iter-242: SSoT for layout constants
#import "../vendor/RMBlurredView/RMBlurredView.h"
#import "../rendering/VerticallyCenteredTextFieldCell.h"

// Informal protocol the panel implements. Declared here so the segment
// views can call the menu builders without importing the full panel
// header (avoids a circular include during incremental modularization).
@interface NSObject (FloatingClockSegmentMenuBuilder)
- (NSMenu *)buildLocalSegmentMenu;
- (NSMenu *)buildActiveSegmentMenu;
- (NSMenu *)buildNextSegmentMenu;
- (void)applyDisplaySettings;  // iter-206: collapse toggle dispatch
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

// v4 iter-248: canonical [LOCAL]/[ACTIVE]/[NEXT] corner overlays
// removed per user directive. Force-hide unconditionally regardless
// of the (now-stale) ShowDebugLabels pref. The view subtree stays so
// the FCNamedSegment protocol contract holds.
static void fcApplyDebugLabelVisibility(NSTextField *lbl) {
    lbl.hidden = YES;
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

    // v4 iter-251: week labels moved OUT of LocalSegmentView and into
    // their own WeekSegmentView (sibling block) per user directive —
    // LOCAL must be a clean timestamp-only block, both H + V centered.

    // v4 iter-199: canonical name overlay. Stable ID "LOCAL".
    _debugLabel = fcMakeDebugLabel([self fcNameID]);
    [self addSubview:_debugLabel];
    self.toolTip = [self fcFullName];

    return self;
}

- (void)layout {
    [super layout];
    // v4 iter-252b: explicitly position timeLabel at the vertical midpoint
    // of the block. The previous approach (frame=self.bounds + rely on
    // VerticallyCenteredTextFieldCell to center) didn't survive NSTextField's
    // internal drawing path — text continued landing at the top of the
    // block. Setting a tight, vertically-centered frame eliminates the
    // dependency on cell-level vertical centering entirely.
    NSRect b = self.bounds;
    CGFloat textH = [(VerticallyCenteredTextFieldCell *)_timeLabel.cell
                               measuredHeightForWidth:b.size.width];
    if (textH < 10) textH = 30;
    CGFloat textY = (b.size.height - textH) / 2.0;
    _timeLabel.frame = NSMakeRect(0, textY, b.size.width, textH);
    fcAnchorDebugLabelBottomLeft(_debugLabel, self.bounds);
}

- (NSString *)fcNameID { return @"LOCAL"; }
- (NSString *)fcFullName { return @"LOCAL — top segment, current user-local time · double-click to collapse/expand bottom blocks"; }
- (void)fcRefreshDebugLabel { fcApplyDebugLabelVisibility(_debugLabel); }

// v4 iter-206: double-click LOCAL → toggle SegmentsCollapsed flag,
// which Layout.m's applyDisplaySettings interprets as temporary
// local-only rendering. DisplayMode pref stays at three-segment so
// the collapse is presentation-only, not a mode change. Single click
// is left untouched (drag-to-move on the window background still
// works because NSPanel.isMovableByWindowBackground handles it
// before mouseDown reaches the NSView subclass).
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        BOOL cur = [d boolForKey:@"SegmentsCollapsed"];
        [d setBool:!cur forKey:@"SegmentsCollapsed"];
        [(id)self.panel applyDisplaySettings];
        return;
    }
    [super mouseDown:event];
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

// v4 iter-251: WEEK segment — splits week-progression machinery out of
// LOCAL into its own block per user directive. Houses (top→bottom):
//   weekNumberLabel   "W##" ISO 8601 — financial-market convention
//   weekDayLabelsLabel "M T W T F S S" centered over day-groups
//   weekBarLabel       7 day-groups of dots, full block width
// All labels horizontally centered. Right-click delegates to LOCAL's
// menu (week prefs live there — no separate WeekSegmentMenu builder).
@implementation WeekSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6.0;
    self.layer.masksToBounds = YES;

    // Same frosted backdrop tone as LOCAL — visually pairs them as
    // user-facing-clock content vs ACTIVE/NEXT's market content.
    RMBlurredView *blurView = [[RMBlurredView alloc] initWithFrame:self.bounds];
    blurView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    blurView.blurRadius = 16.0;
    blurView.saturationFactor = 1.8;
    blurView.tintColor = [NSColor colorWithCalibratedWhite:0.06 alpha:0.40];
    [self addSubview:blurView];

    NSTextField *bar = [[NSTextField alloc] initWithFrame:NSZeroRect];
    NSTextFieldCell *bcell = [[NSTextFieldCell alloc] initTextCell:@""];
    bcell.editable = NO; bcell.selectable = NO; bcell.bezeled = NO; bcell.drawsBackground = NO;
    bcell.alignment = NSTextAlignmentCenter;
    bar.cell = bcell;
    bar.toolTip = @"[WEEKBAR] — weekly progress bar (7 day-groups divided by ┊; ProgressBarStyle / WeekProgressCellsPerDay control glyphs + width)";
    [self addSubview:bar];
    _weekBarLabel = bar;

    NSTextField *days = [[NSTextField alloc] initWithFrame:NSZeroRect];
    NSTextFieldCell *dcell = [[NSTextFieldCell alloc] initTextCell:@""];
    dcell.editable = NO; dcell.selectable = NO; dcell.bezeled = NO; dcell.drawsBackground = NO;
    dcell.alignment = NSTextAlignmentCenter;
    days.cell = dcell;
    days.toolTip = @"[WEEKDAYS] — day-of-week letters (M T W T F S S) aligned over each day-group";
    [self addSubview:days];
    _weekDayLabelsLabel = days;

    NSTextField *num = [[NSTextField alloc] initWithFrame:NSZeroRect];
    NSTextFieldCell *ncell = [[NSTextFieldCell alloc] initTextCell:@""];
    ncell.editable = NO; ncell.selectable = NO; ncell.bezeled = NO; ncell.drawsBackground = NO;
    ncell.alignment = NSTextAlignmentCenter;
    num.cell = ncell;
    num.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.55];
    num.font = [NSFont monospacedSystemFontOfSize:9.5 weight:NSFontWeightMedium];
    num.toolTip = @"[WEEKNUM] — ISO 8601 week-of-year (financial-market convention)";
    [self addSubview:num];
    _weekNumberLabel = num;

    _debugLabel = fcMakeDebugLabel([self fcNameID]);
    [self addSubview:_debugLabel];
    self.toolTip = [self fcFullName];

    return self;
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat barH     = kFCLocalWeekBarH;
    CGFloat daysH    = kFCLocalDayLabelsH;
    CGFloat weekNumH = kFCLocalWeekNumH;
    CGFloat content  = barH + daysH + weekNumH;
    CGFloat slack    = MAX(0.0, b.size.height - content);
    CGFloat topPad   = slack * 0.5;
    CGFloat numY     = b.size.height - topPad - weekNumH;
    CGFloat daysY    = numY - daysH;
    CGFloat barY     = daysY - barH;
    _weekNumberLabel.frame    = NSMakeRect(0, numY,  b.size.width, weekNumH);
    _weekDayLabelsLabel.frame = NSMakeRect(0, daysY, b.size.width, daysH);
    _weekBarLabel.frame       = NSMakeRect(0, barY,  b.size.width, barH);
    fcAnchorDebugLabelBottomLeft(_debugLabel, self.bounds);
}

- (NSString *)fcNameID { return @"WEEK"; }
- (NSString *)fcFullName { return @"WEEK — week-progression block; ISO week #, day letters, and day-group dot bar"; }
- (void)fcRefreshDebugLabel { fcApplyDebugLabelVisibility(_debugLabel); }

- (NSMenu *)menuForEvent:(NSEvent *)event {
    // Week prefs (ShowWeekProgress / WeekProgressCellsPerDay) live in
    // LOCAL's scoped menu — delegate so users have one place to tweak.
    return [(id)self.panel buildLocalSegmentMenu];
}

@end
