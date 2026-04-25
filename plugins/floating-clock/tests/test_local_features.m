#import "test_local_features.h"
#import "../Sources/content/WeekProgressBar.h"
#import "../Sources/data/MoonPhase.h"

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
