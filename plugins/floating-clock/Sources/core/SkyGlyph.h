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

NS_ASSUME_NONNULL_END
