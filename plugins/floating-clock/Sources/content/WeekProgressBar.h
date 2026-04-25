// v4 iter-229: weekly time-progress bar for the LOCAL segment.
//
// User asked for "an elegant stretchable line showing where we are
// in the current week" on the LOCAL segment. Pure offline — derives
// the fraction-into-week from the system calendar's notion of
// "today" + "now" within today. No network, no API key, no
// astronomical math. Future iters can layer dusk/dawn shading,
// holiday strike-through, weather glyphs (those need lat/lon and/or
// network — separate decision).
//
// Math: ISO week starts Monday. weekFraction =
//   (weekday_zero_indexed * 24 + hour + min/60 + sec/3600) / (7 * 24)
// Reuses the existing `buildProgressBar` math for cell-fill +
// 1/8-width-block sub-cell smoothness; pulled into FCBuildWeekProgressBar
// so the LOCAL row gets a self-contained string.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Returns a plain NSString suitable for inline concatenation into
// the LOCAL row's text. Uses the user-selected ProgressBarStyle
// glyph pair (consistency with ACTIVE bar). totalCells must be >= 1.
// `now` may be nil — function returns an all-empty bar in that case.
NSString *FCBuildWeekProgressBar(NSDate * _Nullable now, int totalCells);

// 0.0 (just past Mon midnight) → 1.0 (just before next Mon midnight).
// Pure function for testability — buildProgressBar wraps this. nil
// returns 0.0.
double FCWeekFraction(NSDate * _Nullable now);

NS_ASSUME_NONNULL_END
