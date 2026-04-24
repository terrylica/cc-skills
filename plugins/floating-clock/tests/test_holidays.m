// v4 iter-176: extracted from test_session.m when it crossed the
// 1000-LoC file-size-guard. Holiday-calendar lookup tests
// (iter-173 NYSE, iter-175 LSE) + integration-state lock
// (iter-174 NYSE computeSessionState gate) + iter-176 TSE.
//
// Shares the extern `failures` counter defined in test_session.m via
// test_levers.h. ASSERT_STATE macro redefined locally — not worth
// pulling into a shared header just yet.

#import <Foundation/Foundation.h>
#import "../Sources/data/MarketCatalog.h"
#import "../Sources/data/MarketSessionCalculator.h"
#import "../Sources/data/HolidayCalendar.h"
#import "test_levers.h"  // extern int failures

static NSDate *holidayDateAt(NSString *iana, int y, int m, int d, int h, int mm, int ss) {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:iana];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = y; c.month = m; c.day = d;
    c.hour = h; c.minute = mm; c.second = ss;
    return [cal dateFromComponents:c];
}

static const char *holidayStateName(SessionState s) {
    switch (s) {
        case kSessionOpen:       return "OPEN";
        case kSessionLunch:      return "LUNCH";
        case kSessionClosed:     return "CLOSED";
        case kSessionPreMarket:  return "PRE-MARKET";
        case kSessionAfterHours: return "AFTER-HOURS";
    }
    return "?";
}

#define ASSERT_HSTATE(mkt, date, expected)                                        \
    do {                                                                          \
        SessionState s; double _p; long _n;                                       \
        computeSessionState((mkt), (date), &s, &_p, &_n);                         \
        if (s != (expected)) {                                                    \
            fprintf(stderr, "FAIL %s: state expected %s got %s\n",                \
                    __func__, holidayStateName(expected), holidayStateName(s));   \
            failures++;                                                           \
        }                                                                         \
    } while (0)

void test_holiday_calendar_nyse(void) {
    // v4 iter-173: pure-data lookup test for FCIsMarketHoliday.
    const ClockMarket *nyse = marketForId(@"nyse");
    const ClockMarket *tse  = marketForId(@"tse");

    NSDate *thanksgiving = holidayDateAt(@"America/New_York", 2026, 11, 26, 12, 0, 0);
    NSDate *christmas    = holidayDateAt(@"America/New_York", 2026, 12, 25, 12, 0, 0);
    NSDate *newYears     = holidayDateAt(@"America/New_York", 2026,  1,  1, 12, 0, 0);
    if (!FCIsMarketHoliday(nyse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: Thanksgiving not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(nyse, christmas)) {
        failures++; fprintf(stderr, "FAIL %s: Christmas not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(nyse, newYears)) {
        failures++; fprintf(stderr, "FAIL %s: New Year's Day not flagged\n", __func__);
    }

    NSDate *regularFriday = holidayDateAt(@"America/New_York", 2026, 4, 24, 12, 0, 0);
    if (FCIsMarketHoliday(nyse, regularFriday)) {
        failures++; fprintf(stderr, "FAIL %s: Fri 2026-04-24 wrongly flagged\n", __func__);
    }

    // Cross-market: NYSE must not flag TSE-only Jan 2 bank holiday.
    NSDate *tseJan2 = holidayDateAt(@"America/New_York", 2026, 1, 2, 12, 0, 0);
    if (FCIsMarketHoliday(nyse, tseJan2)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged TSE-only Jan 2\n", __func__);
    }
    (void)tse;

    // Defensive: nil mkt + nil date return NO.
    if (FCIsMarketHoliday(NULL, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: nil mkt should return NO\n", __func__);
    }
    if (FCIsMarketHoliday(nyse, nil)) {
        failures++; fprintf(stderr, "FAIL %s: nil date should return NO\n", __func__);
    }
}

void test_holiday_calendar_lse(void) {
    // v4 iter-175: LSE 2026 bank-holiday lookup. Covers UK-distinctive
    // calendar — Easter Monday, Spring + Summer bank holidays, Boxing
    // Day observed Dec 28 because Dec 26 2026 is Saturday.
    const ClockMarket *lse  = marketForId(@"lse");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *easterMonday = holidayDateAt(@"Europe/London", 2026, 4, 6, 12, 0, 0);
    NSDate *springBank   = holidayDateAt(@"Europe/London", 2026, 5, 25, 12, 0, 0);
    NSDate *summerBank   = holidayDateAt(@"Europe/London", 2026, 8, 31, 12, 0, 0);
    NSDate *boxingObs    = holidayDateAt(@"Europe/London", 2026, 12, 28, 12, 0, 0);
    if (!FCIsMarketHoliday(lse, easterMonday)) {
        failures++; fprintf(stderr, "FAIL %s: Easter Monday not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(lse, springBank)) {
        failures++; fprintf(stderr, "FAIL %s: Spring bank holiday not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(lse, summerBank)) {
        failures++; fprintf(stderr, "FAIL %s: Summer bank holiday not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(lse, boxingObs)) {
        failures++; fprintf(stderr, "FAIL %s: Boxing Day (observed Dec 28) not flagged\n", __func__);
    }

    NSDate *thanksgiving = holidayDateAt(@"Europe/London", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(lse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: LSE wrongly flagged Thanksgiving\n", __func__);
    }
    if (FCIsMarketHoliday(nyse, easterMonday)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Easter Monday\n", __func__);
    }

    NSDate *regularWed = holidayDateAt(@"Europe/London", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(lse, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on LSE\n", __func__);
    }
}

void test_holiday_calendar_tse(void) {
    // v4 iter-176: TSE 2026 Japanese holiday lookup. Covers Shogatsu
    // Jan 2 bank holiday, Coming of Age Day, Golden Week cluster
    // (Apr 29 / May 4-6 incl. May 6 furikae substitute for Sun May 3),
    // summer + autumn equinox-tied holidays, Dec 31 year-end.
    const ClockMarket *tse  = marketForId(@"tse");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *bankJan2      = holidayDateAt(@"Asia/Tokyo", 2026,  1,  2, 12, 0, 0);
    NSDate *comingOfAge   = holidayDateAt(@"Asia/Tokyo", 2026,  1, 12, 12, 0, 0);
    NSDate *emperorBday   = holidayDateAt(@"Asia/Tokyo", 2026,  2, 23, 12, 0, 0);
    NSDate *showaDay      = holidayDateAt(@"Asia/Tokyo", 2026,  4, 29, 12, 0, 0);
    NSDate *goldenWeekSub = holidayDateAt(@"Asia/Tokyo", 2026,  5,  6, 12, 0, 0);
    NSDate *marineDay     = holidayDateAt(@"Asia/Tokyo", 2026,  7, 20, 12, 0, 0);
    NSDate *yearEnd       = holidayDateAt(@"Asia/Tokyo", 2026, 12, 31, 12, 0, 0);
    if (!FCIsMarketHoliday(tse, bankJan2)) {
        failures++; fprintf(stderr, "FAIL %s: TSE Jan 2 bank holiday not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, comingOfAge)) {
        failures++; fprintf(stderr, "FAIL %s: Coming of Age Day not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, emperorBday)) {
        failures++; fprintf(stderr, "FAIL %s: Emperor's Birthday not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, showaDay)) {
        failures++; fprintf(stderr, "FAIL %s: Showa Day not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, goldenWeekSub)) {
        failures++; fprintf(stderr, "FAIL %s: May 6 furikae substitute not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, marineDay)) {
        failures++; fprintf(stderr, "FAIL %s: Marine Day not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(tse, yearEnd)) {
        failures++; fprintf(stderr, "FAIL %s: Dec 31 year-end closure not flagged\n", __func__);
    }

    // Cross-market negatives: NYSE does NOT flag TSE-only holidays.
    if (FCIsMarketHoliday(nyse, comingOfAge)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Coming of Age Day\n", __func__);
    }
    if (FCIsMarketHoliday(nyse, showaDay)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Showa Day\n", __func__);
    }

    // TSE does NOT flag NYSE-only holidays.
    NSDate *thanksgiving = holidayDateAt(@"Asia/Tokyo", 2026, 11, 26, 12, 0, 0);
    NSDate *juneteenth   = holidayDateAt(@"Asia/Tokyo", 2026,  6, 19, 12, 0, 0);
    if (FCIsMarketHoliday(tse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: TSE wrongly flagged Thanksgiving\n", __func__);
    }
    if (FCIsMarketHoliday(tse, juneteenth)) {
        failures++; fprintf(stderr, "FAIL %s: TSE wrongly flagged Juneteenth\n", __func__);
    }

    NSDate *regularWed = holidayDateAt(@"Asia/Tokyo", 2026, 6, 10, 12, 0, 0);
    if (FCIsMarketHoliday(tse, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-06-10 wrongly flagged on TSE\n", __func__);
    }
}

void test_nyse_holiday_state_closed(void) {
    // v4 iter-174: integration lock. Verifies FCIsMarketHoliday result
    // is actually consumed by computeSessionState — forces CLOSED and
    // blocks PRE/AFTER promotions on holidays.
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *thanksgivingMidday    = holidayDateAt(@"America/New_York", 2026, 11, 26, 12, 0, 0);
    NSDate *thanksgivingPreOpen   = holidayDateAt(@"America/New_York", 2026, 11, 26,  9, 25, 0);
    NSDate *thanksgivingPostClose = holidayDateAt(@"America/New_York", 2026, 11, 26, 16,  5, 0);
    NSDate *regularFridayMidday   = holidayDateAt(@"America/New_York", 2026,  4, 24, 12,  0, 0);

    ASSERT_HSTATE(nyse, thanksgivingMidday,    kSessionClosed);
    ASSERT_HSTATE(nyse, thanksgivingPreOpen,   kSessionClosed);
    ASSERT_HSTATE(nyse, thanksgivingPostClose, kSessionClosed);
    ASSERT_HSTATE(nyse, regularFridayMidday,   kSessionOpen);
}
