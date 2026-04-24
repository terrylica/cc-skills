#import "HalfDayCalendar.h"
#include <string.h>

// Entry in a per-market half-day array. Date stored as ISO string for
// easy byte-compare via isEqualToString; close time as separate h/m
// ints to avoid mutable NSDateComponents alloc on every lookup.
typedef struct {
    NSString * _Nonnull iso;
    int close_h;
    int close_m;
} FCHalfDayEntry;

// v4 iter-188: NYSE 2026 half-day sessions. Source: NYSE published
// early-close calendar. Both dates close at 13:00 ET (1:00 pm).
// Day-after-Thanksgiving ("Black Friday") Nov 27 2026, and Christmas
// Eve Dec 24 2026 Thursday.
static const FCHalfDayEntry kNYSE2026HalfDays[] = {
    { @"2026-11-27", 13, 0 },  // Day after Thanksgiving (Black Friday)
    { @"2026-12-24", 13, 0 },  // Christmas Eve
};

typedef struct {
    const char *market_id;
    const FCHalfDayEntry * _Nonnull entries;
    size_t count;
} FCHalfDayTable;

static const FCHalfDayTable kHalfDayTables[] = {
    { "nyse", kNYSE2026HalfDays, sizeof(kNYSE2026HalfDays) / sizeof(kNYSE2026HalfDays[0]) },
};
static const size_t kNumHalfDayTables = sizeof(kHalfDayTables) / sizeof(kHalfDayTables[0]);

BOOL FCIsMarketHalfDay(const ClockMarket *mkt,
                       NSDate *date,
                       int *outCloseHour,
                       int *outCloseMinute) {
    if (!mkt || !date) return NO;

    const FCHalfDayTable *tbl = NULL;
    for (size_t i = 0; i < kNumHalfDayTables; i++) {
        if (strcmp(mkt->id, kHalfDayTables[i].market_id) == 0) {
            tbl = &kHalfDayTables[i];
            break;
        }
    }
    if (!tbl) return NO;

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
    NSString *iso = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                     (long)c.year, (long)c.month, (long)c.day];
    for (size_t i = 0; i < tbl->count; i++) {
        if ([iso isEqualToString:tbl->entries[i].iso]) {
            if (outCloseHour)   *outCloseHour   = tbl->entries[i].close_h;
            if (outCloseMinute) *outCloseMinute = tbl->entries[i].close_m;
            return YES;
        }
    }
    return NO;
}
