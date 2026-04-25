#import "SkyGlyph.h"
#import "../data/SolarEvents.h"

NSString *FCSkyGlyphForHour(NSInteger hour) {
    if (hour >= 5  && hour < 7)  return @"\U0001F305";  // 🌅 sunrise / dawn
    if (hour >= 7  && hour < 17) return @"☀️";            // day
    if (hour >= 17 && hour < 19) return @"\U0001F307";  // 🌇 sunset / dusk
    return @"\U0001F319";                               // 🌙 night (includes < 5 and >= 19)
}

NSString *FCSkyGlyphForDate(NSDate *now, double latDeg, double lonDeg) {
    if (!now) return @"\U0001F319";  // 🌙
    FCSolarEvents ev = FCSolarEventsForLocation(now, latDeg, lonDeg);
    if (!ev.valid) {
        // Polar regions: fall back to the user's local-clock hour bucket.
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSInteger h = [cal component:NSCalendarUnitHour fromDate:now];
        return FCSkyGlyphForHour(h);
    }
    double t = [now timeIntervalSince1970];
    if (t < ev.civilDawn || t >= ev.civilDusk) return @"\U0001F319";  // 🌙 night
    if (t < ev.sunrise)                        return @"\U0001F305";  // 🌅 dawn
    if (t < ev.sunset)                         return @"☀️";           // day
    return @"\U0001F307";                                              // 🌇 dusk
}
