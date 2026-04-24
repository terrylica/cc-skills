#import "HolidayCalendar.h"
#include <string.h>

// NYSE 2026 full-closure days. Source: NYSE public holiday calendar.
// Does NOT include half-days (deferred — those render as open until
// early-close handling lands).
static NSString * const kNYSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-01-19",  // Martin Luther King Jr. Day
    @"2026-02-16",  // Presidents' Day
    @"2026-04-03",  // Good Friday
    @"2026-05-25",  // Memorial Day
    @"2026-06-19",  // Juneteenth
    @"2026-07-03",  // Independence Day (observed; Jul 4 falls Saturday)
    @"2026-09-07",  // Labor Day
    @"2026-11-26",  // Thanksgiving
    @"2026-12-25",  // Christmas
};
static const size_t kNumNYSE2026Holidays = sizeof(kNYSE2026Holidays) / sizeof(kNYSE2026Holidays[0]);

BOOL FCIsMarketHoliday(const ClockMarket *mkt, NSDate *date) {
    if (!mkt || !date) return NO;
    if (strcmp(mkt->id, "nyse") != 0) return NO;  // only NYSE data this iter

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
    NSString *iso = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                     (long)c.year, (long)c.month, (long)c.day];
    for (size_t i = 0; i < kNumNYSE2026Holidays; i++) {
        if ([iso isEqualToString:kNYSE2026Holidays[i]]) return YES;
    }
    return NO;
}
