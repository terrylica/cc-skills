// Unit tests for computeSessionState and related helpers.
//
// Runs as a standalone binary. Each test constructs a fixed NSDate in
// the relevant market's timezone, calls computeSessionState, and
// asserts state/progress/secsToNext. Any failure exits with a non-zero
// code so `make test` fails CI.
//
// Design intent: lightweight — we don't need a full framework. Print
// failing test name + expected vs actual and accumulate a failure
// count. Exit non-zero if any test failed.
//
// History: added after v4 iter-48 caught a "closed-before-open-today"
// off-by-7h bug that had shipped since iter-9 (session-state intro).

#import <Foundation/Foundation.h>
#import "../Sources/data/MarketCatalog.h"
#import "../Sources/data/MarketSessionCalculator.h"

static int failures = 0;

static NSDate *dateAt(NSString *iana, int y, int m, int d, int h, int mm, int ss) {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:iana];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = y; c.month = m; c.day = d;
    c.hour = h; c.minute = mm; c.second = ss;
    return [cal dateFromComponents:c];
}

static const char *stateName(SessionState s) {
    switch (s) {
        case kSessionOpen: return "OPEN";
        case kSessionLunch: return "LUNCH";
        case kSessionClosed: return "CLOSED";
    }
    return "?";
}

// Header annotates out-params as nonnull even though the implementation
// guards each write with `if (outXxx)`. Pass throwaway locals here to
// satisfy the annotation without changing the public contract.
#define ASSERT_STATE(mkt, date, expected)                                        \
    do {                                                                         \
        SessionState s; double _p; long _n;                                      \
        computeSessionState((mkt), (date), &s, &_p, &_n);                        \
        if (s != (expected)) {                                                   \
            fprintf(stderr, "FAIL %s: state expected %s got %s\n",               \
                    __func__, stateName(expected), stateName(s));                \
            failures++;                                                          \
        }                                                                        \
    } while (0)

#define ASSERT_SECS_NEAR(mkt, date, expected, tolerance)                         \
    do {                                                                         \
        SessionState _s; double _p; long actual;                                 \
        computeSessionState((mkt), (date), &_s, &_p, &actual);                   \
        long diff = actual > (expected) ? actual - (expected) : (expected) - actual; \
        if (diff > (tolerance)) {                                                \
            fprintf(stderr, "FAIL %s: secsToNext expected ~%ld got %ld (diff %ld)\n", \
                    __func__, (long)(expected), actual, diff);                   \
            failures++;                                                          \
        }                                                                        \
    } while (0)

// ---- Cases ----

static void test_nyse_closed_before_open_today(void) {
    // v4 iter-48 regression test. 2026-04-24 07:00 EDT = Friday morning
    // before the 09:30 open. Expected secsToNext = 2h 30m = 9000 s.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 7, 0, 0);
    ASSERT_STATE(nyse, d, kSessionClosed);
    ASSERT_SECS_NEAR(nyse, d, 9000, 5);
}

static void test_nyse_open_midsession(void) {
    // Friday 12:00 EDT = 2h30m after open, 4h until close (16:00).
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 12, 0, 0);
    ASSERT_STATE(nyse, d, kSessionOpen);
    ASSERT_SECS_NEAR(nyse, d, 4 * 3600, 5);
}

static void test_nyse_closed_friday_evening_skips_to_monday(void) {
    // Friday 20:00 EDT (after close). Next open is Monday 09:30 EDT —
    // 61h 30m = 221400 s.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 20, 0, 0);
    ASSERT_STATE(nyse, d, kSessionClosed);
    ASSERT_SECS_NEAR(nyse, d, 61 * 3600 + 30 * 60, 120);
}

static void test_nyse_saturday_weekend(void) {
    // Saturday afternoon. Next open is Monday 09:30. Should be ~41.5h
    // at Saturday noon → 149400 s.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 25, 12, 0, 0);
    ASSERT_STATE(nyse, d, kSessionClosed);
    ASSERT_SECS_NEAR(nyse, d, 45 * 3600 + 30 * 60, 120);
}

static void test_tse_lunch_window(void) {
    // TSE lunch is 11:30-12:30 JST. At 12:00 JST the state is LUNCH
    // and secsToNext is 30min = 1800s to lunchEnd.
    const ClockMarket *tse = marketForId(@"tse");
    NSDate *d = dateAt(@"Asia/Tokyo", 2026, 4, 24, 12, 0, 0);
    ASSERT_STATE(tse, d, kSessionLunch);
    ASSERT_SECS_NEAR(tse, d, 30 * 60, 5);
}

static void test_progress_roughly_correct(void) {
    // NYSE at 13:00 EDT (half-way). closeMins=16*60=960, openMins=570,
    // nowMins=780. progress = (780-570)/(960-570) = 210/390 ≈ 0.538.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 13, 0, 0);
    SessionState s; double p; long n;
    computeSessionState(nyse, d, &s, &p, &n);
    if (p < 0.50 || p > 0.58) {
        fprintf(stderr, "FAIL %s: progress expected ~0.54 got %f\n", __func__, p);
        failures++;
    }
}

// ---- TZ-helper fixtures (iter-37/38) ----
//
// Northern-hemisphere DST is on 2026-04-24 (late April — well into
// summer time). A January date exercises standard time. Southern-
// hemisphere (Australia) is inverted.

#define ASSERT_EQ_STR(actual, expected)                                          \
    do {                                                                         \
        if (![(actual) isEqualToString:(expected)]) {                            \
            fprintf(stderr, "FAIL %s: expected '%s' got '%s'\n",                 \
                    __func__, [(expected) UTF8String], [(actual) UTF8String]);   \
            failures++;                                                          \
        }                                                                        \
    } while (0)

static void test_abbrev_london_dst_vs_standard(void) {
    NSDate *summer = dateAt(@"Europe/London", 2026, 7, 15, 12, 0, 0);
    NSDate *winter = dateAt(@"Europe/London", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(friendlyAbbrevForIana("Europe/London", summer), @"BST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Europe/London", winter), @"GMT");
}

static void test_abbrev_paris_dst_vs_standard(void) {
    NSDate *summer = dateAt(@"Europe/Paris", 2026, 7, 15, 12, 0, 0);
    NSDate *winter = dateAt(@"Europe/Paris", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(friendlyAbbrevForIana("Europe/Paris", summer), @"CEST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Europe/Paris", winter), @"CET");
}

static void test_abbrev_new_york_dst_vs_standard(void) {
    NSDate *summer = dateAt(@"America/New_York", 2026, 7, 15, 12, 0, 0);
    NSDate *winter = dateAt(@"America/New_York", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(friendlyAbbrevForIana("America/New_York", summer), @"EDT");
    ASSERT_EQ_STR(friendlyAbbrevForIana("America/New_York", winter), @"EST");
}

static void test_abbrev_sydney_inverted(void) {
    // Southern hemisphere DST. July = standard (AEST), January = summer (AEDT).
    NSDate *nh_summer = dateAt(@"Australia/Sydney", 2026, 7, 15, 12, 0, 0);
    NSDate *nh_winter = dateAt(@"Australia/Sydney", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(friendlyAbbrevForIana("Australia/Sydney", nh_summer), @"AEST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Australia/Sydney", nh_winter), @"AEDT");
}

static void test_abbrev_no_dst_zones(void) {
    // These never observe DST — should return same value year-round.
    NSDate *summer = dateAt(@"Asia/Tokyo", 2026, 7, 15, 12, 0, 0);
    NSDate *winter = dateAt(@"Asia/Tokyo", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(friendlyAbbrevForIana("Asia/Tokyo", summer), @"JST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Asia/Tokyo", winter), @"JST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Asia/Kolkata", summer), @"IST");
    ASSERT_EQ_STR(friendlyAbbrevForIana("Asia/Hong_Kong", winter), @"HKT");
}

static void test_utc_offset_format(void) {
    NSDate *summer = dateAt(@"America/New_York", 2026, 7, 15, 12, 0, 0);
    NSDate *winter = dateAt(@"America/New_York", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(utcOffsetForIana("America/New_York", summer), @"UTC-4");
    ASSERT_EQ_STR(utcOffsetForIana("America/New_York", winter), @"UTC-5");

    // Kolkata has the famous half-hour offset → must render "UTC+5:30".
    NSDate *any = dateAt(@"Asia/Kolkata", 2026, 4, 24, 12, 0, 0);
    ASSERT_EQ_STR(utcOffsetForIana("Asia/Kolkata", any), @"UTC+5:30");
}

static void test_full_tz_label_composition(void) {
    NSDate *summer = dateAt(@"Europe/London", 2026, 7, 15, 12, 0, 0);
    ASSERT_EQ_STR(fullTzLabelForIana("Europe/London", summer), @"BST UTC+1");
    // GMT intentionally suppressed by fullTzLabelForIana — it's a
    // synonym for UTC, so "UTC+0" alone is less redundant than
    // "GMT UTC+0". Lock that behavior in the test.
    NSDate *winter = dateAt(@"Europe/London", 2026, 1, 15, 12, 0, 0);
    ASSERT_EQ_STR(fullTzLabelForIana("Europe/London", winter), @"UTC+0");
}

int main(void) {
    @autoreleasepool {
        test_nyse_closed_before_open_today();
        test_nyse_open_midsession();
        test_nyse_closed_friday_evening_skips_to_monday();
        test_nyse_saturday_weekend();
        test_tse_lunch_window();
        test_progress_roughly_correct();

        test_abbrev_london_dst_vs_standard();
        test_abbrev_paris_dst_vs_standard();
        test_abbrev_new_york_dst_vs_standard();
        test_abbrev_sydney_inverted();
        test_abbrev_no_dst_zones();
        test_utc_offset_format();
        test_full_tz_label_composition();

        if (failures == 0) {
            fprintf(stderr, "All 13 tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%d test(s) failed.\n", failures);
        return 1;
    }
}
