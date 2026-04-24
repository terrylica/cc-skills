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

// v4 iter-178: HKEX 2026 non-trading days. Source: HKEX published
// calendar. First calendar to feature lunar-calendar holidays
// (Lunar New Year 3-day cluster, Buddha's Birthday, Dragon Boat,
// Mid-Autumn, Chung Yeung) whose Gregorian dates shift year-by-year
// — this fixture-locks the 2026 mapping. Good Friday + Easter Monday
// coincide with Ching Ming Festival 2026-04-05 Sun → observed Mon
// (combined into one day off). Half-day trading sessions (e.g. LNY
// Eve 2026-02-16 Mon) render as full sessions — half-day handling
// deferred.
static NSString * const kHKEX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-02-17",  // Lunar New Year Day 1 (農曆新年初一)
    @"2026-02-18",  // Lunar New Year Day 2 (初二)
    @"2026-02-19",  // Lunar New Year Day 3 (初三)
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday / Ching Ming observed (coincident)
    @"2026-05-01",  // Labour Day
    @"2026-05-25",  // Buddha's Birthday observed (lunar Apr 8 = Sun May 24)
    @"2026-06-19",  // Dragon Boat Festival (端午節)
    @"2026-07-01",  // HKSAR Establishment Day
    @"2026-09-25",  // Mid-Autumn Festival (中秋節)
    @"2026-10-01",  // National Day (國慶日)
    @"2026-10-19",  // Chung Yeung Festival (重陽節)
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // 1st weekday after Christmas (Boxing Day observed; Dec 26 Sat)
};

// v4 iter-179: TARGET2-aligned exchanges (XETRA Frankfurt + Euronext
// Paris/Amsterdam/Brussels/Lisbon/Dublin). Both use the same 5-date
// TARGET2 settlement-calendar closures in 2026. One shared array,
// two registry entries below — no data duplication. Dec 26 Boxing
// Day falls Saturday 2026 so weekend handling covers it (skip here).
// Half-day sessions (Dec 24 Christmas Eve + Dec 31 NYE shortened
// trading) render as full days, consistent with other markets.
static NSString * const kTARGET2_2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-05-01",  // Labour Day
    @"2026-12-25",  // Christmas Day
};

// v4 iter-180: ASX 2026 non-trading days. Source: ASX published
// calendar. Distinctive: **Easter Tuesday** — ASX is one of the few
// major exchanges that closes the Tuesday after Easter Mon (4-day
// Easter long weekend for Australia). ANZAC Day Apr 25 2026 falls on
// Saturday — ASX does not observe a Monday substitute when ANZAC is
// on weekend (weekend branch handles the closure). King's Birthday is
// the 2nd Monday of June for NSW / VIC / ACT (where ASX operates).
static NSString * const kASX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-01-26",  // Australia Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-04-07",  // Easter Tuesday (ASX-distinctive)
    @"2026-06-08",  // King's Birthday (2nd Mon of Jun)
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // Boxing Day observed (Dec 26 Sat)
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
    { "nyse",     kNYSE2026Holidays,    sizeof(kNYSE2026Holidays)    / sizeof(kNYSE2026Holidays[0])    },
    { "lse",      kLSE2026Holidays,     sizeof(kLSE2026Holidays)     / sizeof(kLSE2026Holidays[0])     },
    { "tse",      kTSE2026Holidays,     sizeof(kTSE2026Holidays)     / sizeof(kTSE2026Holidays[0])     },
    { "hkex",     kHKEX2026Holidays,    sizeof(kHKEX2026Holidays)    / sizeof(kHKEX2026Holidays[0])    },
    // v4 iter-179: both XETRA + Euronext reference kTARGET2_2026Holidays.
    { "xetra",    kTARGET2_2026Holidays, sizeof(kTARGET2_2026Holidays) / sizeof(kTARGET2_2026Holidays[0]) },
    { "euronext", kTARGET2_2026Holidays, sizeof(kTARGET2_2026Holidays) / sizeof(kTARGET2_2026Holidays[0]) },
    { "asx",      kASX2026Holidays,      sizeof(kASX2026Holidays)      / sizeof(kASX2026Holidays[0])      },
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
