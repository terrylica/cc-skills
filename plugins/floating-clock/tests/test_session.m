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
// Split v4 iter-118: the ~14 pref-lever / dispatcher invariant tests
// moved to test_levers.m once this file hit the 1000-LoC cap. Session-
// state, TZ-helper, flag/city, landing-time, and profile-coverage
// tests stay here.

#import <Foundation/Foundation.h>
#import "../Sources/data/MarketCatalog.h"
#import "../Sources/data/MarketSessionCalculator.h"
#import "../Sources/data/HolidayCalendar.h"
#import "../Sources/preferences/FloatingClockStarterProfiles.h"
#import "../Sources/content/LandingTimeFormatter.h"
#import "test_levers.h"
#import "test_holidays.h"  // iter-176 extraction
#import "test_halfdays.h"  // iter-193 extraction

// Shared failure counter — extern-declared in test_levers.h so
// test_levers.m can increment the same storage.
int failures = 0;

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
        case kSessionOpen:       return "OPEN";
        case kSessionLunch:      return "LUNCH";
        case kSessionClosed:     return "CLOSED";
        case kSessionPreMarket:  return "PRE-MARKET";
        case kSessionAfterHours: return "AFTER-HOURS";
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

#define ASSERT_PROGRESS_NEAR(mkt, date, expected, tolerance)                     \
    do {                                                                         \
        SessionState _s; double actual; long _n;                                 \
        computeSessionState((mkt), (date), &_s, &actual, &_n);                   \
        double diff = actual > (expected) ? actual - (expected) : (expected) - actual; \
        if (diff > (tolerance)) {                                                \
            fprintf(stderr, "FAIL %s: progress expected ~%.3f got %.3f (diff %.3f)\n", \
                    __func__, (double)(expected), actual, diff);                 \
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

static void test_nyse_premarket_last_15min(void) {
    // v4 iter-123: [open - 15min, open) on a weekday promotes the state
    // from CLOSED to PRE-MARKET. NYSE opens 09:30 EDT; 09:20 is 10 min
    // before = PRE-MARKET. 09:10 is 20 min before = still CLOSED.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d_pre  = dateAt(@"America/New_York", 2026, 4, 24, 9, 20, 0);
    ASSERT_STATE(nyse, d_pre, kSessionPreMarket);
    ASSERT_SECS_NEAR(nyse, d_pre, 10 * 60, 5);

    NSDate *d_closed_earlier = dateAt(@"America/New_York", 2026, 4, 24, 9, 10, 0);
    ASSERT_STATE(nyse, d_closed_earlier, kSessionClosed);

    // Edge: exactly at open should be OPEN (not PRE-MARKET — the PRE
    // promotion requires nowMins < openMins).
    NSDate *d_open = dateAt(@"America/New_York", 2026, 4, 24, 9, 30, 0);
    ASSERT_STATE(nyse, d_open, kSessionOpen);
}

static void test_tse_premarket_not_just_nyse(void) {
    // v4 iter-124: iter-123's PRE-MARKET promotion is uniform across
    // all 12 exchanges (no per-market hasPreMarket flag). Verify it
    // applies to TSE too so the design choice is locked: 15 min before
    // TSE's 09:00 JST open on a weekday = PRE-MARKET, not CLOSED.
    const ClockMarket *tse = marketForId(@"tse");
    // 08:50 JST on Fri 2026-04-24 (early hours pre-open)
    NSDate *d_pre = dateAt(@"Asia/Tokyo", 2026, 4, 24, 8, 50, 0);
    ASSERT_STATE(tse, d_pre, kSessionPreMarket);
    ASSERT_SECS_NEAR(tse, d_pre, 10 * 60, 5);

    // 08:30 JST = 30 min before = still CLOSED (outside the 15-min window).
    NSDate *d_closed = dateAt(@"Asia/Tokyo", 2026, 4, 24, 8, 30, 0);
    ASSERT_STATE(tse, d_closed, kSessionClosed);
}

static void test_premarket_not_on_weekend(void) {
    // v4 iter-124: PRE-MARKET promotion requires !isWeekend. Saturday
    // "15 min before market would open if it were a weekday" stays CLOSED.
    const ClockMarket *nyse = marketForId(@"nyse");
    // Sat 2026-04-25 09:20 EDT — weekday-schedule would say pre-open.
    NSDate *d_sat = dateAt(@"America/New_York", 2026, 4, 25, 9, 20, 0);
    ASSERT_STATE(nyse, d_sat, kSessionClosed);
}

static void test_nyse_afterhours_first_15min(void) {
    // v4 iter-125: symmetric to iter-123. [close, close+15min) on a
    // weekday promotes CLOSED → AFTER-HOURS. NYSE closes 16:00 EDT;
    // 16:10 is 10 min after close = AFTER-HOURS. 16:30 is 30 min after
    // = back to CLOSED. 15:59 is still OPEN (mid-session boundary).
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d_after = dateAt(@"America/New_York", 2026, 4, 24, 16, 10, 0);
    ASSERT_STATE(nyse, d_after, kSessionAfterHours);

    NSDate *d_closed_later = dateAt(@"America/New_York", 2026, 4, 24, 16, 30, 0);
    ASSERT_STATE(nyse, d_closed_later, kSessionClosed);

    // Edge: exactly at close should be CLOSED→AFTER-HOURS (nowMins >= closeMins).
    NSDate *d_close = dateAt(@"America/New_York", 2026, 4, 24, 16, 0, 0);
    ASSERT_STATE(nyse, d_close, kSessionAfterHours);

    // Edge: 15:59 is still mid-session.
    NSDate *d_open = dateAt(@"America/New_York", 2026, 4, 24, 15, 59, 0);
    ASSERT_STATE(nyse, d_open, kSessionOpen);
}

static void test_afterhours_not_on_weekend(void) {
    // v4 iter-125: AFTER-HOURS promotion also requires !isWeekend.
    // Sat 16:10 EDT (within the theoretical 15-min post-close window)
    // must stay CLOSED — markets don't post-close-auction on Saturdays.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d_sat = dateAt(@"America/New_York", 2026, 4, 25, 16, 10, 0);
    ASSERT_STATE(nyse, d_sat, kSessionClosed);
}

static void test_premarket_progress_is_zero(void) {
    // v4 iter-142: PRE-MARKET is before the regular session, so the
    // session-progress bar must read 0.0 (not "almost done" or "just
    // started"). computeSessionState sets progress to 0.0 when state
    // is neither OPEN/LUNCH nor nowMins >= closeMins. Lock it.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 9, 20, 0);
    ASSERT_STATE(nyse, d, kSessionPreMarket);
    ASSERT_PROGRESS_NEAR(nyse, d, 0.0, 0.001);
}

static void test_afterhours_progress_is_one(void) {
    // v4 iter-142: AFTER-HOURS is just after the regular session, so
    // the session-progress bar reads 1.0 — the session is 100%
    // complete. nowMins >= closeMins triggers the progress = 1.0
    // branch before the AFTER-HOURS state promotion.
    const ClockMarket *nyse = marketForId(@"nyse");
    NSDate *d = dateAt(@"America/New_York", 2026, 4, 24, 16, 10, 0);
    ASSERT_STATE(nyse, d, kSessionAfterHours);
    ASSERT_PROGRESS_NEAR(nyse, d, 1.0, 0.001);
}

// Shared sweep helper — iterates a single weekday in 30-min steps and
// asserts structural invariants (state ∈ 5-enum set, progress ∈ [0,1],
// secsToNext ≥ 0). Used by multiple market-specific sweep fixtures.
static void sweep_invariants(const ClockMarket *mkt, NSString *iana, const char *tzLabel) {
    for (int minute = 0; minute < 24 * 60; minute += 30) {
        int h = minute / 60;
        int m = minute % 60;
        NSDate *t = dateAt(iana, 2026, 4, 24, h, m, 0);
        SessionState s; double p; long n;
        computeSessionState(mkt, t, &s, &p, &n);
        BOOL stateValid = (s == kSessionOpen || s == kSessionLunch ||
                           s == kSessionClosed || s == kSessionPreMarket ||
                           s == kSessionAfterHours);
        if (!stateValid) {
            fprintf(stderr, "FAIL sweep %s: invalid state %d at %02d:%02d %s\n",
                    mkt->code, (int)s, h, m, tzLabel);
            failures++;
        }
        if (p < 0.0 || p > 1.0) {
            fprintf(stderr, "FAIL sweep %s: progress %.3f out of [0,1] at %02d:%02d %s\n",
                    mkt->code, p, h, m, tzLabel);
            failures++;
        }
        if (n < 0) {
            fprintf(stderr, "FAIL sweep %s: secsToNext %ld negative at %02d:%02d %s\n",
                    mkt->code, n, h, m, tzLabel);
            failures++;
        }
    }
}

static void test_state_invariants_24h_sweep(void) {
    // v4 iter-143: structural invariants across a full weekday sweep.
    // NYSE has no LUNCH state — see test_state_invariants_tse_sweep
    // (iter-145) for lunch-market coverage.
    const ClockMarket *nyse = marketForId(@"nyse");
    sweep_invariants(nyse, @"America/New_York", "EDT");
}

static void test_state_invariants_tse_sweep(void) {
    // v4 iter-145: extend iter-143's invariant sweep to a lunch-market.
    // TSE has LUNCH state (11:30-12:30 JST) which NYSE's sweep can never
    // hit. Locks the same invariants (state valid, progress ∈ [0,1],
    // secsToNext ≥ 0) through the lunch code path — a previously
    // untested region of computeSessionState.
    const ClockMarket *tse = marketForId(@"tse");
    sweep_invariants(tse, @"Asia/Tokyo", "JST");
}

static void test_state_invariants_jse_sweep(void) {
    // v4 iter-157: extend the invariant-sweep family to Africa. JSE
    // (Africa/Johannesburg) has no DST, no lunch, UTC+2 year-round —
    // structurally distinct from NYSE (DST, EDT/EST) and TSE (lunch,
    // no-DST JST). Running the same invariant sweep catches any
    // regression specific to the no-DST / no-lunch code path.
    const ClockMarket *jse = marketForId(@"jse");
    sweep_invariants(jse, @"Africa/Johannesburg", "SAST");
}

static void test_state_invariants_asx_sweep(void) {
    // v4 iter-162: Southern-Hemisphere DST sweep. ASX (Australia/Sydney)
    // runs AEDT (UTC+11, DST-on) from Oct to Apr and AEST (UTC+10,
    // DST-off) from Apr to Oct — inverse of NYSE's NH DST calendar.
    // 2026-04-24 is post-DST-end in SH (Apr 5 was the transition), so
    // ASX sits in AEST for this test. Validates the invariant path
    // through a SH-DST zone that neither NYSE (NH DST) nor
    // JSE/B3 (no-DST) exercises.
    const ClockMarket *asx = marketForId(@"asx");
    sweep_invariants(asx, @"Australia/Sydney", "AEST");
}

static void test_state_invariants_lse_sweep(void) {
    // v4 iter-163: European DST sweep. LSE (Europe/London) runs
    // BST (UTC+1, DST-on) from last-Sunday-of-March to last-Sunday-
    // of-October, GMT (UTC+0, DST-off) otherwise — DIFFERENT transition
    // rules than US (second-Sunday-of-March / first-Sunday-of-November).
    // 2026-04-24 is post-EU-spring-transition (Mar 29 was the switch),
    // so LSE sits in BST for this test. Validates the invariant path
    // through the EU DST zone — neither NYSE (US DST) nor ASX (SH DST)
    // exercises the EU transition-date logic.
    const ClockMarket *lse = marketForId(@"lse");
    sweep_invariants(lse, @"Europe/London", "BST");
}

static void test_state_invariants_b3_sweep(void) {
    // v4 iter-171: Americas-south no-DST sweep. B3 (America/Sao_Paulo)
    // runs at BRT (UTC-3) year-round since Brazil abolished DST in
    // 2019. Structurally parallel to JSE (no-DST) but in a different
    // TZ region — covers the negative-UTC-offset no-DST path. Iter-161
    // added the market, this iter adds the invariant sweep completion.
    const ClockMarket *b3 = marketForId(@"b3");
    sweep_invariants(b3, @"America/Sao_Paulo", "BRT");
}

static void test_auction_watcher_sets_extended_window(void) {
    // v4 iter-148: Auction Watcher's identity is "extended 30-min
    // auction window". If the profile doesn't explicitly set the pref,
    // it falls back to default "15min" and the profile lies about its
    // behavior. Lock it to catch accidental removal.
    NSDictionary *profiles = buildStarterProfiles();
    NSDictionary *aw = profiles[@"Auction Watcher"];
    if (aw == nil) {
        failures++; fprintf(stderr, "FAIL %s: Auction Watcher missing\n", __func__);
        return;
    }
    NSString *got = aw[@"SessionSignalWindow"];
    if (![got isEqualToString:@"30min"]) {
        failures++;
        fprintf(stderr, "FAIL %s: SessionSignalWindow='%s' (want '30min')\n",
                __func__, got ? got.UTF8String : "(unset)");
    }
}

static void test_weekend_always_closed(void) {
    // v4 iter-147: lock the weekend invariant. Markets do not open on
    // Sat or Sun, so every 30-min tick on Sat 2026-04-25 must stay
    // CLOSED (no promotion to OPEN / LUNCH / PRE-MARKET / AFTER-HOURS).
    // Complements the sweep helpers by exercising the weekend branch
    // in computeSessionState that NYSE/TSE weekday sweeps never touch.
    const ClockMarket *nyse = marketForId(@"nyse");
    for (int minute = 0; minute < 24 * 60; minute += 30) {
        int h = minute / 60, m = minute % 60;
        NSDate *t = dateAt(@"America/New_York", 2026, 4, 25, h, m, 0);  // Saturday
        SessionState s; double p; long n;
        computeSessionState(nyse, t, &s, &p, &n);
        if (s != kSessionClosed) {
            fprintf(stderr, "FAIL %s: Sat %02d:%02d EDT state %d (want CLOSED)\n",
                    __func__, h, m, (int)s);
            failures++;
        }
        if (n < 0) {
            fprintf(stderr, "FAIL %s: Sat %02d:%02d EDT secsToNext %ld negative\n",
                    __func__, h, m, n);
            failures++;
        }
    }
}

static void test_signal_window_pref_gates_premarket(void) {
    // v4 iter-127: locks the wiring between iter-126's SessionSignalWindow
    // pref and iter-123's PRE-MARKET promotion gate. iter-126's unit test
    // only covers the dispatcher (id → minutes); this covers the
    // integration (pref-value → actual state outcome).
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *saved = [d stringForKey:@"SessionSignalWindow"];

    const ClockMarket *nyse = marketForId(@"nyse");
    // NYSE opens 09:30 EDT. 09:20 = 10 min pre-open.
    NSDate *t = dateAt(@"America/New_York", 2026, 4, 24, 9, 20, 0);

    // "off" disables promotion: 10 min pre-open stays CLOSED.
    [d setObject:@"off" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionClosed);

    // "5min" is too narrow at T-10min: still CLOSED.
    [d setObject:@"5min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionClosed);

    // "15min" / "30min" / "60min" all cover T-10min: PRE-MARKET.
    [d setObject:@"15min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionPreMarket);
    [d setObject:@"30min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionPreMarket);
    [d setObject:@"60min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionPreMarket);

    // Restore.
    if (saved) [d setObject:saved forKey:@"SessionSignalWindow"];
    else       [d removeObjectForKey:@"SessionSignalWindow"];
}

static void test_signal_window_pref_gates_afterhours(void) {
    // v4 iter-127: symmetric integration test for iter-125's AFTER-HOURS
    // promotion gate.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *saved = [d stringForKey:@"SessionSignalWindow"];

    const ClockMarket *nyse = marketForId(@"nyse");
    // NYSE closes 16:00 EDT. 16:10 = 10 min post-close.
    NSDate *t = dateAt(@"America/New_York", 2026, 4, 24, 16, 10, 0);

    // "off" disables promotion: 10 min post-close stays CLOSED.
    [d setObject:@"off" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionClosed);

    // "5min" is too narrow at T+10min: back to CLOSED.
    [d setObject:@"5min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionClosed);

    // "15min" / "30min" / "60min" all cover T+10min: AFTER-HOURS.
    [d setObject:@"15min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionAfterHours);
    [d setObject:@"30min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionAfterHours);
    [d setObject:@"60min" forKey:@"SessionSignalWindow"];
    ASSERT_STATE(nyse, t, kSessionAfterHours);

    // Restore.
    if (saved) [d setObject:saved forKey:@"SessionSignalWindow"];
    else       [d removeObjectForKey:@"SessionSignalWindow"];
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
        {"Africa/Johannesburg", "JHB"},  // iter-155
        {"America/Sao_Paulo",   "SAO"},  // iter-161
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
        "Africa/Johannesburg",  // iter-155
        "America/Sao_Paulo",    // iter-161
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

// v4 iter-176: holiday-calendar tests moved to tests/test_holidays.m
// when this file hit the 1000-LoC file-size-guard. Function bodies
// for test_holiday_calendar_{nyse,lse,tse} + test_nyse_holiday_state_closed
// now live there; they're declared in test_holidays.h and called from
// main() below as if still local.

static void test_market_roster_lock(void) {
    // v4 iter-156: lock the 13-exchange roster (post-iter-155 JSE).
    // Existing coverage tests iterate kMarkets and pass for whatever
    // count happens to be present — a silent removal wouldn't fail
    // any test. This one explicitly names each market ID so removal
    // triggers a failure immediately.
    // v4 iter-164: upgraded from ID-only to (ID, iana, code) triple so
    // an accidental IANA rename (e.g. "Asia/Tokyo" → "Asia/Tokio") or
    // code typo (e.g. "NYSE" → "NYS") fails CI immediately instead of
    // silently changing render output + time-zone behavior.
    struct { NSString *id; const char *iana; const char *code; } expected[] = {
        {@"local",    "",                      "LOCAL"},
        {@"nyse",     "America/New_York",      "NYSE"},
        {@"tsx",      "America/Toronto",       "TSX"},
        {@"lse",      "Europe/London",         "LSE"},
        {@"euronext", "Europe/Paris",          "EUX"},
        {@"xetra",    "Europe/Berlin",         "XETR"},
        {@"six",      "Europe/Zurich",         "SIX"},
        {@"tse",      "Asia/Tokyo",            "TSE"},
        {@"hkex",     "Asia/Hong_Kong",        "HKEX"},
        {@"sse",      "Asia/Shanghai",         "SSE"},
        {@"krx",      "Asia/Seoul",            "KRX"},
        {@"nse",      "Asia/Kolkata",          "NSE"},
        {@"asx",      "Australia/Sydney",      "ASX"},
        {@"jse",      "Africa/Johannesburg",   "JSE"},
        {@"b3",       "America/Sao_Paulo",     "B3"},
    };
    size_t expectedCount = sizeof(expected) / sizeof(expected[0]);
    if (kNumMarkets != expectedCount) {
        failures++;
        fprintf(stderr, "FAIL %s: kNumMarkets=%zu, expected %zu\n",
                __func__, kNumMarkets, expectedCount);
    }
    for (size_t i = 0; i < expectedCount; i++) {
        const ClockMarket *m = marketForId(expected[i].id);
        NSString *gotId = [NSString stringWithUTF8String:m->id];
        if (![gotId isEqualToString:expected[i].id]) {
            failures++;
            fprintf(stderr, "FAIL %s: id '%s' missing (marketForId returned '%s')\n",
                    __func__, expected[i].id.UTF8String, gotId.UTF8String);
            continue;
        }
        if (strcmp(m->iana, expected[i].iana) != 0) {
            failures++;
            fprintf(stderr, "FAIL %s: '%s' iana '%s' (want '%s')\n",
                    __func__, expected[i].id.UTF8String, m->iana, expected[i].iana);
        }
        if (strcmp(m->code, expected[i].code) != 0) {
            failures++;
            fprintf(stderr, "FAIL %s: '%s' code '%s' (want '%s')\n",
                    __func__, expected[i].id.UTF8String, m->code, expected[i].code);
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
    // Exceptions are power-user overrides that fall back cleanly when
    // unset: FontName (iter-6, iTerm2/system cascade fallback),
    // {Local,Active,Next}Opacity (iter-90, CanvasOpacity fallback via
    // FCResolveSegmentOpacity), and LetterSpacing (iter-94, no-op at
    // value "normal" which is the registered default).
    NSDictionary *profiles = buildStarterProfiles();
    NSArray *keys = profileManagedKeys();
    NSSet *exempt = [NSSet setWithObjects:@"FontName",
                                          @"LocalOpacity",
                                          @"ActiveOpacity",
                                          @"NextOpacity",
                                          @"LetterSpacing",
                                          @"LineSpacing",
                                          @"TimeSeparator",
                                          @"SessionSignalWindow",  // iter-128 — registered default "15min" is fine
                                          @"UrgencyHorizon",       // iter-215 — registered default "60min" is fine
                                          nil];

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

static void test_profile_managed_keys_covers_iter126_lever(void) {
    // v4 iter-128: SessionSignalWindow must live inside profileManagedKeys
    // so Save/Load/Switch profile round-trips it. Without this, iter-126's
    // pref silently leaks across profile changes (e.g. user picks Hacker
    // profile with "off", switches to Day Trader, and still sees no
    // PRE-MARKET / AFTER-HOURS glyph). Regression guard.
    NSArray *keys = profileManagedKeys();
    if (![keys containsObject:@"SessionSignalWindow"]) {
        failures++;
        fprintf(stderr, "FAIL %s: profileManagedKeys() missing SessionSignalWindow\n", __func__);
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

    // v4 iter-75 → v4 iter-208: progressive human-readable at >=1 day.
    // iter-208 added seconds (T-Nd Hh MMm SSs) per user directive —
    // all countdowns must tick visibly.
    ASSERT_EQ_STR(formatCountdownFancy(86400),  @"T-1d 0h 00m 00s");
    ASSERT_EQ_STR(formatCountdownFancy(214020), @"T-2d 11h 27m 00s");
    ASSERT_EQ_STR(formatCountdownFancy(86400 + 5*60 + 33), @"T-1d 0h 05m 33s");
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
    NSDate *now     = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 24, 6, 30, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "America/New_York", &user, &mkt);
    ASSERT_EQ_STR(user, @"06:30");
    ASSERT_EQ_STR(mkt,  @"09:30 EDT");
}

static void test_landing_cross_day_cross_weekday(void) {
    NSDate *now = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 26, 17, 0, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "Asia/Tokyo", &user, &mkt);
    ASSERT_EQ_STR(user, @"Sun 17:00");
    ASSERT_EQ_STR(mkt,  @"Mon 09:00 JST");
}

static void test_landing_cross_day_same_weekday(void) {
    NSDate *now = dateAt(@"America/Los_Angeles", 2026, 4, 24, 23, 0, 0);
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 27, 0, 0, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "Europe/London", &user, &mkt);
    ASSERT_EQ_STR(user, @"Mon 00:00");
    ASSERT_EQ_STR(mkt,  @"08:00 BST");
}

static void test_landing_empty_iana(void) {
    NSDate *now     = dateAt(@"America/Los_Angeles", 2026, 4, 24, 4, 0, 0);
    NSDate *landsAt = dateAt(@"America/Los_Angeles", 2026, 4, 24, 6, 30, 0);
    NSString *user = nil, *mkt = nil;
    FCFormatLandingTime(now, landsAt, "", &user, &mkt);
    ASSERT_EQ_STR(user, @"06:30");
    ASSERT_EQ_STR(mkt,  @"");
}

static void test_starter_profiles_count(void) {
    // Sanity: the canonical bundled starters exist.
    NSDictionary *profiles = buildStarterProfiles();
    NSArray *expected = @[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Researcher", @"Watch Party", @"Auction Watcher", @"Arctic"];
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

int main(void) {
    @autoreleasepool {
        test_nyse_closed_before_open_today();
        test_nyse_open_midsession();
        test_nyse_closed_friday_evening_skips_to_monday();
        test_nyse_saturday_weekend();
        test_nyse_premarket_last_15min();
        test_tse_premarket_not_just_nyse();
        test_premarket_not_on_weekend();
        test_nyse_afterhours_first_15min();
        test_afterhours_not_on_weekend();
        test_premarket_progress_is_zero();
        test_afterhours_progress_is_one();
        test_state_invariants_24h_sweep();
        test_state_invariants_tse_sweep();
        test_state_invariants_jse_sweep();
        test_state_invariants_asx_sweep();
        test_state_invariants_lse_sweep();
        test_state_invariants_b3_sweep();
        test_weekend_always_closed();
        test_auction_watcher_sets_extended_window();
        test_signal_window_pref_gates_premarket();
        test_signal_window_pref_gates_afterhours();
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
        test_market_roster_lock();
        test_holiday_calendar_nyse();
        test_holiday_calendar_lse();
        test_holiday_calendar_tse();
        test_holiday_calendar_hkex();
        test_holiday_calendar_target2();
        test_holiday_calendar_asx();
        test_holiday_calendar_tsx();
        test_holiday_calendar_six();
        test_holiday_calendar_sse();
        test_holiday_calendar_krx();
        test_holiday_calendar_nse();
        test_holiday_calendar_jse();
        test_holiday_calendar_b3();
        test_halfday_calendar_nyse();
        test_halfday_calendar_lse_and_target2();
        test_halfday_calendar_hkex_and_tsx();
        test_halfday_calendar_jse_and_asx();
        test_nyse_halfday_state_closed();
        test_nyse_holiday_state_closed();
        test_holiday_chains_through_weekend();
        test_flag_empty_for_unknown_iana();

        test_starter_profiles_cover_all_keys();
        test_starter_profiles_count();
        test_profile_managed_keys_covers_iter126_lever();

        test_countdown_fancy_format();
        test_lunch_markets_identified();

        test_landing_same_day_same_weekday();
        test_landing_cross_day_cross_weekday();
        test_landing_cross_day_same_weekday();
        test_landing_empty_iana();

        // Lever / dispatcher tests (declared in test_levers.h,
        // defined in test_levers.m; share the `failures` counter).
        test_font_weight_parser();
        test_segment_weight_fallback();
        test_segment_opacity_fallback();
        test_progress_bar_glyph_styles();
        test_theme_catalog_invariants();
        test_letter_spacing_parser();
        test_line_spacing_parser();
        test_date_format_prefix();
        test_sky_glyph_phases();
        test_segment_gap_points();
        test_density_pad_points();
        test_corner_radius_points();
        test_current_time_format();
        test_quick_styles_invariants();
        test_shadow_spec_catalog();
        test_session_signal_window();
        test_session_state_label();
        test_session_state_color();
        test_state_is_trading();
        test_clipboard_header_format();
        test_urgency_color_tiers();
        test_urgency_continuous_and_flash();
        test_urgency_horizon_dispatcher();

        if (failures == 0) {
            fprintf(stderr, "All 86 tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%d test(s) failed.\n", failures);
        return 1;
    }
}
