#import "SolarEvents.h"
#import <math.h>

static const double kDeg2Rad = M_PI / 180.0;
static const double kRad2Deg = 180.0 / M_PI;

// Pure-offline solar-position calculator. Algorithm from SunCalc
// (https://github.com/mourner/suncalc) which itself derives from Jean
// Meeus's "Astronomical Algorithms" ch. 25/15. Accuracy ±1 minute for
// civil purposes — adequate for a desktop-clock dawn/dusk glyph.
static double fcJulianDayFromUnix(double unixSecs) {
    return (unixSecs / 86400.0) + 2440587.5;
}

static double fcUnixFromJulianDay(double jd) {
    return (jd - 2440587.5) * 86400.0;
}

// Hour angle (radians) at which the sun reaches altitude `h0Rad`.
// h0Rad is typically -0.833° (sunrise/sunset, accounting for solar
// disk radius + atmospheric refraction) or -6° (civil twilight).
// Returns NAN at polar latitudes where the sun never reaches that
// altitude.
static double fcHourAngle(double h0Rad, double latRad, double declRad) {
    double cosOmega = (sin(h0Rad) - sin(latRad) * sin(declRad))
                    / (cos(latRad) * cos(declRad));
    if (cosOmega < -1.0 || cosOmega > 1.0) return NAN;  // polar day/night
    return acos(cosOmega);
}

FCSolarEvents FCSolarEventsForLocation(NSDate *date, double latDeg, double lonDeg) {
    FCSolarEvents out = (FCSolarEvents){ .valid = NO, .civilDawn = NAN,
                                          .sunrise = NAN, .sunset = NAN,
                                          .civilDusk = NAN };
    if (!date) return out;

    // SunCalc style: west-longitude positive (lw = -lonDeg).
    double lwRad = -lonDeg * kDeg2Rad;
    double latRad = latDeg * kDeg2Rad;

    double jd = fcJulianDayFromUnix([date timeIntervalSince1970]);
    double d = jd - 2451545.0;        // days since J2000.0

    // Julian cycle — integer count of solar transits since J2000 at
    // this longitude. Round to nearest integer so we land on the local
    // solar noon CLOSEST to the input `date` (in either direction). This
    // is the key fix vs. ceil() which always picks the *next* noon and
    // breaks for "evening Pacific time = next-day early-UTC" cases.
    double n = round(d - 0.0009 - lwRad / (2.0 * M_PI));

    // Approximate solar transit (days since J2000). The +lw/(2π) term
    // shifts the integer day index n into local-solar time at this
    // longitude, so adding 2451545 + corrections lands at local noon.
    double ds = 0.0009 + lwRad / (2.0 * M_PI) + n;

    // Solar mean anomaly (radians).
    double Mrad = (357.5291 + 0.98560028 * ds) * kDeg2Rad;
    double M = Mrad * kRad2Deg;

    // Equation of the center.
    double C = 1.9148 * sin(Mrad) + 0.0200 * sin(2.0 * Mrad) + 0.0003 * sin(3.0 * Mrad);

    // Ecliptic longitude.
    double lambdaDeg = fmod(M + C + 180.0 + 102.9372, 360.0);
    if (lambdaDeg < 0) lambdaDeg += 360.0;
    double lambdaRad = lambdaDeg * kDeg2Rad;

    // Solar transit (Julian date of local solar noon at this longitude).
    double Jtransit = 2451545.0 + ds + 0.0053 * sin(Mrad) - 0.0069 * sin(2.0 * lambdaRad);

    // Solar declination.
    double declRad = asin(sin(lambdaRad) * sin(23.4397 * kDeg2Rad));

    double omegaSun   = fcHourAngle(-0.833 * kDeg2Rad, latRad, declRad);
    double omegaCivil = fcHourAngle(-6.0   * kDeg2Rad, latRad, declRad);

    if (isnan(omegaSun)) return out;  // polar day or polar night

    // Hour-angle in radians → fraction of a day = ω / (2π).
    double Jsunrise = Jtransit - omegaSun / (2.0 * M_PI);
    double Jsunset  = Jtransit + omegaSun / (2.0 * M_PI);

    out.sunrise = fcUnixFromJulianDay(Jsunrise);
    out.sunset  = fcUnixFromJulianDay(Jsunset);

    if (!isnan(omegaCivil)) {
        out.civilDawn = fcUnixFromJulianDay(Jtransit - omegaCivil / (2.0 * M_PI));
        out.civilDusk = fcUnixFromJulianDay(Jtransit + omegaCivil / (2.0 * M_PI));
    } else {
        // Civil-twilight band undefined → collapse dawn/dusk windows.
        out.civilDawn = out.sunrise;
        out.civilDusk = out.sunset;
    }
    out.valid = YES;
    return out;
}
