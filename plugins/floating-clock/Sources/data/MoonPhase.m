#import "MoonPhase.h"
#include <math.h>

// Reference new moon: 2000-01-06 18:14:00 UTC
// Unix epoch seconds = 947182440 (computed via NSCalendar at build-out;
// hardcoding the constant makes the function pure + testable).
static const double kFCMoonRefEpochSecs = 947182440.0;
static const double kFCMoonSynodicSecs  = 29.530588853 * 86400.0;  // ≈ 2551442.8 s

double FCMoonPhaseFraction(NSDate *now) {
    if (!now) return 0.0;
    double t = [now timeIntervalSince1970];
    double sinceRef = t - kFCMoonRefEpochSecs;
    double cycles = sinceRef / kFCMoonSynodicSecs;
    double frac = cycles - floor(cycles);  // wrap to [0, 1)
    if (frac < 0) frac += 1.0;
    return frac;
}

NSString *FCMoonPhaseGlyph(NSDate *now) {
    double f = FCMoonPhaseFraction(now);
    if (f < 0.0625) return @"🌑";
    if (f < 0.1875) return @"🌒";
    if (f < 0.3125) return @"🌓";
    if (f < 0.4375) return @"🌔";
    if (f < 0.5625) return @"🌕";
    if (f < 0.6875) return @"🌖";
    if (f < 0.8125) return @"🌗";
    if (f < 0.9375) return @"🌘";
    return @"🌑";
}
