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
#import "test_helpers.h" // shared dateAt / sessionStateName / ASSERT_SESSION_STATE

void test_holiday_calendar_nyse(void) {
    // v4 iter-173: pure-data lookup test for FCIsMarketHoliday.
    const ClockMarket *nyse = marketForId(@"nyse");
    const ClockMarket *tse  = marketForId(@"tse");

    NSDate *thanksgiving = dateAt(@"America/New_York", 2026, 11, 26, 12, 0, 0);
    NSDate *christmas    = dateAt(@"America/New_York", 2026, 12, 25, 12, 0, 0);
    NSDate *newYears     = dateAt(@"America/New_York", 2026,  1,  1, 12, 0, 0);
    if (!FCIsMarketHoliday(nyse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: Thanksgiving not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(nyse, christmas)) {
        failures++; fprintf(stderr, "FAIL %s: Christmas not flagged\n", __func__);
    }
    if (!FCIsMarketHoliday(nyse, newYears)) {
        failures++; fprintf(stderr, "FAIL %s: New Year's Day not flagged\n", __func__);
    }

    NSDate *regularFriday = dateAt(@"America/New_York", 2026, 4, 24, 12, 0, 0);
    if (FCIsMarketHoliday(nyse, regularFriday)) {
        failures++; fprintf(stderr, "FAIL %s: Fri 2026-04-24 wrongly flagged\n", __func__);
    }

    // Cross-market: NYSE must not flag TSE-only Jan 2 bank holiday.
    NSDate *tseJan2 = dateAt(@"America/New_York", 2026, 1, 2, 12, 0, 0);
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

    NSDate *easterMonday = dateAt(@"Europe/London", 2026, 4, 6, 12, 0, 0);
    NSDate *springBank   = dateAt(@"Europe/London", 2026, 5, 25, 12, 0, 0);
    NSDate *summerBank   = dateAt(@"Europe/London", 2026, 8, 31, 12, 0, 0);
    NSDate *boxingObs    = dateAt(@"Europe/London", 2026, 12, 28, 12, 0, 0);
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

    NSDate *thanksgiving = dateAt(@"Europe/London", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(lse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: LSE wrongly flagged Thanksgiving\n", __func__);
    }
    if (FCIsMarketHoliday(nyse, easterMonday)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Easter Monday\n", __func__);
    }

    NSDate *regularWed = dateAt(@"Europe/London", 2026, 3, 11, 12, 0, 0);
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

    NSDate *bankJan2      = dateAt(@"Asia/Tokyo", 2026,  1,  2, 12, 0, 0);
    NSDate *comingOfAge   = dateAt(@"Asia/Tokyo", 2026,  1, 12, 12, 0, 0);
    NSDate *emperorBday   = dateAt(@"Asia/Tokyo", 2026,  2, 23, 12, 0, 0);
    NSDate *showaDay      = dateAt(@"Asia/Tokyo", 2026,  4, 29, 12, 0, 0);
    NSDate *goldenWeekSub = dateAt(@"Asia/Tokyo", 2026,  5,  6, 12, 0, 0);
    NSDate *marineDay     = dateAt(@"Asia/Tokyo", 2026,  7, 20, 12, 0, 0);
    NSDate *yearEnd       = dateAt(@"Asia/Tokyo", 2026, 12, 31, 12, 0, 0);
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
    NSDate *thanksgiving = dateAt(@"Asia/Tokyo", 2026, 11, 26, 12, 0, 0);
    NSDate *juneteenth   = dateAt(@"Asia/Tokyo", 2026,  6, 19, 12, 0, 0);
    if (FCIsMarketHoliday(tse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: TSE wrongly flagged Thanksgiving\n", __func__);
    }
    if (FCIsMarketHoliday(tse, juneteenth)) {
        failures++; fprintf(stderr, "FAIL %s: TSE wrongly flagged Juneteenth\n", __func__);
    }

    NSDate *regularWed = dateAt(@"Asia/Tokyo", 2026, 6, 10, 12, 0, 0);
    if (FCIsMarketHoliday(tse, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-06-10 wrongly flagged on TSE\n", __func__);
    }
}

void test_holiday_calendar_hkex(void) {
    // v4 iter-178: HKEX 2026 non-trading days. First fixture covering
    // lunar-calendar holidays whose Gregorian dates shift year-by-year
    // (Lunar New Year 3-day cluster, Buddha's Birthday, Dragon Boat,
    // Mid-Autumn, Chung Yeung). Also covers dual observations: Good
    // Friday (Western) + Lunar New Year Day 1/2/3 within two months.
    const ClockMarket *hkex = marketForId(@"hkex");
    const ClockMarket *nyse = marketForId(@"nyse");

    // Lunar New Year 3-day cluster — Feb 17/18/19 Tue/Wed/Thu 2026.
    NSDate *lny1 = dateAt(@"Asia/Hong_Kong", 2026,  2, 17, 12, 0, 0);
    NSDate *lny2 = dateAt(@"Asia/Hong_Kong", 2026,  2, 18, 12, 0, 0);
    NSDate *lny3 = dateAt(@"Asia/Hong_Kong", 2026,  2, 19, 12, 0, 0);
    if (!FCIsMarketHoliday(hkex, lny1)) { failures++; fprintf(stderr, "FAIL %s: LNY Day 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, lny2)) { failures++; fprintf(stderr, "FAIL %s: LNY Day 2 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, lny3)) { failures++; fprintf(stderr, "FAIL %s: LNY Day 3 not flagged\n", __func__); }

    // Lunar-calendar non-LNY holidays.
    NSDate *buddha      = dateAt(@"Asia/Hong_Kong", 2026,  5, 25, 12, 0, 0);
    NSDate *dragonBoat  = dateAt(@"Asia/Hong_Kong", 2026,  6, 19, 12, 0, 0);
    NSDate *midAutumn   = dateAt(@"Asia/Hong_Kong", 2026,  9, 25, 12, 0, 0);
    NSDate *chungYeung  = dateAt(@"Asia/Hong_Kong", 2026, 10, 19, 12, 0, 0);
    if (!FCIsMarketHoliday(hkex, buddha))     { failures++; fprintf(stderr, "FAIL %s: Buddha's Birthday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, dragonBoat)) { failures++; fprintf(stderr, "FAIL %s: Dragon Boat not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, midAutumn))  { failures++; fprintf(stderr, "FAIL %s: Mid-Autumn not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, chungYeung)) { failures++; fprintf(stderr, "FAIL %s: Chung Yeung not flagged\n", __func__); }

    // Civic holidays (National Day + SAR Establishment) and the
    // Easter Mon + Ching Ming coincidence.
    NSDate *sarDay      = dateAt(@"Asia/Hong_Kong", 2026,  7,  1, 12, 0, 0);
    NSDate *nationalDay = dateAt(@"Asia/Hong_Kong", 2026, 10,  1, 12, 0, 0);
    NSDate *easterMon   = dateAt(@"Asia/Hong_Kong", 2026,  4,  6, 12, 0, 0);
    if (!FCIsMarketHoliday(hkex, sarDay))      { failures++; fprintf(stderr, "FAIL %s: HKSAR Establishment Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, nationalDay)) { failures++; fprintf(stderr, "FAIL %s: National Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(hkex, easterMon))   { failures++; fprintf(stderr, "FAIL %s: Easter Mon/Ching Ming not flagged\n", __func__); }

    // Cross-market negatives: NYSE must NOT flag HKEX-only holidays
    // whose HK-noon doesn't overlap a NY holiday after TZ conversion.
    // Avoided pitfalls:
    //   - LNY Day 1 (Feb 17 HK) = Feb 16 NY = Presidents' Day → shared
    //   - Dragon Boat (Jun 19 HK) = Jun 19 NY = Juneteenth → shared
    // Use dates that land on ordinary NY weekdays after conversion.
    if (FCIsMarketHoliday(nyse, lny2))       { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged LNY Day 2\n", __func__); }
    if (FCIsMarketHoliday(nyse, lny3))       { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged LNY Day 3\n", __func__); }
    if (FCIsMarketHoliday(nyse, chungYeung)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Chung Yeung\n", __func__); }
    if (FCIsMarketHoliday(nyse, midAutumn))  { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Mid-Autumn\n", __func__); }

    // HKEX must NOT flag NYSE-only holidays. Same TZ-conversion pitfall
    // check: Thanksgiving in HK-noon lands on Thanksgiving-in-NY-night,
    // which is still a NY holiday — but HKEX's own registry has no
    // Thanksgiving, so it returns NO as expected (cross-market routing
    // rather than TZ logic).
    NSDate *thanksgiving = dateAt(@"Asia/Hong_Kong", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(hkex, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: HKEX wrongly flagged Thanksgiving\n", __func__);
    }
    // Note: Jun 19 2026 happens to be BOTH Juneteenth (US) and Dragon
    // Boat Festival (HK) — a genuine multi-market holiday coincidence.
    // Both markets correctly flag it; no negative test applicable.

    // Regular HKEX trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Asia/Hong_Kong", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(hkex, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on HKEX\n", __func__);
    }
}

void test_holiday_calendar_target2(void) {
    // v4 iter-179: XETRA + Euronext both reference the same shared
    // kTARGET2_2026Holidays array in the registry. This test locks down
    // that (a) each market flags the shared TARGET2 closures, (b) both
    // markets reject holidays that belong to other exchanges (NYSE
    // Thanksgiving, HKEX Dragon Boat, TSE Golden Week), (c) the data
    // dedup doesn't cause one market's entry to accidentally alias the
    // other — both return identical results for a given date, confirmed
    // by asserting them against the same fixtures in parallel.
    const ClockMarket *xetra    = marketForId(@"xetra");
    const ClockMarket *euronext = marketForId(@"euronext");

    NSDate *newYears     = dateAt(@"Europe/Berlin", 2026,  1,  1, 12, 0, 0);
    NSDate *goodFriday   = dateAt(@"Europe/Berlin", 2026,  4,  3, 12, 0, 0);
    NSDate *easterMonday = dateAt(@"Europe/Berlin", 2026,  4,  6, 12, 0, 0);
    NSDate *labourDay    = dateAt(@"Europe/Berlin", 2026,  5,  1, 12, 0, 0);
    NSDate *christmas    = dateAt(@"Europe/Berlin", 2026, 12, 25, 12, 0, 0);

    // All 5 TARGET2 dates must be flagged for both markets.
    if (!FCIsMarketHoliday(xetra,    newYears))     { failures++; fprintf(stderr, "FAIL %s: XETRA Jan 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(euronext, newYears))     { failures++; fprintf(stderr, "FAIL %s: Euronext Jan 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(xetra,    goodFriday))   { failures++; fprintf(stderr, "FAIL %s: XETRA Good Friday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(euronext, goodFriday))   { failures++; fprintf(stderr, "FAIL %s: Euronext Good Friday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(xetra,    easterMonday)) { failures++; fprintf(stderr, "FAIL %s: XETRA Easter Mon not flagged\n", __func__); }
    if (!FCIsMarketHoliday(euronext, easterMonday)) { failures++; fprintf(stderr, "FAIL %s: Euronext Easter Mon not flagged\n", __func__); }
    if (!FCIsMarketHoliday(xetra,    labourDay))    { failures++; fprintf(stderr, "FAIL %s: XETRA Labour Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(euronext, labourDay))    { failures++; fprintf(stderr, "FAIL %s: Euronext Labour Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(xetra,    christmas))    { failures++; fprintf(stderr, "FAIL %s: XETRA Christmas not flagged\n", __func__); }
    if (!FCIsMarketHoliday(euronext, christmas))    { failures++; fprintf(stderr, "FAIL %s: Euronext Christmas not flagged\n", __func__); }

    // Dec 26 Sat 2026 — Boxing Day (weekend, not in TARGET2 array).
    // FCIsMarketHoliday should return NO for both (data array doesn't
    // have it; isWeekend branch in computeSessionState handles it).
    NSDate *dec26Sat = dateAt(@"Europe/Berlin", 2026, 12, 26, 12, 0, 0);
    if (FCIsMarketHoliday(xetra, dec26Sat)) {
        failures++; fprintf(stderr, "FAIL %s: Dec 26 wrongly in XETRA array (handled by weekend)\n", __func__);
    }

    // Cross-market negatives: TARGET2 markets must NOT flag holidays
    // from other calendars (NYSE Thanksgiving, TSE Shogatsu, HKEX LNY).
    NSDate *thanksgiving = dateAt(@"Europe/Berlin", 2026, 11, 26, 12, 0, 0);
    NSDate *tseShogatsu  = dateAt(@"Europe/Berlin", 2026,  1,  2, 12, 0, 0);
    NSDate *hkexLNY      = dateAt(@"Europe/Berlin", 2026,  2, 17, 12, 0, 0);
    if (FCIsMarketHoliday(xetra,    thanksgiving)) { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged Thanksgiving\n", __func__); }
    if (FCIsMarketHoliday(euronext, thanksgiving)) { failures++; fprintf(stderr, "FAIL %s: Euronext wrongly flagged Thanksgiving\n", __func__); }
    if (FCIsMarketHoliday(xetra,    tseShogatsu))  { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged TSE Shogatsu\n", __func__); }
    if (FCIsMarketHoliday(xetra,    hkexLNY))      { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged HKEX LNY\n", __func__); }

    // Regular trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Europe/Berlin", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(xetra,    regularWed)) { failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on XETRA\n", __func__); }
    if (FCIsMarketHoliday(euronext, regularWed)) { failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on Euronext\n", __func__); }
}

void test_holiday_calendar_asx(void) {
    // v4 iter-180: ASX 2026 non-trading days. First Oceania coverage.
    // Distinctive: Easter Tuesday (Apr 7) — ASX is one of the few
    // major exchanges that closes a 4-day Easter long weekend. Also
    // locks Australia Day (Jan 26) + King's Birthday (2nd Mon of Jun,
    // Jun 8 2026).
    const ClockMarket *asx  = marketForId(@"asx");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *australiaDay  = dateAt(@"Australia/Sydney", 2026,  1, 26, 12, 0, 0);
    NSDate *easterTuesday = dateAt(@"Australia/Sydney", 2026,  4,  7, 12, 0, 0);
    NSDate *kingsBday     = dateAt(@"Australia/Sydney", 2026,  6,  8, 12, 0, 0);
    NSDate *boxingObs     = dateAt(@"Australia/Sydney", 2026, 12, 28, 12, 0, 0);
    if (!FCIsMarketHoliday(asx, australiaDay))   { failures++; fprintf(stderr, "FAIL %s: Australia Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(asx, easterTuesday))  { failures++; fprintf(stderr, "FAIL %s: Easter Tuesday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(asx, kingsBday))      { failures++; fprintf(stderr, "FAIL %s: King's Birthday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(asx, boxingObs))      { failures++; fprintf(stderr, "FAIL %s: Boxing Day (observed Dec 28) not flagged\n", __func__); }

    // Cross-market negatives: NYSE must NOT flag ASX-only holidays.
    if (FCIsMarketHoliday(nyse, australiaDay))   { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Australia Day\n", __func__); }
    if (FCIsMarketHoliday(nyse, easterTuesday))  { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Easter Tuesday\n", __func__); }
    if (FCIsMarketHoliday(nyse, kingsBday))      { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged King's Birthday\n", __func__); }

    // ASX does NOT flag NYSE-only holidays (Thanksgiving, Juneteenth).
    NSDate *thanksgiving = dateAt(@"Australia/Sydney", 2026, 11, 26, 12, 0, 0);
    NSDate *juneteenth   = dateAt(@"Australia/Sydney", 2026,  6, 19, 12, 0, 0);
    if (FCIsMarketHoliday(asx, thanksgiving)) { failures++; fprintf(stderr, "FAIL %s: ASX wrongly flagged Thanksgiving\n", __func__); }
    if (FCIsMarketHoliday(asx, juneteenth))   { failures++; fprintf(stderr, "FAIL %s: ASX wrongly flagged Juneteenth\n", __func__); }

    // ANZAC Day Apr 25 2026 is Saturday — ASX does NOT observe a Mon
    // substitute; weekend branch handles the closure. So Apr 27 Mon
    // must NOT be flagged (regular trading).
    NSDate *anzacMondayAfter = dateAt(@"Australia/Sydney", 2026, 4, 27, 12, 0, 0);
    if (FCIsMarketHoliday(asx, anzacMondayAfter)) {
        failures++; fprintf(stderr, "FAIL %s: ASX wrongly flagged Apr 27 Mon (no ANZAC substitute)\n", __func__);
    }

    // Regular ASX trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Australia/Sydney", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(asx, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on ASX\n", __func__);
    }
}

void test_holiday_calendar_tsx(void) {
    // v4 iter-181: TSX 2026 non-trading days. Tests Canadian-specific
    // calendar: Family Day (Ontario), Victoria Day, Canada Day, Civic
    // Holiday (Aug), Canadian Thanksgiving (Oct not Nov). Also locks
    // that TSX does NOT close Easter Mon — a common mistake (TSX
    // follows US-style for Easter; closes Good Fri only).
    const ClockMarket *tsx  = marketForId(@"tsx");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *familyDay       = dateAt(@"America/Toronto", 2026,  2, 16, 12, 0, 0);
    NSDate *victoriaDay     = dateAt(@"America/Toronto", 2026,  5, 18, 12, 0, 0);
    NSDate *canadaDay       = dateAt(@"America/Toronto", 2026,  7,  1, 12, 0, 0);
    NSDate *civicHoliday    = dateAt(@"America/Toronto", 2026,  8,  3, 12, 0, 0);
    NSDate *canadaThanks    = dateAt(@"America/Toronto", 2026, 10, 12, 12, 0, 0);
    NSDate *boxingObs       = dateAt(@"America/Toronto", 2026, 12, 28, 12, 0, 0);
    if (!FCIsMarketHoliday(tsx, familyDay))    { failures++; fprintf(stderr, "FAIL %s: Family Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(tsx, victoriaDay))  { failures++; fprintf(stderr, "FAIL %s: Victoria Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(tsx, canadaDay))    { failures++; fprintf(stderr, "FAIL %s: Canada Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(tsx, civicHoliday)) { failures++; fprintf(stderr, "FAIL %s: Civic Holiday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(tsx, canadaThanks)) { failures++; fprintf(stderr, "FAIL %s: Canadian Thanksgiving not flagged\n", __func__); }
    if (!FCIsMarketHoliday(tsx, boxingObs))    { failures++; fprintf(stderr, "FAIL %s: Boxing Day (observed) not flagged\n", __func__); }

    // TSX does NOT close Easter Monday (trades).
    NSDate *easterMonday = dateAt(@"America/Toronto", 2026, 4, 6, 12, 0, 0);
    if (FCIsMarketHoliday(tsx, easterMonday)) {
        failures++; fprintf(stderr, "FAIL %s: TSX wrongly flagged Easter Monday (TSX trades Easter Mon)\n", __func__);
    }

    // Cross-market: NYSE must NOT flag TSX-only Canadian Thanksgiving
    // (NYSE Thanksgiving is Nov, not Oct).
    if (FCIsMarketHoliday(nyse, canadaThanks)) {
        failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Canadian Thanksgiving\n", __func__);
    }
    // NYSE must NOT flag Canada Day or Civic Holiday.
    if (FCIsMarketHoliday(nyse, canadaDay))    { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Canada Day\n", __func__); }
    if (FCIsMarketHoliday(nyse, civicHoliday)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Civic Holiday\n", __func__); }

    // TSX does NOT flag NYSE Thanksgiving (Nov 26).
    NSDate *usThanks = dateAt(@"America/Toronto", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(tsx, usThanks)) {
        failures++; fprintf(stderr, "FAIL %s: TSX wrongly flagged US Thanksgiving (TSX trades Nov 26)\n", __func__);
    }

    // Regular TSX trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"America/Toronto", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(tsx, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on TSX\n", __func__);
    }
}

void test_holiday_calendar_six(void) {
    // v4 iter-182: SIX Swiss Exchange 2026. Distinctive dates:
    // Berchtold's Day Jan 2 (Swiss-only), Ascension Day May 14 +
    // Whit Monday May 25 (Christian Easter-based holidays other
    // markets don't observe), Dec 24 + Dec 31 as FULL closures
    // (most markets treat these as half-day sessions).
    const ClockMarket *six    = marketForId(@"six");
    const ClockMarket *xetra  = marketForId(@"xetra");

    NSDate *berchtold    = dateAt(@"Europe/Zurich", 2026,  1,  2, 12, 0, 0);
    NSDate *ascension    = dateAt(@"Europe/Zurich", 2026,  5, 14, 12, 0, 0);
    NSDate *whitMonday   = dateAt(@"Europe/Zurich", 2026,  5, 25, 12, 0, 0);
    NSDate *xmasEve      = dateAt(@"Europe/Zurich", 2026, 12, 24, 12, 0, 0);
    NSDate *nyEve        = dateAt(@"Europe/Zurich", 2026, 12, 31, 12, 0, 0);
    if (!FCIsMarketHoliday(six, berchtold))  { failures++; fprintf(stderr, "FAIL %s: Berchtold's Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(six, ascension))  { failures++; fprintf(stderr, "FAIL %s: Ascension Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(six, whitMonday)) { failures++; fprintf(stderr, "FAIL %s: Whit Monday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(six, xmasEve))    { failures++; fprintf(stderr, "FAIL %s: Xmas Eve full closure not flagged\n", __func__); }
    if (!FCIsMarketHoliday(six, nyEve))      { failures++; fprintf(stderr, "FAIL %s: NYE full closure not flagged\n", __func__); }

    // Cross-market: XETRA (TARGET2) does NOT have Berchtold/Ascension/
    // Whit Mon/Xmas Eve/NYE — these are SIX-distinctive.
    if (FCIsMarketHoliday(xetra, berchtold))  { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged Berchtold\n", __func__); }
    if (FCIsMarketHoliday(xetra, ascension))  { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged Ascension\n", __func__); }
    if (FCIsMarketHoliday(xetra, whitMonday)) { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged Whit Mon\n", __func__); }
    if (FCIsMarketHoliday(xetra, xmasEve))    { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged Xmas Eve (XETRA trades — half day)\n", __func__); }
    if (FCIsMarketHoliday(xetra, nyEve))      { failures++; fprintf(stderr, "FAIL %s: XETRA wrongly flagged NYE (XETRA trades — half day)\n", __func__); }

    // SIX must NOT flag NYSE-only holidays.
    NSDate *thanksgiving = dateAt(@"Europe/Zurich", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(six, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: SIX wrongly flagged Thanksgiving\n", __func__);
    }

    // Swiss National Day Aug 1 2026 is Saturday — SIX has no substitute,
    // so Mon Aug 3 must NOT be flagged (weekend handles Aug 1 itself).
    NSDate *nationalDayAfterMonday = dateAt(@"Europe/Zurich", 2026, 8, 3, 12, 0, 0);
    if (FCIsMarketHoliday(six, nationalDayAfterMonday)) {
        failures++; fprintf(stderr, "FAIL %s: SIX wrongly flagged Aug 3 (no National Day substitute)\n", __func__);
    }

    // Regular SIX trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Europe/Zurich", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(six, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on SIX\n", __func__);
    }
}

void test_holiday_calendar_sse(void) {
    // v4 iter-183: SSE 2026 non-trading days. First calendar with two
    // 7-day Golden Week clusters (Spring Festival + National Day).
    // Interesting overlaps with HKEX: Dragon Boat (Jun 19) and
    // Mid-Autumn (Sep 25) fall on exactly the same Gregorian dates
    // — both markets correctly flag them.
    const ClockMarket *sse  = marketForId(@"sse");
    const ClockMarket *hkex = marketForId(@"hkex");
    const ClockMarket *nyse = marketForId(@"nyse");

    // Spring Festival Golden Week — verify all 5 weekday closures.
    NSDate *sfDay1 = dateAt(@"Asia/Shanghai", 2026, 2, 17, 12, 0, 0);
    NSDate *sfDay5 = dateAt(@"Asia/Shanghai", 2026, 2, 23, 12, 0, 0);
    if (!FCIsMarketHoliday(sse, sfDay1)) { failures++; fprintf(stderr, "FAIL %s: Spring Festival Day 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(sse, sfDay5)) { failures++; fprintf(stderr, "FAIL %s: Spring Festival Day 5 (Feb 23 Mon) not flagged\n", __func__); }

    // National Day Golden Week.
    NSDate *ndDay1 = dateAt(@"Asia/Shanghai", 2026, 10, 1, 12, 0, 0);
    NSDate *ndDay5 = dateAt(@"Asia/Shanghai", 2026, 10, 7, 12, 0, 0);
    if (!FCIsMarketHoliday(sse, ndDay1)) { failures++; fprintf(stderr, "FAIL %s: National Day Day 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(sse, ndDay5)) { failures++; fprintf(stderr, "FAIL %s: National Day Day 5 (Oct 7 Wed) not flagged\n", __func__); }

    // Qingming + Mid-Autumn + Dragon Boat + Labour Day.
    NSDate *qingming   = dateAt(@"Asia/Shanghai", 2026,  4,  6, 12, 0, 0);
    NSDate *labour     = dateAt(@"Asia/Shanghai", 2026,  5,  1, 12, 0, 0);
    NSDate *dragonBoat = dateAt(@"Asia/Shanghai", 2026,  6, 19, 12, 0, 0);
    NSDate *midAutumn  = dateAt(@"Asia/Shanghai", 2026,  9, 25, 12, 0, 0);
    if (!FCIsMarketHoliday(sse, qingming))   { failures++; fprintf(stderr, "FAIL %s: Qingming not flagged\n", __func__); }
    if (!FCIsMarketHoliday(sse, labour))     { failures++; fprintf(stderr, "FAIL %s: Labour Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(sse, dragonBoat)) { failures++; fprintf(stderr, "FAIL %s: Dragon Boat not flagged\n", __func__); }
    if (!FCIsMarketHoliday(sse, midAutumn))  { failures++; fprintf(stderr, "FAIL %s: Mid-Autumn not flagged\n", __func__); }

    // HKEX shares Dragon Boat + Mid-Autumn dates (same lunar calendar).
    if (!FCIsMarketHoliday(hkex, dragonBoat)) { failures++; fprintf(stderr, "FAIL %s: HKEX should also flag Dragon Boat\n", __func__); }
    if (!FCIsMarketHoliday(hkex, midAutumn))  { failures++; fprintf(stderr, "FAIL %s: HKEX should also flag Mid-Autumn\n", __func__); }

    // Cross-market: SSE must NOT flag NYSE-only holidays.
    NSDate *thanksgiving = dateAt(@"Asia/Shanghai", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(sse, thanksgiving)) { failures++; fprintf(stderr, "FAIL %s: SSE wrongly flagged Thanksgiving\n", __func__); }

    // NYSE must NOT flag SSE-only National Day Oct 5 (doesn't coincide
    // w/ any US holiday after TZ adjustment — Oct 5 Shanghai noon =
    // Oct 5 01:00 NY EDT, still a Mon non-holiday).
    if (FCIsMarketHoliday(nyse, ndDay5)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged SSE Oct 7\n", __func__); }

    // Regular SSE trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Asia/Shanghai", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(sse, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on SSE\n", __func__);
    }
}

void test_holiday_calendar_krx(void) {
    // v4 iter-184: KRX 2026. Covers Seollal + Chuseok multi-day
    // clusters, Korean substitute-holiday mechanics (weekend holidays
    // shift to next weekday), and the triple-market Sep 25 Mid-Autumn
    // / Chuseok / Mid-Autumn coincidence across KRX, HKEX, SSE.
    const ClockMarket *krx  = marketForId(@"krx");
    const ClockMarket *hkex = marketForId(@"hkex");
    const ClockMarket *sse  = marketForId(@"sse");

    // Seollal cluster.
    NSDate *seollalEve  = dateAt(@"Asia/Seoul", 2026, 2, 16, 12, 0, 0);
    NSDate *seollalDay1 = dateAt(@"Asia/Seoul", 2026, 2, 17, 12, 0, 0);
    NSDate *seollalDay2 = dateAt(@"Asia/Seoul", 2026, 2, 18, 12, 0, 0);
    if (!FCIsMarketHoliday(krx, seollalEve))  { failures++; fprintf(stderr, "FAIL %s: Seollal Eve not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, seollalDay1)) { failures++; fprintf(stderr, "FAIL %s: Seollal Day 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, seollalDay2)) { failures++; fprintf(stderr, "FAIL %s: Seollal Day 2 not flagged\n", __func__); }

    // Chuseok cluster (Sep 24-28).
    NSDate *chuseok1 = dateAt(@"Asia/Seoul", 2026, 9, 24, 12, 0, 0);
    NSDate *chuseok2 = dateAt(@"Asia/Seoul", 2026, 9, 25, 12, 0, 0);
    NSDate *chuseokSub = dateAt(@"Asia/Seoul", 2026, 9, 28, 12, 0, 0);
    if (!FCIsMarketHoliday(krx, chuseok1))    { failures++; fprintf(stderr, "FAIL %s: Chuseok Day 1 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, chuseok2))    { failures++; fprintf(stderr, "FAIL %s: Chuseok Day 2 not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, chuseokSub))  { failures++; fprintf(stderr, "FAIL %s: Chuseok Sep 28 substitute not flagged\n", __func__); }

    // Korean-distinctive single-day holidays.
    NSDate *marMonSub = dateAt(@"Asia/Seoul", 2026,  3,  2, 12, 0, 0);
    NSDate *childrens = dateAt(@"Asia/Seoul", 2026,  5,  5, 12, 0, 0);
    NSDate *libSub    = dateAt(@"Asia/Seoul", 2026,  8, 17, 12, 0, 0);
    NSDate *foundSub  = dateAt(@"Asia/Seoul", 2026, 10,  5, 12, 0, 0);
    NSDate *hangeul   = dateAt(@"Asia/Seoul", 2026, 10,  9, 12, 0, 0);
    NSDate *yearEnd   = dateAt(@"Asia/Seoul", 2026, 12, 31, 12, 0, 0);
    if (!FCIsMarketHoliday(krx, marMonSub)) { failures++; fprintf(stderr, "FAIL %s: Independence Movement Day substitute not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, childrens)) { failures++; fprintf(stderr, "FAIL %s: Children's Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, libSub))    { failures++; fprintf(stderr, "FAIL %s: Liberation Day substitute not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, foundSub))  { failures++; fprintf(stderr, "FAIL %s: National Foundation substitute not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, hangeul))   { failures++; fprintf(stderr, "FAIL %s: Hangeul Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(krx, yearEnd))   { failures++; fprintf(stderr, "FAIL %s: Dec 31 year-end not flagged\n", __func__); }

    // Triple-market lunar-date coincidence: Sep 25 2026 = Chuseok Day 2
    // = HKEX Mid-Autumn = SSE Mid-Autumn. All three must flag.
    if (!FCIsMarketHoliday(hkex, chuseok2)) { failures++; fprintf(stderr, "FAIL %s: HKEX must flag Sep 25 (Mid-Autumn)\n", __func__); }
    if (!FCIsMarketHoliday(sse,  chuseok2)) { failures++; fprintf(stderr, "FAIL %s: SSE must flag Sep 25 (Mid-Autumn)\n", __func__); }

    // Cross-market negative: KRX must NOT flag NYSE Thanksgiving.
    NSDate *thanksgiving = dateAt(@"Asia/Seoul", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(krx, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: KRX wrongly flagged Thanksgiving\n", __func__);
    }

    // Regular KRX trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Asia/Seoul", 2026, 3, 11, 12, 0, 0);
    if (FCIsMarketHoliday(krx, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-03-11 wrongly flagged on KRX\n", __func__);
    }
}

void test_holiday_calendar_nse(void) {
    // v4 iter-185: NSE 2026. India's calendar is the most diverse —
    // mixes Gregorian-fixed civic dates (Republic Day, Gandhi Jayanti,
    // Christmas), Christian (Good Friday), Jain (Mahavir Jayanti),
    // Sikh (Guru Nanak Jayanti), Muslim (Bakri Id), and multiple
    // Hindu lunar-calendar festivals (Holi, Ram Navami, Ganesh
    // Chaturthi, Dussehra, Diwali 2-day cluster). This test asserts
    // the Gregorian-fixed dates with confidence; the lunar-derived
    // dates are fixture-locked best-effort.
    const ClockMarket *nse  = marketForId(@"nse");
    const ClockMarket *nyse = marketForId(@"nyse");

    // Gregorian-fixed Indian civic dates (highest confidence).
    NSDate *republicDay  = dateAt(@"Asia/Kolkata", 2026,  1, 26, 12, 0, 0);
    NSDate *maharashtra  = dateAt(@"Asia/Kolkata", 2026,  5,  1, 12, 0, 0);
    NSDate *gandhi       = dateAt(@"Asia/Kolkata", 2026, 10,  2, 12, 0, 0);
    NSDate *goodFriday   = dateAt(@"Asia/Kolkata", 2026,  4,  3, 12, 0, 0);
    NSDate *christmas    = dateAt(@"Asia/Kolkata", 2026, 12, 25, 12, 0, 0);
    if (!FCIsMarketHoliday(nse, republicDay)) { failures++; fprintf(stderr, "FAIL %s: Republic Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, maharashtra)) { failures++; fprintf(stderr, "FAIL %s: Maharashtra Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, gandhi))      { failures++; fprintf(stderr, "FAIL %s: Gandhi Jayanti not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, goodFriday))  { failures++; fprintf(stderr, "FAIL %s: Good Friday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, christmas))   { failures++; fprintf(stderr, "FAIL %s: Christmas not flagged\n", __func__); }

    // Lunar/religious-calc dates (fixture-locked, best-effort).
    NSDate *diwaliLaxmi  = dateAt(@"Asia/Kolkata", 2026, 11,  9, 12, 0, 0);
    NSDate *govardhan    = dateAt(@"Asia/Kolkata", 2026, 11, 10, 12, 0, 0);
    NSDate *ganesh       = dateAt(@"Asia/Kolkata", 2026,  8, 26, 12, 0, 0);
    NSDate *dussehra     = dateAt(@"Asia/Kolkata", 2026, 10, 20, 12, 0, 0);
    NSDate *holi         = dateAt(@"Asia/Kolkata", 2026,  3,  3, 12, 0, 0);
    if (!FCIsMarketHoliday(nse, diwaliLaxmi)) { failures++; fprintf(stderr, "FAIL %s: Diwali Laxmi Pujan not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, govardhan))   { failures++; fprintf(stderr, "FAIL %s: Govardhan Puja not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, ganesh))      { failures++; fprintf(stderr, "FAIL %s: Ganesh Chaturthi not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, dussehra))    { failures++; fprintf(stderr, "FAIL %s: Dussehra not flagged\n", __func__); }
    if (!FCIsMarketHoliday(nse, holi))        { failures++; fprintf(stderr, "FAIL %s: Holi not flagged\n", __func__); }

    // NSE does NOT substitute Independence Day (Aug 15 2026 = Saturday)
    // — Mon Aug 17 must NOT be flagged (not an NSE holiday; weekend
    // branch handles Aug 15 itself).
    NSDate *aug17Mon = dateAt(@"Asia/Kolkata", 2026, 8, 17, 12, 0, 0);
    if (FCIsMarketHoliday(nse, aug17Mon)) {
        failures++; fprintf(stderr, "FAIL %s: NSE wrongly flagged Aug 17 (Indep Day Aug 15 Sat, no substitute)\n", __func__);
    }

    // Cross-market negatives: NYSE must NOT flag NSE-only holidays.
    if (FCIsMarketHoliday(nyse, republicDay)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Republic Day\n", __func__); }
    if (FCIsMarketHoliday(nyse, gandhi))      { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Gandhi Jayanti\n", __func__); }
    if (FCIsMarketHoliday(nyse, diwaliLaxmi)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Diwali\n", __func__); }

    // NSE must NOT flag NYSE Thanksgiving.
    NSDate *thanksgiving = dateAt(@"Asia/Kolkata", 2026, 11, 26, 12, 0, 0);
    if (FCIsMarketHoliday(nse, thanksgiving)) {
        failures++; fprintf(stderr, "FAIL %s: NSE wrongly flagged Thanksgiving\n", __func__);
    }

    // Regular NSE trading day should NOT be flagged.
    NSDate *regularTue = dateAt(@"Asia/Kolkata", 2026, 7, 14, 12, 0, 0);
    if (FCIsMarketHoliday(nse, regularTue)) {
        failures++; fprintf(stderr, "FAIL %s: Tue 2026-07-14 wrongly flagged on NSE\n", __func__);
    }
}

void test_holiday_calendar_jse(void) {
    // v4 iter-186: JSE 2026. Covers SA substitute-holiday rule
    // (Sun → Mon substitute; Sat has no sub) via Aug 10 Mon shift
    // for Women's Day. Also locks "Family Day" (Easter Monday in SA)
    // and Day of Reconciliation Dec 16.
    const ClockMarket *jse  = marketForId(@"jse");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *familyDay       = dateAt(@"Africa/Johannesburg", 2026,  4,  6, 12, 0, 0);
    NSDate *freedomDay      = dateAt(@"Africa/Johannesburg", 2026,  4, 27, 12, 0, 0);
    NSDate *youthDay        = dateAt(@"Africa/Johannesburg", 2026,  6, 16, 12, 0, 0);
    NSDate *womensDaySub    = dateAt(@"Africa/Johannesburg", 2026,  8, 10, 12, 0, 0);
    NSDate *heritageDay     = dateAt(@"Africa/Johannesburg", 2026,  9, 24, 12, 0, 0);
    NSDate *reconciliation  = dateAt(@"Africa/Johannesburg", 2026, 12, 16, 12, 0, 0);
    if (!FCIsMarketHoliday(jse, familyDay))      { failures++; fprintf(stderr, "FAIL %s: Family Day (Easter Mon) not flagged\n", __func__); }
    if (!FCIsMarketHoliday(jse, freedomDay))     { failures++; fprintf(stderr, "FAIL %s: Freedom Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(jse, youthDay))       { failures++; fprintf(stderr, "FAIL %s: Youth Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(jse, womensDaySub))   { failures++; fprintf(stderr, "FAIL %s: Women's Day Mon substitute not flagged\n", __func__); }
    if (!FCIsMarketHoliday(jse, heritageDay))    { failures++; fprintf(stderr, "FAIL %s: Heritage Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(jse, reconciliation)) { failures++; fprintf(stderr, "FAIL %s: Day of Reconciliation not flagged\n", __func__); }

    // Human Rights Day Mar 21 2026 Sat — no substitute. Mon Mar 23
    // must NOT be flagged.
    NSDate *hrdMondayAfter = dateAt(@"Africa/Johannesburg", 2026, 3, 23, 12, 0, 0);
    if (FCIsMarketHoliday(jse, hrdMondayAfter)) {
        failures++; fprintf(stderr, "FAIL %s: JSE wrongly flagged Mar 23 (Human Rights Day Sat, no sub)\n", __func__);
    }

    // Cross-market: NYSE must NOT flag JSE-only holidays.
    if (FCIsMarketHoliday(nyse, freedomDay)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Freedom Day\n", __func__); }
    if (FCIsMarketHoliday(nyse, youthDay))   { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Youth Day\n", __func__); }

    // Regular JSE trading day should NOT be flagged.
    NSDate *regularWed = dateAt(@"Africa/Johannesburg", 2026, 7, 15, 12, 0, 0);
    if (FCIsMarketHoliday(jse, regularWed)) {
        failures++; fprintf(stderr, "FAIL %s: Wed 2026-07-15 wrongly flagged on JSE\n", __func__);
    }
}

void test_holiday_calendar_b3(void) {
    // v4 iter-186: B3 2026. Covers Carnival 2-day cluster (Feb 16-17),
    // Corpus Christi (moveable = Easter + 60d), and Brazilian civic
    // dates. Ash Wed (Feb 18) half-day session not modelled.
    const ClockMarket *b3   = marketForId(@"b3");
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *carnivalMon   = dateAt(@"America/Sao_Paulo", 2026,  2, 16, 12, 0, 0);
    NSDate *carnivalTue   = dateAt(@"America/Sao_Paulo", 2026,  2, 17, 12, 0, 0);
    NSDate *tiradentes    = dateAt(@"America/Sao_Paulo", 2026,  4, 21, 12, 0, 0);
    NSDate *corpusChristi = dateAt(@"America/Sao_Paulo", 2026,  6,  4, 12, 0, 0);
    NSDate *independence  = dateAt(@"America/Sao_Paulo", 2026,  9,  7, 12, 0, 0);
    NSDate *aparecida     = dateAt(@"America/Sao_Paulo", 2026, 10, 12, 12, 0, 0);
    NSDate *allSouls      = dateAt(@"America/Sao_Paulo", 2026, 11,  2, 12, 0, 0);
    NSDate *blackAwarens  = dateAt(@"America/Sao_Paulo", 2026, 11, 20, 12, 0, 0);
    if (!FCIsMarketHoliday(b3, carnivalMon))   { failures++; fprintf(stderr, "FAIL %s: Carnival Monday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, carnivalTue))   { failures++; fprintf(stderr, "FAIL %s: Carnival Tuesday not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, tiradentes))    { failures++; fprintf(stderr, "FAIL %s: Tiradentes not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, corpusChristi)) { failures++; fprintf(stderr, "FAIL %s: Corpus Christi not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, independence))  { failures++; fprintf(stderr, "FAIL %s: Independence Day not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, aparecida))     { failures++; fprintf(stderr, "FAIL %s: Our Lady of Aparecida not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, allSouls))      { failures++; fprintf(stderr, "FAIL %s: All Souls' not flagged\n", __func__); }
    if (!FCIsMarketHoliday(b3, blackAwarens))  { failures++; fprintf(stderr, "FAIL %s: Black Awareness Day not flagged\n", __func__); }

    // Proclamation Day Nov 15 2026 Sun — no substitute. Mon Nov 16
    // must NOT be flagged.
    NSDate *nov16Mon = dateAt(@"America/Sao_Paulo", 2026, 11, 16, 12, 0, 0);
    if (FCIsMarketHoliday(b3, nov16Mon)) {
        failures++; fprintf(stderr, "FAIL %s: B3 wrongly flagged Nov 16 (Proclamation Sun, no sub)\n", __func__);
    }

    // Cross-market: NYSE must NOT flag B3-only holidays.
    // NOTE: Avoid Carnival Mon Feb 16 (= NYSE Presidents' Day) and
    // Independence Day Sep 7 (= NYSE Labor Day) — use B3-only dates.
    if (FCIsMarketHoliday(nyse, carnivalTue))   { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Carnival Tue\n", __func__); }
    if (FCIsMarketHoliday(nyse, tiradentes))    { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Tiradentes\n", __func__); }
    if (FCIsMarketHoliday(nyse, corpusChristi)) { failures++; fprintf(stderr, "FAIL %s: NYSE wrongly flagged Corpus Christi\n", __func__); }

    // Regular B3 trading day should NOT be flagged.
    NSDate *regularThu = dateAt(@"America/Sao_Paulo", 2026, 7, 16, 12, 0, 0);
    if (FCIsMarketHoliday(b3, regularThu)) {
        failures++; fprintf(stderr, "FAIL %s: Thu 2026-07-16 wrongly flagged on B3\n", __func__);
    }
}

// v4 iter-193: half-day fixtures moved to tests/test_halfdays.m when
// test_holidays.m approached the 1000-LoC file-size-guard. Declared
// in test_halfdays.h and called from main() in test_session.m as if
// still local. See test_halfdays.m for:
//   test_halfday_calendar_nyse              (iter-188)
//   test_halfday_calendar_lse_and_target2   (iter-190)
//   test_halfday_calendar_hkex_and_tsx      (iter-191)
//   test_halfday_calendar_jse_and_asx       (iter-192)
//   test_nyse_halfday_state_closed          (iter-189 integration lock)

void test_nyse_holiday_state_closed(void) {
    // v4 iter-174: integration lock. Verifies FCIsMarketHoliday result
    // is actually consumed by computeSessionState — forces CLOSED and
    // blocks PRE/AFTER promotions on holidays.
    const ClockMarket *nyse = marketForId(@"nyse");

    NSDate *thanksgivingMidday    = dateAt(@"America/New_York", 2026, 11, 26, 12, 0, 0);
    NSDate *thanksgivingPreOpen   = dateAt(@"America/New_York", 2026, 11, 26,  9, 25, 0);
    NSDate *thanksgivingPostClose = dateAt(@"America/New_York", 2026, 11, 26, 16,  5, 0);
    NSDate *regularFridayMidday   = dateAt(@"America/New_York", 2026,  4, 24, 12,  0, 0);

    ASSERT_SESSION_STATE(nyse, thanksgivingMidday,    kSessionClosed);
    ASSERT_SESSION_STATE(nyse, thanksgivingPreOpen,   kSessionClosed);
    ASSERT_SESSION_STATE(nyse, thanksgivingPostClose, kSessionClosed);
    ASSERT_SESSION_STATE(nyse, regularFridayMidday,   kSessionOpen);
}

void test_holiday_chains_through_weekend(void) {
    // v4 iter-177: verify secsToNext correctly skips back-to-back
    // closed days (holiday → weekend → holiday). Scenario: LSE
    // on Thu 2026-12-24 at 18:00 London (after 16:30 close). The
    // calendar ahead:
    //   Dec 25 Fri — Christmas (holiday)
    //   Dec 26 Sat — weekend
    //   Dec 27 Sun — weekend
    //   Dec 28 Mon — Boxing Day observed (holiday)
    //   Dec 29 Tue — regular trading day, open 08:00 London
    // Expected secsToNext: 5 days — 6h (18:00→24:00) + 4×24h + 8h
    //   = 6*3600 + 4*86400 + 8*3600 = 21600 + 345600 + 28800 = 396000
    // (Before iter-177, the loop only skipped weekends so the answer
    // was off by ~3 days — first candidate was Dec 25 Friday's open.)
    const ClockMarket *lse = marketForId(@"lse");
    NSDate *thursdayAfterClose = dateAt(@"Europe/London", 2026, 12, 24, 18, 0, 0);
    SessionState s; double _p; long actual;
    computeSessionState(lse, thursdayAfterClose, &s, &_p, &actual);
    if (s != kSessionClosed) {
        failures++; fprintf(stderr, "FAIL %s: state expected CLOSED got %s\n", __func__, sessionStateName(s));
    }
    long expected = 396000L;
    long diff = actual > expected ? actual - expected : expected - actual;
    if (diff > 60) {  // 60s tolerance
        failures++;
        fprintf(stderr, "FAIL %s: secsToNext expected ~%ld (Dec 29 open) got %ld (diff %ld)\n",
                __func__, expected, actual, diff);
    }

    // NYSE Christmas Fri Dec 25 2026 at 18:00 ET → next open Mon Dec 28.
    // Chain through holiday (Fri) + weekend (Sat+Sun). Dec 28 is a
    // regular trading day for NYSE (Boxing Day is LSE-only).
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *nyseChristmasEve = dateAt(@"America/New_York", 2026, 12, 25, 18, 0, 0);
    computeSessionState(nyse, nyseChristmasEve, &s, &_p, &actual);
    // From Fri 18:00 ET to Mon 09:30 ET = 6h + 2*24h + 9.5h
    //   = 21600 + 172800 + 34200 = 228600
    long nyseExpected = 228600L;
    long nyseDiff = actual > nyseExpected ? actual - nyseExpected : nyseExpected - actual;
    if (nyseDiff > 60) {
        failures++;
        fprintf(stderr, "FAIL %s: NYSE secsToNext expected ~%ld got %ld (diff %ld)\n",
                __func__, nyseExpected, actual, nyseDiff);
    }
}
