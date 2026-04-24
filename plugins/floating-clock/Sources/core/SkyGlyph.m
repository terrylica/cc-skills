#import "SkyGlyph.h"

NSString *FCSkyGlyphForHour(NSInteger hour) {
    if (hour >= 5  && hour < 7)  return @"\U0001F305";  // 🌅 sunrise / dawn
    if (hour >= 7  && hour < 17) return @"☀️";            // day
    if (hour >= 17 && hour < 19) return @"\U0001F307";  // 🌇 sunset / dusk
    return @"\U0001F319";                               // 🌙 night (includes < 5 and >= 19)
}
