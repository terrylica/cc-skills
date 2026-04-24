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

// v4 iter-175: LSE 2026 bank holidays. Source:
// https://www.londonstockexchange.com/equities-trading/business-days
// Full-day closures only; half-days (Christmas Eve, New Year's Eve)
// deferred to early-close handling.
static NSString * const kLSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-05-04",  // Early May bank holiday
    @"2026-05-25",  // Spring bank holiday
    @"2026-08-31",  // Summer bank holiday
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // Boxing Day (observed; Dec 26 is Saturday)
};

// v4 iter-176: TSE 2026 non-trading days. Source: JPX (Japan Exchange
// Group) official calendar. Excludes weekend-coincident holidays
// (Jan 3 Sat Bank Holiday, May 3 Sun Constitution Memorial Day) — the
// isWeekend branch in computeSessionState already handles those.
// May 6 is a furikae-kyujitsu (substitute holiday) because May 3 fell
// on Sunday. Half-days (大発会 / 大納会 shortened sessions) deferred.
static NSString * const kTSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day (元日)
    @"2026-01-02",  // Bank holiday (銀行休業日)
    @"2026-01-12",  // Coming of Age Day (成人の日 — 2nd Mon of Jan)
    @"2026-02-11",  // National Foundation Day (建国記念の日)
    @"2026-02-23",  // Emperor's Birthday (天皇誕生日)
    @"2026-03-20",  // Vernal Equinox Day (春分の日)
    @"2026-04-29",  // Showa Day (昭和の日)
    @"2026-05-04",  // Greenery Day (みどりの日)
    @"2026-05-05",  // Children's Day (こどもの日)
    @"2026-05-06",  // Substitute holiday for May 3 (振替休日)
    @"2026-07-20",  // Marine Day (海の日 — 3rd Mon of Jul)
    @"2026-08-11",  // Mountain Day (山の日)
    @"2026-09-21",  // Respect for the Aged Day (敬老の日 — 3rd Mon of Sep)
    @"2026-09-23",  // Autumnal Equinox Day (秋分の日)
    @"2026-10-12",  // Sports Day (スポーツの日 — 2nd Mon of Oct)
    @"2026-11-03",  // Culture Day (文化の日)
    @"2026-11-23",  // Labor Thanksgiving Day (勤労感謝の日)
    @"2026-12-31",  // Year-end non-trading day (大納会 was Dec 30)
};

// v4 iter-175: per-market registry. Adding an exchange's holiday data
// = append one entry here + one static array above. No function-body
// changes. The lookup fans out by market_id match.
typedef struct {
    const char *market_id;
    NSString * const * _Nonnull dates;
    size_t count;
} FCHolidayTable;

static const FCHolidayTable kHolidayTables[] = {
    { "nyse", kNYSE2026Holidays, sizeof(kNYSE2026Holidays) / sizeof(kNYSE2026Holidays[0]) },
    { "lse",  kLSE2026Holidays,  sizeof(kLSE2026Holidays)  / sizeof(kLSE2026Holidays[0])  },
    { "tse",  kTSE2026Holidays,  sizeof(kTSE2026Holidays)  / sizeof(kTSE2026Holidays[0])  },
};
static const size_t kNumHolidayTables = sizeof(kHolidayTables) / sizeof(kHolidayTables[0]);

BOOL FCIsMarketHoliday(const ClockMarket *mkt, NSDate *date) {
    if (!mkt || !date) return NO;

    const FCHolidayTable *tbl = NULL;
    for (size_t i = 0; i < kNumHolidayTables; i++) {
        if (strcmp(mkt->id, kHolidayTables[i].market_id) == 0) {
            tbl = &kHolidayTables[i];
            break;
        }
    }
    if (!tbl) return NO;  // no data for this market yet

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
    NSString *iso = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                     (long)c.year, (long)c.month, (long)c.day];
    for (size_t i = 0; i < tbl->count; i++) {
        if ([iso isEqualToString:tbl->dates[i]]) return YES;
    }
    return NO;
}
