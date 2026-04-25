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

// v4 iter-230: structured per-day rendering with day separators.
// Returns a plain NSString of 7 day-groups (each `cellsPerDay`
// cells wide) joined by `┊` (U+250A light dotted vertical line).
// Each day's cells reflect that day's progress relative to `now`:
// past days fully filled, current day partial by hour-fraction,
// future days empty. Uses the user-selected ProgressBarStyle glyph
// pair (consistency with ACTIVE bar). cellsPerDay must be >= 1.
// `now` may be nil — function returns an all-empty bar in that case.
//
// Total displayed width: 7 × cellsPerDay characters + 6 separators.
// Default cellsPerDay = 2 → 14 cells + 6 separators = 20 chars.
NSString *FCBuildWeekProgressBar(NSDate * _Nullable now, int cellsPerDay);

// v4 iter-233: attributed variant with weekend-dimming + theme-color
// awareness. Same 7-day-group structure as the plain variant but
// returns an NSAttributedString with per-character color:
//   weekday filled cells (Mon–Fri):  filledColor
//   weekday empty cells:             emptyColor
//   weekend filled cells (Sat–Sun):  filledColor × kWeekendDimAlpha
//   weekend empty cells:             emptyColor × kWeekendDimAlpha
//   day separators (┊):              emptyColor (always dim, both weeks)
// Caller passes the active font (typically the segment's mono font)
// so per-glyph attributes are consistent with the surrounding text.
NSAttributedString *FCBuildWeekProgressBarAttributed(NSDate * _Nullable now,
                                                     int cellsPerDay,
                                                     NSColor *filledColor,
                                                     NSColor *emptyColor,
                                                     NSFont *font);

// v4 iter-234: day-letter row aligned over the bar's day-groups.
// Returns "MTWTFSS" with cellsPerDay-wide centered slots and ┊
// separators — matches FCBuildWeekProgressBar's structure char-for-char
// (minus the ▕ ▏ brackets) so rendering both centered in equal-width
// labels lines them up vertically.
NSString *FCBuildWeekDayLabels(int cellsPerDay);

// v4 iter-240/iter-241: phase color for hour-of-day. Mirrors iter-112's
// SkyGlyph 5-phase logic. Returns nil for "day" phase so callers can
// fall back to their theme foreground (LocalTheme harmony). Other
// phases return distinct tints:
//   hour ∈ [5, 7)   → dawn   warm amber (R 0.98, G 0.78, B 0.40)
//   hour ∈ [7, 17)  → day    nil       (caller uses theme color)
//   hour ∈ [17, 19) → dusk   warm rose (R 0.95, G 0.50, B 0.55)
//   hour ∈ [19, 5)  → night  cool blue (R 0.45, G 0.55, B 0.85)
NSColor * _Nullable FCPhaseColorForHour(NSInteger hour);

// v4 iter-234: ISO 8601 week-of-year for `now` in the system locale.
// Financial-market convention (Reuters / Bloomberg / SWIFT / Basel
// reporting) — Mon-start week, week 1 = the week containing the
// year's first Thursday. Returns 1..53. nil → 0.
NSInteger FCISOWeekOfYear(NSDate * _Nullable now);

// 0.0 (just past Mon midnight) → 1.0 (just before next Mon midnight).
// Pure function for testability — buildProgressBar wraps this. nil
// returns 0.0.
double FCWeekFraction(NSDate * _Nullable now);

NS_ASSUME_NONNULL_END
