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
#import "../Sources/preferences/FloatingClockStarterProfiles.h"
#import "../Sources/content/LandingTimeFormatter.h"
#import "../Sources/rendering/FontResolver.h"

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

static void test_city_codes_for_all_markets(void) {
    // Each supported IANA has a stable 3-letter city code. Catches
    // future typos or IANA-to-display-code drift.
    struct { const char *iana; const char *code; } fixtures[] = {
        {"America/New_York",  "NYC"},
        {"America/Toronto",   "TOR"},
        {"Europe/London",     "LON"},
        {"Europe/Paris",      "PAR"},
        {"Europe/Berlin",     "FRA"},
        {"Europe/Zurich",     "ZRH"},
        {"Asia/Tokyo",        "TOK"},
        {"Asia/Hong_Kong",    "HKG"},
        {"Asia/Shanghai",     "SHA"},
        {"Asia/Seoul",        "SEO"},
        {"Asia/Kolkata",      "MUM"},
        {"Australia/Sydney",  "SYD"},
    };
    for (size_t i = 0; i < sizeof(fixtures)/sizeof(fixtures[0]); i++) {
        const char *got = cityCodeForIana(fixtures[i].iana);
        if (strcmp(got, fixtures[i].code) != 0) {
            fprintf(stderr, "FAIL %s: %s expected '%s' got '%s'\n",
                    __func__, fixtures[i].iana, fixtures[i].code, got);
            failures++;
        }
    }
}

static void test_flag_emoji_present_for_all_markets(void) {
    // Each supported IANA has a country-flag emoji. Exact byte sequence
    // isn't asserted (regional-indicator pairs are easy to typo) — just
    // verify non-empty and starts with the regional-indicator lead byte 0xF0.
    const char *ianas[] = {
        "America/New_York", "America/Toronto", "Europe/London", "Europe/Paris",
        "Europe/Berlin", "Europe/Zurich", "Asia/Tokyo", "Asia/Hong_Kong",
        "Asia/Shanghai", "Asia/Seoul", "Asia/Kolkata", "Australia/Sydney",
    };
    for (size_t i = 0; i < sizeof(ianas)/sizeof(ianas[0]); i++) {
        const char *flag = flagForIana(ianas[i]);
        if (flag[0] == 0) {
            fprintf(stderr, "FAIL %s: %s has empty flag\n", __func__, ianas[i]);
            failures++;
        } else if ((unsigned char)flag[0] != 0xF0) {
            fprintf(stderr, "FAIL %s: %s flag lead byte 0x%02x (expected 0xF0)\n",
                    __func__, ianas[i], (unsigned char)flag[0]);
            failures++;
        }
    }
}

static void test_flag_empty_for_unknown_iana(void) {
    // Defensive: unknown IANAs return "" (not null, not garbage).
    if (flagForIana("Mars/Olympus_Mons")[0] != 0) {
        fprintf(stderr, "FAIL %s: expected empty flag for unknown IANA\n", __func__);
        failures++;
    }
    if (flagForIana(NULL)[0] != 0) {
        fprintf(stderr, "FAIL %s: NULL iana should return empty flag\n", __func__);
        failures++;
    }
}

static void test_starter_profiles_cover_all_keys(void) {
    // Locks in v4 iter-55's fix: each starter must specify every key
    // in profileManagedKeys() so switching profiles fully resets state.
    // FontName is the one legit exception (power-user override that
    // defaults to the iTerm2/system cascade).
    NSDictionary *profiles = buildStarterProfiles();
    NSArray *keys = profileManagedKeys();
    NSSet *exempt = [NSSet setWithObject:@"FontName"];

    for (NSString *profileName in profiles.allKeys) {
        NSDictionary *profile = profiles[profileName];
        for (NSString *key in keys) {
            if ([exempt containsObject:key]) continue;
            if (profile[key] == nil) {
                fprintf(stderr, "FAIL %s: profile '%s' missing key '%s'\n",
                        __func__, [profileName UTF8String], [key UTF8String]);
                failures++;
            }
        }
    }
}

static void test_countdown_fancy_format(void) {
    // v4 iter-59: T-HH:MM:SS rocket-launch convention, sub-day.
    ASSERT_EQ_STR(formatCountdownFancy(0),      @"T-00:00:00");
    ASSERT_EQ_STR(formatCountdownFancy(7),      @"T-00:00:07");
    ASSERT_EQ_STR(formatCountdownFancy(105),    @"T-00:01:45");  // 1m 45s
    ASSERT_EQ_STR(formatCountdownFancy(9257),   @"T-02:34:17");  // 2h 34m 17s
    ASSERT_EQ_STR(formatCountdownFancy(35940),  @"T-09:59:00");  // almost 10h
    ASSERT_EQ_STR(formatCountdownFancy(-5),     @"T-00:00:00");  // negative clamp

    // v4 iter-75: progressive human-readable at >=1 day.
    // 24h exactly = 1d 0h 0m.
    ASSERT_EQ_STR(formatCountdownFancy(86400),  @"T-1d 0h 00m");
    // 2d 11h 27m = 2*86400 + 11*3600 + 27*60 = 172800 + 39600 + 1620 = 214020
    ASSERT_EQ_STR(formatCountdownFancy(214020), @"T-2d 11h 27m");
    // 1d 0h 05m — minute zero-padding
    ASSERT_EQ_STR(formatCountdownFancy(86400 + 5*60), @"T-1d 0h 05m");
    // Just-under-day stays in HH:MM:SS form (23:59:59).
    ASSERT_EQ_STR(formatCountdownFancy(86399), @"T-23:59:59");
}

static void test_lunch_markets_identified(void) {
    // Lock in which markets have midday-lunch windows. If a future edit
    // accidentally adds lunch to a no-lunch market or removes it from a
    // lunch market, this catches it. Source of truth: ClockMarket
    // struct's lunch_start_h >= 0 flag.
    struct { const char *id; BOOL hasLunch; } fixtures[] = {
        {"nyse",  NO},  {"tsx",  NO},  {"lse",  NO},  {"euronext", NO},
        {"xetra", NO},  {"six",  NO},  {"tse",  YES}, {"hkex",     YES},
        {"sse",   YES}, {"krx",  NO},  {"nse",  NO},  {"asx",      NO},
    };
    for (size_t i = 0; i < sizeof(fixtures)/sizeof(fixtures[0]); i++) {
        const ClockMarket *m = marketForId(@(fixtures[i].id));
        BOOL actualHasLunch = (m->lunch_start_h >= 0);
        if (actualHasLunch != fixtures[i].hasLunch) {
            fprintf(stderr, "FAIL %s: %s hasLunch expected %d got %d\n",
                    __func__, fixtures[i].id, fixtures[i].hasLunch, actualHasLunch);
            failures++;
        }
    }
}

// FCFormatLandingTime fixtures (iter-74/76). Tests the dual-zone
// landing-time formatter's cross-day / cross-weekday disambiguation
// rules. Now that `now` is a parameter, results are reproducible.
//
// Scenario 1: same-day, same-weekday — both bare HH:mm.
//   User PDT (UTC-7), NYSE opens at local 06:30 today.
static void test_landing_same_day_same_weekday(void) {
    // Fri 2026-04-24 04:00 PDT = Fri 11:00 UTC.
    NSDate *now     = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    // NYSE opens 09:30 EDT = 06:30 PDT same Fri.
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 24, 6, 30, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "America/New_York", &user, &mkt);
    ASSERT_EQ_STR(user, @"06:30");
    ASSERT_EQ_STR(mkt,  @"09:30 EDT");
}

// Scenario 2: cross-day AND cross-weekday — Sun in user-local, Mon in
// market-local (the TSE weekend case the user flagged).
static void test_landing_cross_day_cross_weekday(void) {
    // Fri 2026-04-24 04:00 PDT.
    NSDate *now = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    // TSE opens Mon 2026-04-27 09:00 JST = Sun 2026-04-26 17:00 PDT.
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 26, 17, 0, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "Asia/Tokyo", &user, &mkt);
    ASSERT_EQ_STR(user, @"Sun 17:00");
    ASSERT_EQ_STR(mkt,  @"Mon 09:00 JST");
}

// Scenario 3: cross-day but same weekday in both zones (user sees a
// different date but same weekday — e.g. London opens tomorrow for a
// user who stays up past midnight).
static void test_landing_cross_day_same_weekday(void) {
    // Fri 2026-04-24 23:00 PDT = Sat 06:00 UTC.
    NSDate *now = dateAt(@"America/Los_Angeles", 2026, 4, 24, 23, 0, 0);
    // LSE opens Mon 2026-04-27 08:00 BST = Sun 00:00 PDT = Sun 07:00 UTC.
    // Both times are Mon in their respective zones.
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 27, 0, 0, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "Europe/London", &user, &mkt);
    // Not same-day (Fri vs Mon) so user gets weekday prefix.
    ASSERT_EQ_STR(user, @"Mon 00:00");
    // Same weekday on both sides (Mon) so market gets no prefix.
    ASSERT_EQ_STR(mkt,  @"08:00 BST");
}

// Scenario 4: unknown/empty IANA — market string should be empty.
static void test_landing_empty_iana(void) {
    NSDate *now     = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 24, 6, 30, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "", &user, &mkt);
    ASSERT_EQ_STR(user, @"06:30");
    ASSERT_EQ_STR(mkt,  @"");
}

static void test_starter_profiles_count(void) {
    // Sanity: the 5 canonical bundled starters exist. Catches accidental
    // deletion or typo in buildStarterProfiles.
    NSDictionary *profiles = buildStarterProfiles();
    NSArray *expected = @[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Researcher", @"Watch Party"];
    if (profiles.count != expected.count) {
        fprintf(stderr, "FAIL %s: expected %lu starters got %lu\n",
                __func__, (unsigned long)expected.count, (unsigned long)profiles.count);
        failures++;
    }
    for (NSString *name in expected) {
        if (profiles[name] == nil) {
            fprintf(stderr, "FAIL %s: missing starter '%s'\n", __func__, [name UTF8String]);
            failures++;
        }
    }
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

static void test_font_weight_parser(void) {
    // Known ids map to their NSFontWeight constants.
    struct { NSString *id; NSFontWeight w; } cases[] = {
        {@"regular",  NSFontWeightRegular},
        {@"medium",   NSFontWeightMedium},
        {@"semibold", NSFontWeightSemibold},
        {@"bold",     NSFontWeightBold},
        {@"heavy",    NSFontWeightHeavy},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSFontWeight got = FCParseFontWeight(cases[i].id);
        if (fabs(got - cases[i].w) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.2f got %.2f\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].w, (double)got);
            failures++;
        }
    }
    // Unknown / nil / empty fall back to Medium (matches registerDefaults).
    if (fabs(FCParseFontWeight(nil) - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: nil → Medium\n", __func__); failures++;
    }
    if (fabs(FCParseFontWeight(@"") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: empty → Medium\n", __func__); failures++;
    }
    if (fabs(FCParseFontWeight(@"ultrablack") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: unknown → Medium\n", __func__); failures++;
    }
}

static void test_segment_weight_fallback(void) {
    // FCResolveSegmentWeight's lookup order:
    //   1. NSUserDefaults[segmentKey]  (when non-empty)
    //   2. NSUserDefaults[@"FontWeight"] (when non-empty)
    //   3. NSFontWeightMedium
    // Seed values directly, verify each tier resolves.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"FontWeight"];
    [d removeObjectForKey:@"TestSegWeight"];

    // Tier 3: both unset → Medium
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: unset → Medium\n", __func__); failures++;
    }

    // Tier 2: only global set → inherits global
    [d setObject:@"bold" forKey:@"FontWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightBold) > 0.001) {
        fprintf(stderr, "FAIL %s: global bold → Bold\n", __func__); failures++;
    }

    // Tier 1: segment override wins over global
    [d setObject:@"heavy" forKey:@"TestSegWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightHeavy) > 0.001) {
        fprintf(stderr, "FAIL %s: override heavy → Heavy\n", __func__); failures++;
    }

    // Empty string in segment key falls through to global.
    [d setObject:@"" forKey:@"TestSegWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightBold) > 0.001) {
        fprintf(stderr, "FAIL %s: empty override → global Bold\n", __func__); failures++;
    }

    // Cleanup — don't leak fixtures into user defaults when run outside
    // the test binary (though standardUserDefaults in a throwaway
    // process is memory-only under normal test invocation).
    [d removeObjectForKey:@"FontWeight"];
    [d removeObjectForKey:@"TestSegWeight"];
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

        test_city_codes_for_all_markets();
        test_flag_emoji_present_for_all_markets();
        test_flag_empty_for_unknown_iana();

        test_starter_profiles_cover_all_keys();
        test_starter_profiles_count();

        test_countdown_fancy_format();
        test_lunch_markets_identified();

        test_landing_same_day_same_weekday();
        test_landing_cross_day_cross_weekday();
        test_landing_cross_day_same_weekday();
        test_landing_empty_iana();

        test_font_weight_parser();
        test_segment_weight_fallback();

        if (failures == 0) {
            fprintf(stderr, "All 26 tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%d test(s) failed.\n", failures);
        return 1;
    }
}
