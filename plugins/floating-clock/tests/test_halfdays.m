// v4 iter-193: extracted from test_holidays.m when that file approached
// the 1000-LoC file-size-guard again (second split — first was iter-176
// extracting holiday tests from test_session.m). Five half-day fixtures
// (iter-188 through iter-192) live here now; iter-193+ half-day campaign
// iters can grow this file without touching test_holidays.
//
// Shares the extern `failures` counter defined in test_session.m via
// test_levers.h. Helper functions (halfdayDateAt + halfdayStateName +
// ASSERT_HDSTATE macro) are local — same pattern as test_holidays.m's
// local helpers.

#import <Foundation/Foundation.h>
#import "../Sources/data/MarketCatalog.h"
#import "../Sources/data/MarketSessionCalculator.h"
#import "../Sources/data/HolidayCalendar.h"
#import "../Sources/data/HalfDayCalendar.h"
#import "test_levers.h"  // extern int failures

static NSDate *halfdayDateAt(NSString *iana, int y, int m, int d, int h, int mm, int ss) {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:iana];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = y; c.month = m; c.day = d;
    c.hour = h; c.minute = mm; c.second = ss;
    return [cal dateFromComponents:c];
}

static const char *halfdayStateName(SessionState s) {
    switch (s) {
        case kSessionOpen:       return "OPEN";
        case kSessionLunch:      return "LUNCH";
        case kSessionClosed:     return "CLOSED";
        case kSessionPreMarket:  return "PRE-MARKET";
        case kSessionAfterHours: return "AFTER-HOURS";
    }
    return "?";
}

#define ASSERT_HDSTATE(mkt, date, expected)                                     \
    do {                                                                        \
        SessionState s; double _p; long _n;                                     \
        computeSessionState((mkt), (date), &s, &_p, &_n);                       \
        if (s != (expected)) {                                                  \
            fprintf(stderr, "FAIL %s: state expected %s got %s\n",              \
                    __func__, halfdayStateName(expected), halfdayStateName(s)); \
            failures++;                                                         \
        }                                                                       \
    } while (0)

void test_halfday_calendar_nyse(void) {
    // v4 iter-188: NYSE 2026 half-day MVP (data-only). Both close 13:00 ET.
    const ClockMarket *nyse = marketForId(@"nyse");
    const ClockMarket *tse  = marketForId(@"tse");

    NSDate *blackFriday = halfdayDateAt(@"America/New_York", 2026, 11, 27, 12, 0, 0);
    NSDate *xmasEve     = halfdayDateAt(@"America/New_York", 2026, 12, 24, 12, 0, 0);

    int h = -1, m = -1;
    if (!FCIsMarketHalfDay(nyse, blackFriday, &h, &m) || h != 13 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: Black Friday expected 13:00 got %d:%02d\n", __func__, h, m);
    }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(nyse, xmasEve, &h, &m) || h != 13 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: Xmas Eve expected 13:00 got %d:%02d\n", __func__, h, m);
    }
    if (!FCIsMarketHalfDay(nyse, blackFriday, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: nil-out-param probe returned NO\n", __func__);
    }
    NSDate *regularFriday = halfdayDateAt(@"America/New_York", 2026, 4, 24, 12, 0, 0);
    if (FCIsMarketHalfDay(nyse, regularFriday, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: Regular Fri wrongly flagged\n", __func__);
    }
    // Full-holiday and half-day are disjoint sets.
    NSDate *thanksgiving = halfdayDateAt(@"America/New_York", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHalfDay(nyse, thanksgiving, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: Thanksgiving wrongly flagged half-day\n", __func__);
    }
    if (FCIsMarketHalfDay(tse, xmasEve, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: TSE wrongly flagged (no data)\n", __func__);
    }
    if (FCIsMarketHalfDay(NULL, blackFriday, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: nil mkt should return NO\n", __func__);
    }
    if (FCIsMarketHalfDay(nyse, nil, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: nil date should return NO\n", __func__);
    }
}

void test_halfday_calendar_lse_and_target2(void) {
    // v4 iter-190: LSE (12:30) + XETRA/Euronext (14:00) Dec 24 + Dec 31.
    const ClockMarket *lse      = marketForId(@"lse");
    const ClockMarket *xetra    = marketForId(@"xetra");
    const ClockMarket *euronext = marketForId(@"euronext");

    NSDate *lseXmasEve = halfdayDateAt(@"Europe/London", 2026, 12, 24, 12, 0, 0);
    NSDate *lseNYE     = halfdayDateAt(@"Europe/London", 2026, 12, 31, 12, 0, 0);
    int h = -1, m = -1;
    if (!FCIsMarketHalfDay(lse, lseXmasEve, &h, &m) || h != 12 || m != 30) {
        failures++; fprintf(stderr, "FAIL %s: LSE Xmas Eve expected 12:30 got %d:%02d\n", __func__, h, m);
    }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(lse, lseNYE, &h, &m) || h != 12 || m != 30) {
        failures++; fprintf(stderr, "FAIL %s: LSE NYE expected 12:30 got %d:%02d\n", __func__, h, m);
    }

    NSDate *xetraXmasEve = halfdayDateAt(@"Europe/Berlin", 2026, 12, 24, 12, 0, 0);
    NSDate *euronextNYE  = halfdayDateAt(@"Europe/Paris",  2026, 12, 31, 12, 0, 0);
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(xetra, xetraXmasEve, &h, &m) || h != 14 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: XETRA Xmas Eve expected 14:00 got %d:%02d\n", __func__, h, m);
    }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(euronext, euronextNYE, &h, &m) || h != 14 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: Euronext NYE expected 14:00 got %d:%02d\n", __func__, h, m);
    }

    // Dedup sanity: TARGET2 shared array must flag both dates for both markets.
    if (!FCIsMarketHalfDay(xetra,    euronextNYE,  NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: XETRA must flag Dec 31\n", __func__); }
    if (!FCIsMarketHalfDay(euronext, xetraXmasEve, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: Euronext must flag Dec 24\n", __func__); }

    // LSE Dec 24 half-day NOT in full-holiday set (disjoint).
    if (FCIsMarketHoliday(lse, lseXmasEve)) {
        failures++; fprintf(stderr, "FAIL %s: LSE Dec 24 is half-day NOT full holiday\n", __func__);
    }

    NSDate *regularFri = halfdayDateAt(@"Europe/London", 2026, 7, 10, 12, 0, 0);
    if (FCIsMarketHalfDay(lse,      regularFri, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: LSE regular Fri flagged\n", __func__); }
    if (FCIsMarketHalfDay(xetra,    regularFri, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: XETRA regular Fri flagged\n", __func__); }
    if (FCIsMarketHalfDay(euronext, regularFri, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: Euronext regular Fri flagged\n", __func__); }
}

void test_halfday_calendar_hkex_and_tsx(void) {
    // v4 iter-191: HKEX (lunch-bearing, 12:00 HKT = lunch-start close,
    // stress-tests iter-189 hasLunch=NO override) + TSX (Dec 24 only).
    const ClockMarket *hkex = marketForId(@"hkex");
    const ClockMarket *tsx  = marketForId(@"tsx");

    NSDate *lnyEve  = halfdayDateAt(@"Asia/Hong_Kong", 2026,  2, 16, 10,  0, 0);
    NSDate *xmasEve = halfdayDateAt(@"Asia/Hong_Kong", 2026, 12, 24, 10,  0, 0);
    NSDate *nye     = halfdayDateAt(@"Asia/Hong_Kong", 2026, 12, 31, 10,  0, 0);
    int h = -1, m = -1;
    if (!FCIsMarketHalfDay(hkex, lnyEve,  &h, &m) || h != 12 || m != 0) { failures++; fprintf(stderr, "FAIL %s: HKEX LNY Eve expected 12:00 got %d:%02d\n", __func__, h, m); }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(hkex, xmasEve, &h, &m) || h != 12 || m != 0) { failures++; fprintf(stderr, "FAIL %s: HKEX Xmas Eve expected 12:00 got %d:%02d\n", __func__, h, m); }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(hkex, nye,     &h, &m) || h != 12 || m != 0) { failures++; fprintf(stderr, "FAIL %s: HKEX NYE expected 12:00 got %d:%02d\n", __func__, h, m); }

    // Integration lock — 12:30 on half-day must be CLOSED not LUNCH.
    NSDate *xmasEveLunch = halfdayDateAt(@"Asia/Hong_Kong", 2026, 12, 24, 12, 30, 0);
    SessionState s; double _p; long _n;
    computeSessionState(hkex, xmasEveLunch, &s, &_p, &_n);
    if (s != kSessionClosed) {
        failures++;
        fprintf(stderr, "FAIL %s: HKEX 12:30 Xmas Eve expected CLOSED got %s (iter-189 hasLunch=NO override broken)\n",
                __func__, halfdayStateName(s));
    }
    ASSERT_HDSTATE(hkex, xmasEve, kSessionOpen);

    NSDate *tsxXmasEve = halfdayDateAt(@"America/Toronto", 2026, 12, 24, 10, 0, 0);
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(tsx, tsxXmasEve, &h, &m) || h != 13 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: TSX Xmas Eve expected 13:00 got %d:%02d\n", __func__, h, m);
    }
    NSDate *tsxNYE = halfdayDateAt(@"America/Toronto", 2026, 12, 31, 10, 0, 0);
    if (FCIsMarketHalfDay(tsx, tsxNYE, NULL, NULL)) {
        failures++; fprintf(stderr, "FAIL %s: TSX Dec 31 wrongly flagged half-day\n", __func__);
    }
}

void test_halfday_calendar_jse_and_asx(void) {
    // v4 iter-192: JSE + ASX Dec 24 half-days fill Africa + Oceania.
    const ClockMarket *jse = marketForId(@"jse");
    const ClockMarket *asx = marketForId(@"asx");
    NSDate *jseXmasEve = halfdayDateAt(@"Africa/Johannesburg", 2026, 12, 24, 10, 0, 0);
    NSDate *asxXmasEve = halfdayDateAt(@"Australia/Sydney",    2026, 12, 24, 10, 0, 0);
    int h = -1, m = -1;
    if (!FCIsMarketHalfDay(jse, jseXmasEve, &h, &m) || h != 12 || m != 0) {
        failures++; fprintf(stderr, "FAIL %s: JSE Xmas Eve expected 12:00 got %d:%02d\n", __func__, h, m);
    }
    h = -1; m = -1;
    if (!FCIsMarketHalfDay(asx, asxXmasEve, &h, &m) || h != 14 || m != 10) {
        failures++; fprintf(stderr, "FAIL %s: ASX Xmas Eve expected 14:10 got %d:%02d\n", __func__, h, m);
    }
    NSDate *jseNYE = halfdayDateAt(@"Africa/Johannesburg", 2026, 12, 31, 10, 0, 0);
    NSDate *asxNYE = halfdayDateAt(@"Australia/Sydney",    2026, 12, 31, 10, 0, 0);
    if (FCIsMarketHalfDay(jse, jseNYE, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: JSE Dec 31 wrongly flagged\n", __func__); }
    if (FCIsMarketHalfDay(asx, asxNYE, NULL, NULL)) { failures++; fprintf(stderr, "FAIL %s: ASX Dec 31 wrongly flagged\n", __func__); }
}

void test_nyse_halfday_state_closed(void) {
    // v4 iter-189: integration lock. 14:00 on NYSE half-days must be
    // CLOSED (regular NYSE close is 16:00 — without iter-189 wiring
    // this would be OPEN).
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *bfMorning     = halfdayDateAt(@"America/New_York", 2026, 11, 27, 10,  0, 0);
    NSDate *bfAfterClose  = halfdayDateAt(@"America/New_York", 2026, 11, 27, 14,  0, 0);
    ASSERT_HDSTATE(nyse, bfMorning,    kSessionOpen);
    ASSERT_HDSTATE(nyse, bfAfterClose, kSessionClosed);

    NSDate *xeMorning    = halfdayDateAt(@"America/New_York", 2026, 12, 24, 10,  0, 0);
    NSDate *xeAfterClose = halfdayDateAt(@"America/New_York", 2026, 12, 24, 14,  0, 0);
    ASSERT_HDSTATE(nyse, xeMorning,    kSessionOpen);
    ASSERT_HDSTATE(nyse, xeAfterClose, kSessionClosed);

    NSDate *regularFri14 = halfdayDateAt(@"America/New_York", 2026, 4, 24, 14, 0, 0);
    ASSERT_HDSTATE(nyse, regularFri14, kSessionOpen);
}
