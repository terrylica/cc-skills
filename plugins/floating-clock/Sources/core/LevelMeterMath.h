// Level-meter math (2026-10-15) — pure C, AppKit-free, unit-tested (test_level_meter).
//
// Ballistics follow the peak-programme-meter convention: instant attack, a fixed dB/s release,
// and a peak marker that holds ~1 s before falling. Range is -60..0 dBFS, which is what a
// meter a few pixels wide can resolve anyway.
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

static const double FCMeterFloorDb      = -60.0;
static const double FCMeterReleaseDbPS  = 24.0;   // bar fall speed
static const double FCMeterPeakHoldSecs = 1.0;    // peak marker hold before it falls

typedef struct {
    double levelDb;    // displayed bar level
    double peakDb;     // peak-hold marker
    double holdLeft;   // seconds the marker still holds
} FCMeterState;

// Linear amplitude (0..1) -> dBFS, floored at FCMeterFloorDb (silence and NaN map to the floor).
double FCLinearToDb(double amplitude);
// dBFS -> 0..1 fraction of the meter length.
double FCDbToFraction(double db);
// Advance the ballistics by dt seconds with a new instantaneous level.
void FCMeterStep(FCMeterState *s, double inputDb, double dt);
// Reset to silence.
void FCMeterReset(FCMeterState *s);

// Text progress bar with 1/8-cell resolution ("█▉▊▋▌▍▎▏"), padded with `empty` to `cells`.
// Same glyph family as the clock's market-session progress bar.
NSString *FCEighthBlockBar(double fraction, NSUInteger cells, NSString *empty);

#ifdef __cplusplus
}
#endif
