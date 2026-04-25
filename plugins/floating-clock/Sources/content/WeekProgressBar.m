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

NSString *FCBuildWeekDayLabels(int cellsPerDay) {
    if (cellsPerDay < 1) cellsPerDay = 1;
    static const char *kLetters = "MTWTFSS";
    NSMutableString *out = [NSMutableString string];
    for (int d = 0; d < 7; d++) {
        if (d > 0) [out appendString:@"┊"];
        // Center the single letter in cellsPerDay slots:
        //   leftPad  = (cellsPerDay - 1) / 2     (favors left when even)
        //   rightPad = cellsPerDay - 1 - leftPad
        int leftPad  = (cellsPerDay - 1) / 2;
        int rightPad = (cellsPerDay - 1) - leftPad;
        for (int i = 0; i < leftPad; i++)  [out appendString:@" "];
        [out appendFormat:@"%c", kLetters[d]];
        for (int i = 0; i < rightPad; i++) [out appendString:@" "];
    }
    return out;
}

NSInteger FCISOWeekOfYear(NSDate *now) {
    if (!now) return 0;
    // Use ISO 8601 calendar settings: Mon first day, min 4 days in
    // first week. NSCalendar's `weekOfYear` component honors these
    // settings → returns 1..53 per ISO spec.
    NSCalendar *iso = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierISO8601];
    if (!iso) {
        // Fallback: tweak gregorian. (NSCalendarIdentifierISO8601 was
        // added in macOS 10.10 — should always be present, but
        // defensive code never hurts.)
        iso = [NSCalendar currentCalendar];
        iso.firstWeekday = 2;             // Mon
        iso.minimumDaysInFirstWeek = 4;   // ISO 8601
    }
    NSDateComponents *c = [iso components:NSCalendarUnitWeekOfYear fromDate:now];
    return c.weekOfYear;
}

// v4 iter-233: dim factor for weekend (Sat/Sun) cells. Below 1.0 =
// muted vs weekday cells. 0.45 = noticeably dimmer but still legible.
static const CGFloat kWeekendDimAlpha = 0.45;

// Helper: returns YES if Mon=0..Sun=6 day index is a weekend.
static BOOL fcIsWeekendDayIdx(NSInteger d) { return d == 5 || d == 6; }

// v4 iter-235: fine-grain boundary glyph selector. Maps fractional
// cell remainder (0.0..1.0) to a Unicode pie/circle glyph for
// 5-level sub-cell rendering when the user's ProgressBarStyle is
// "dots":
//   ≤0.125  → empty  ○     (round down)
//   ≤0.375  → quarter ◔
//   ≤0.625  → half    ◐
//   ≤0.875  → three-q ◕
//   >0.875  → full   ●     (round up)
static NSString *fcFineGrainBoundaryGlyph(double remainder) {
    if (remainder <= 0.125) return @"○";
    if (remainder <= 0.375) return @"◔";
    if (remainder <= 0.625) return @"◐";
    if (remainder <= 0.875) return @"◕";
    return @"●";
}

NSAttributedString *FCBuildWeekProgressBarAttributed(NSDate *now, int cellsPerDay,
                                                     NSColor *filledColor, NSColor *emptyColor,
                                                     NSFont *font) {
    if (cellsPerDay < 1) cellsPerDay = 1;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger currentDayIdx = -1;
    double currentHourFrac = 0.0;
    if (now) {
        NSInteger gregWeekday = [cal component:NSCalendarUnitWeekday fromDate:now];
        currentDayIdx = (gregWeekday + 5) % 7;
        NSDateComponents *hms = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                       fromDate:now];
        currentHourFrac = ((double)hms.hour + (double)hms.minute / 60.0 + (double)hms.second / 3600.0) / 24.0;
    }

    // iter-235: detect dots style for fine-grain. Other styles still
    // get integer fill via FCBuildWeekProgressBar (no half-dots
    // available in those families).
    NSString *prefStyle = [[NSUserDefaults standardUserDefaults] stringForKey:@"ProgressBarStyle"];
    BOOL fineGrain = (prefStyle == nil) || [prefStyle isEqualToString:@"dots"];

    NSColor *filledDim = [filledColor colorWithAlphaComponent:filledColor.alphaComponent * kWeekendDimAlpha];
    NSColor *emptyDim  = [emptyColor  colorWithAlphaComponent:emptyColor.alphaComponent  * kWeekendDimAlpha];

    // Build string char-by-char so we can substitute the boundary
    // glyph on the current day. Color attributes go alongside.
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSDictionary *fontOnly = @{NSFontAttributeName: font};

    for (NSInteger d = 0; d < 7; d++) {
        if (d > 0) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"┊"
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: emptyColor}]];
        }
        double dayFrac = 0.0;
        if (d < currentDayIdx)       dayFrac = 1.0;
        else if (d == currentDayIdx) dayFrac = currentHourFrac;

        BOOL weekend = fcIsWeekendDayIdx(d);
        NSColor *fillC  = weekend ? filledDim : filledColor;
        NSColor *emptyC = weekend ? emptyDim  : emptyColor;

        // Filled cell count + fractional remainder for the boundary cell.
        double cellsExact = dayFrac * (double)cellsPerDay;
        int fullCells = (int)cellsExact;
        double remainder = cellsExact - (double)fullCells;
        if (fullCells > cellsPerDay) { fullCells = cellsPerDay; remainder = 0.0; }
        if (fullCells < 0) fullCells = 0;

        for (int i = 0; i < cellsPerDay; i++) {
            NSString *glyph;
            NSColor *color;
            if (i < fullCells) { glyph = fineGrain ? @"●" : @"●"; color = fillC; }
            else if (i == fullCells && fineGrain && d == currentDayIdx && remainder > 0.0) {
                // Boundary cell: render the fine-grain quarter/half/three-q glyph.
                glyph = fcFineGrainBoundaryGlyph(remainder);
                // Use fillC if glyph has any fill, otherwise emptyC.
                color = ([glyph isEqualToString:@"○"]) ? emptyC : fillC;
            } else {
                glyph = fineGrain ? @"○" : @"○"; color = emptyC;
            }
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:glyph
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}]];
        }
    }
    (void)fontOnly;
    return out;
}
