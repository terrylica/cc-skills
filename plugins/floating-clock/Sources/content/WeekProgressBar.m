#import "WeekProgressBar.h"
#import "../data/MarketSessionCalculator.h"  // buildProgressBar reuse

double FCWeekFraction(NSDate *now) {
    if (!now) return 0.0;
    NSCalendar *cal = [NSCalendar currentCalendar];
    // ISO week: Monday is day 2 in NSCalendar's 1=Sunday convention.
    // Convert to Mon=0..Sun=6 zero-indexed weekday.
    NSInteger gregWeekday = [cal component:NSCalendarUnitWeekday fromDate:now];  // 1=Sun, 2=Mon, ..., 7=Sat
    NSInteger monIdx = (gregWeekday + 5) % 7;  // Mon=0, Tue=1, ..., Sun=6

    NSDateComponents *hms = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                   fromDate:now];
    double hourFraction = (double)hms.hour
                        + (double)hms.minute / 60.0
                        + (double)hms.second / 3600.0;
    double weekHours = (double)monIdx * 24.0 + hourFraction;
    double frac = weekHours / (7.0 * 24.0);
    if (frac < 0.0) frac = 0.0;
    if (frac > 1.0) frac = 1.0;
    return frac;
}

// v4 iter-230: structured per-day rendering with day separators.
// Gives the bar visible weekly rhythm — 7 day-segments delimited by
// `┊` (light dotted vertical line, U+250A). Total width:
//   7 × cellsPerDay characters + 6 separators
//
// Each day's cells reflect that day's progress relative to `now`:
//   day < currentDay   → fully filled
//   day == currentDay  → partially filled by hour-fraction
//   day > currentDay   → empty
//
// Reuses `buildProgressBar` per-day so the user's ProgressBarStyle
// glyph pair carries through.
NSString *FCBuildWeekProgressBar(NSDate *now, int cellsPerDay) {
    if (cellsPerDay < 1) cellsPerDay = 1;
    if (!now) {
        // Default-empty rendering: 7 empty day-groups.
        NSMutableString *empty = [NSMutableString string];
        for (int d = 0; d < 7; d++) {
            if (d > 0) [empty appendString:@"┊"];
            [empty appendString:buildProgressBar(0.0, cellsPerDay)];
        }
        return empty;
    }

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger gregWeekday = [cal component:NSCalendarUnitWeekday fromDate:now];
    NSInteger currentDayIdx = (gregWeekday + 5) % 7;  // Mon=0..Sun=6

    NSDateComponents *hms = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                   fromDate:now];
    double hourFrac = ((double)hms.hour
                     + (double)hms.minute / 60.0
                     + (double)hms.second / 3600.0) / 24.0;

    NSMutableString *bar = [NSMutableString string];
    for (NSInteger d = 0; d < 7; d++) {
        if (d > 0) [bar appendString:@"┊"];
        double dayFrac;
        if (d < currentDayIdx)      dayFrac = 1.0;
        else if (d == currentDayIdx) dayFrac = hourFrac;
        else                         dayFrac = 0.0;
        [bar appendString:buildProgressBar(dayFrac, cellsPerDay)];
    }
    return bar;
}

// v4 iter-233: dim factor for weekend (Sat/Sun) cells. Below 1.0 =
// muted vs weekday cells. 0.45 = noticeably dimmer but still legible.
static const CGFloat kWeekendDimAlpha = 0.45;

// Helper: returns YES if Mon=0..Sun=6 day index is a weekend.
static BOOL fcIsWeekendDayIdx(NSInteger d) { return d == 5 || d == 6; }

NSAttributedString *FCBuildWeekProgressBarAttributed(NSDate *now, int cellsPerDay,
                                                     NSColor *filledColor, NSColor *emptyColor,
                                                     NSFont *font) {
    NSString *plain = FCBuildWeekProgressBar(now, cellsPerDay);
    if (cellsPerDay < 1) cellsPerDay = 1;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger currentDayIdx = -1;
    if (now) {
        NSInteger gregWeekday = [cal component:NSCalendarUnitWeekday fromDate:now];
        currentDayIdx = (gregWeekday + 5) % 7;
    }

    NSColor *filledDim = [filledColor colorWithAlphaComponent:filledColor.alphaComponent * kWeekendDimAlpha];
    NSColor *emptyDim  = [emptyColor  colorWithAlphaComponent:emptyColor.alphaComponent  * kWeekendDimAlpha];

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:plain];
    [out addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, plain.length)];

    // Walk: 7 day-groups separated by single-char `┊`. Within each group,
    // first `fullCells` cells are filled, rest empty. Apply weekend
    // dimming on Sat/Sun day-groups; separators stay at emptyColor
    // (always dim) regardless of which day-pair they border.
    NSUInteger pos = 0;
    for (NSInteger d = 0; d < 7; d++) {
        if (d > 0) {
            // Separator at `pos` is a single character.
            [out addAttribute:NSForegroundColorAttributeName value:emptyColor
                        range:NSMakeRange(pos, 1)];
            pos += 1;
        }
        // dayFrac for fill computation
        double dayFrac = 0.0;
        if (d < currentDayIdx)       dayFrac = 1.0;
        else if (d == currentDayIdx) {
            NSDateComponents *hms = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                           fromDate:now];
            dayFrac = ((double)hms.hour + (double)hms.minute / 60.0 + (double)hms.second / 3600.0) / 24.0;
        }
        int fullCells = (int)(dayFrac * cellsPerDay + 0.5);
        if (fullCells > cellsPerDay) fullCells = cellsPerDay;
        if (fullCells < 0) fullCells = 0;

        BOOL weekend = fcIsWeekendDayIdx(d);
        NSColor *fillC  = weekend ? filledDim : filledColor;
        NSColor *emptyC = weekend ? emptyDim  : emptyColor;

        if (fullCells > 0) {
            [out addAttribute:NSForegroundColorAttributeName value:fillC
                        range:NSMakeRange(pos, (NSUInteger)fullCells)];
        }
        if (fullCells < cellsPerDay) {
            [out addAttribute:NSForegroundColorAttributeName value:emptyC
                        range:NSMakeRange(pos + (NSUInteger)fullCells,
                                          (NSUInteger)(cellsPerDay - fullCells))];
        }
        pos += (NSUInteger)cellsPerDay;
    }
    return out;
}
