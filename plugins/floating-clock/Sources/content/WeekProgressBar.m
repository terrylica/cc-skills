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

NSString *FCBuildWeekProgressBar(NSDate *now, int totalCells) {
    if (totalCells < 1) totalCells = 1;
    double frac = FCWeekFraction(now);
    return buildProgressBar(frac, totalCells);
}
