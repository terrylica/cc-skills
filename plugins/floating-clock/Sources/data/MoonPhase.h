// v4 iter-243: pure-offline moon-phase calculation.
//
// User asked for "movements of the Earth, Moon, Sun, and Universe"
// granular coloring. Moon phase is the easiest to ship purely
// offline — no lat/lon, no network needed, just synodic-month math
// from a known new-moon epoch.
//
// Algorithm: standard astronomy.
//   1. Known new moon: 2000-01-06 18:14:00 UTC (Julian Day 2451550.26)
//   2. Synodic month: 29.530588853 days (mean lunar cycle)
//   3. Days since epoch / synodic = fractional cycle position [0..1)
//   4. Map fraction → one of 8 moon-phase glyphs:
//      0.000 → 0.0625  🌑 new
//      0.0625 → 0.1875 🌒 waxing crescent
//      0.1875 → 0.3125 🌓 first quarter
//      0.3125 → 0.4375 🌔 waxing gibbous
//      0.4375 → 0.5625 🌕 full
//      0.5625 → 0.6875 🌖 waning gibbous
//      0.6875 → 0.8125 🌗 third quarter
//      0.8125 → 0.9375 🌘 waning crescent
//      0.9375 → 1.000  🌑 new
//
// Accuracy: ±~6h vs ephemerides. Fine for a glyph indicator.
// For sub-day precision (e.g. exact full-moon timing), would need
// proper lunar perturbation model — out of scope.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// 8-phase glyph for the given date. nil → 🌑 (new moon fallback).
NSString *FCMoonPhaseGlyph(NSDate * _Nullable now);

// Fractional cycle position [0..1). 0 = new, 0.5 = full. nil → 0.
double FCMoonPhaseFraction(NSDate * _Nullable now);

NS_ASSUME_NONNULL_END
