// v4 iter-114: `FCSkyGlyphForHour` — pure hour-of-day → emoji dispatcher.
//
// Extracted from Runtime.m inline so a test can lock the 5-phase
// bucket boundaries (iter-112) for each hour [0, 23].
//
// Returns a single-character NSString with the phase glyph:
//   [ 5,  7)  🌅  dawn / sunrise
//   [ 7, 17)  ☀️   day
//   [17, 19)  🌇  dusk / sunset
//   [19,  5)  🌙  night  (includes [0, 5))
// Hours outside [0, 23] fall back to night.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *FCSkyGlyphForHour(NSInteger hour);

// v4 iter-250: solar-event aware dispatcher. Computes sunrise/sunset
// + civil twilight at (lat, lon) for `now`'s date and returns:
//   now < civilDawn  || now >= civilDusk  → 🌙 night
//   civilDawn <= now < sunrise            → 🌅 dawn
//   sunrise <= now < sunset               → ☀️ day
//   sunset <= now < civilDusk             → 🌇 dusk
// Falls back to FCSkyGlyphForHour at polar latitudes (sun never
// rises/sets for the date) so the glyph never disappears.
NSString *FCSkyGlyphForDate(NSDate *now, double latDeg, double lonDeg);

NS_ASSUME_NONNULL_END
