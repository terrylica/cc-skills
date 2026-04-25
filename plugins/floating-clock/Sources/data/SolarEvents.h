// v4 iter-250: pure-offline NOAA solar-position calculator.
//
// Returns sunrise / sunset / civil-twilight times for a given
// (latitude, longitude, date). Algorithm: Jean Meeus's "Astronomical
// Algorithms" (2nd ed. ch. 25/15) — accuracy ±1 minute for civil
// purposes. Used by FCSkyGlyphForDate to replace iter-114's hard-coded
// hour buckets with real solar-event boundaries.
//
// Polar regions: when the sun never rises or never sets at the given
// (lat, date), `valid` is set NO and times are NaN. Caller should fall
// back to the legacy hour-bucket dispatcher.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct FCSolarEvents {
    BOOL    valid;       // NO if polar day/night
    double  civilDawn;   // unix epoch seconds — sun at -6° before sunrise
    double  sunrise;     // unix epoch seconds — sun at -0.833° (geometric + refraction)
    double  sunset;      // unix epoch seconds — sun at -0.833°
    double  civilDusk;   // unix epoch seconds — sun at -6° after sunset
} FCSolarEvents;

// Computes sunrise/sunset/civil-twilight for the given UTC date at
// (lat, lon) in degrees. Date is interpreted as the local civil date
// at the given longitude (i.e. the calendar day the user sees).
FCSolarEvents FCSolarEventsForLocation(NSDate *date, double latDeg, double lonDeg);

NS_ASSUME_NONNULL_END
