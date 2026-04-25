#import "test_local_features.h"
#import "../Sources/content/WeekProgressBar.h"
#import "../Sources/data/MoonPhase.h"
#import "../Sources/data/SolarEvents.h"
#import <math.h>

void test_week_fraction(void) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    struct { NSInteger year, mon, day, h, m, s; double expectMin, expectMax; const char *label; } cases[] = {
        {2026, 4, 20, 0, 0, 0,    0.0,        0.001,    "Mon midnight"},
        {2026, 4, 20, 12, 0, 0,   0.0714 - 0.001, 0.0714 + 0.001, "Mon noon"},
        {2026, 4, 24, 17, 18, 0,  0.674 - 0.001, 0.674 + 0.001, "Fri 17:18"},
        {2026, 4, 26, 23, 59, 59, 0.999, 1.001, "Sun end"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSDateComponents *comp = [[NSDateComponents alloc] init];
        comp.year = cases[i].year; comp.month = cases[i].mon; comp.day = cases[i].day;
        comp.hour = cases[i].h;    comp.minute = cases[i].m;  comp.second = cases[i].s;
        NSDate *d = [cal dateFromComponents:comp];
        double got = FCWeekFraction(d);
        if (got < cases[i].expectMin || got > cases[i].expectMax) {
            failures++;
            fprintf(stderr, "FAIL %s: %s expected [%.4f, %.4f] got %.4f\n",
                    __func__, cases[i].label, cases[i].expectMin, cases[i].expectMax, got);
        }
    }
    if (FCWeekFraction(nil) != 0.0) { failures++; fprintf(stderr, "FAIL %s: nil → %.4f\n", __func__, FCWeekFraction(nil)); }
    NSDateComponents *fri = [[NSDateComponents alloc] init];
    fri.year = 2026; fri.month = 4; fri.day = 24; fri.hour = 17; fri.minute = 18;
    NSDate *friDate = [cal dateFromComponents:fri];
    struct { int cpd; NSUInteger expectLen; } barCases[] = { {2, 20}, {4, 34} };
    for (size_t i = 0; i < 2; i++) {
        NSString *b = FCBuildWeekProgressBar(friDate, barCases[i].cpd);
        if (b.length != barCases[i].expectLen) {
            failures++; fprintf(stderr, "FAIL %s: cpd=%d len=%lu want %lu\n",
                    __func__, barCases[i].cpd, (unsigned long)b.length, (unsigned long)barCases[i].expectLen);
        }
    }
    NSUInteger sepCount = [[FCBuildWeekProgressBar(friDate, 2) componentsSeparatedByString:@"┊"] count] - 1;
    if (sepCount != 6) { failures++; fprintf(stderr, "FAIL %s: %lu seps (want 6)\n", __func__, (unsigned long)sepCount); }
    if (FCBuildWeekProgressBar(nil, 2).length != 20) { failures++; fprintf(stderr, "FAIL %s: nil bar length\n", __func__); }
}

void test_phase_color_for_hour(void) {
    struct { NSInteger h; BOOL nilOk; } cases[] = {
        {3, NO}, {5, NO}, {6, NO}, {7, YES}, {12, YES}, {16, YES}, {17, NO}, {18, NO}, {19, NO}, {23, NO},
    };
    for (size_t i = 0; i < 10; i++) {
        BOOL g = (FCPhaseColorForHour(cases[i].h) == nil);
        if (g != cases[i].nilOk) { failures++; fprintf(stderr, "FAIL %s: h=%ld\n", __func__, (long)cases[i].h); }
    }
}

void test_moon_phase(void) {
    // iter-244: lock new-moon epoch (2000-01-06 18:14 UTC) → 🌑;
    // half-synodic-month later → 🌕.
    NSDate *r = [NSDate dateWithTimeIntervalSince1970:947182440];
    NSDate *full = [NSDate dateWithTimeIntervalSince1970:947182440 + 1275721];
    if (![FCMoonPhaseGlyph(r) isEqualToString:@"🌑"]) { failures++; fprintf(stderr, "FAIL %s: ref glyph %s\n", __func__, FCMoonPhaseGlyph(r).UTF8String); }
    if (![FCMoonPhaseGlyph(full) isEqualToString:@"🌕"]) { failures++; fprintf(stderr, "FAIL %s: full glyph %s\n", __func__, FCMoonPhaseGlyph(full).UTF8String); }
    if (![FCMoonPhaseGlyph(nil) isEqualToString:@"🌑"]) { failures++; fprintf(stderr, "FAIL %s: nil should fallback to 🌑\n", __func__); }
    if (FCMoonPhaseFraction(nil) != 0.0) { failures++; fprintf(stderr, "FAIL %s: nil fraction\n", __func__); }
}

void test_solar_events(void) {
    // iter-250: NYC 2026-04-25 — published NOAA values: sunrise ~10:08 UTC
    // (06:08 EDT), sunset ~23:46 UTC (19:46 EDT). Tolerance ±5min.
    NSCalendar *gc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    gc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 4; c.day = 25; c.hour = 12;
    NSDate *noon = [gc dateFromComponents:c];

    FCSolarEvents ev = FCSolarEventsForLocation(noon, 40.7128, -74.0060);
    if (!ev.valid) {
        failures++;
        fprintf(stderr, "FAIL %s: NYC 2026-04-25 events invalid\n", __func__);
        return;
    }

    double midnightUTC = floor(ev.sunrise / 86400.0) * 86400.0;
    double srSecs = ev.sunrise - midnightUTC;
    double ssSecs = ev.sunset  - midnightUTC;
    double srExpect = 10.0 * 3600 + 8 * 60;   // 10:08 UTC
    double ssExpect = 23.0 * 3600 + 46 * 60;  // 23:46 UTC

    if (fabs(srSecs - srExpect) > 300) {
        failures++;
        fprintf(stderr, "FAIL %s: NYC sunrise off by %.0fs (expected ~10:08 UTC)\n",
                __func__, srSecs - srExpect);
    }
    if (fabs(ssSecs - ssExpect) > 300) {
        failures++;
        fprintf(stderr, "FAIL %s: NYC sunset off by %.0fs (expected ~23:46 UTC)\n",
                __func__, ssSecs - ssExpect);
    }
    if (ev.civilDawn >= ev.sunrise) {
        failures++; fprintf(stderr, "FAIL %s: civilDawn >= sunrise\n", __func__);
    }
    if (ev.civilDusk <= ev.sunset) {
        failures++; fprintf(stderr, "FAIL %s: civilDusk <= sunset\n", __func__);
    }

    // Polar fallback: 89°N at June solstice → permanent day, invalid struct.
    NSDateComponents *jun = [[NSDateComponents alloc] init];
    jun.year = 2026; jun.month = 6; jun.day = 21; jun.hour = 12;
    NSDate *junNoon = [gc dateFromComponents:jun];
    FCSolarEvents polar = FCSolarEventsForLocation(junNoon, 89.0, 0.0);
    if (polar.valid) {
        failures++;
        fprintf(stderr, "FAIL %s: 89°N at June solstice should be polar day\n", __func__);
    }

    // Nil-date safety.
    FCSolarEvents nilEv = FCSolarEventsForLocation(nil, 40.0, -74.0);
    if (nilEv.valid) {
        failures++;
        fprintf(stderr, "FAIL %s: nil date should be invalid\n", __func__);
    }
}
