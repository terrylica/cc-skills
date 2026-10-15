#import "LevelMeterMath.h"
#include <math.h>

double FCLinearToDb(double amplitude) {
    if (!(amplitude > 0.0)) return FCMeterFloorDb;   // also catches NaN
    double db = 20.0 * log10(amplitude);
    if (db < FCMeterFloorDb) return FCMeterFloorDb;
    if (db > 0.0) return 0.0;
    return db;
}

double FCDbToFraction(double db) {
    if (!(db > FCMeterFloorDb)) return 0.0;
    if (db >= 0.0) return 1.0;
    return (db - FCMeterFloorDb) / -FCMeterFloorDb;
}

void FCMeterReset(FCMeterState *s) {
    s->levelDb = FCMeterFloorDb;
    s->peakDb = FCMeterFloorDb;
    s->holdLeft = 0.0;
}

void FCMeterStep(FCMeterState *s, double inputDb, double dt) {
    if (dt < 0.0) dt = 0.0;
    if (!(inputDb > FCMeterFloorDb)) inputDb = FCMeterFloorDb;
    double fallen = s->levelDb - FCMeterReleaseDbPS * dt;
    s->levelDb = inputDb > fallen ? inputDb : fallen;            // instant attack, linear-dB release
    if (s->levelDb < FCMeterFloorDb) s->levelDb = FCMeterFloorDb;

    if (inputDb >= s->peakDb) {
        s->peakDb = inputDb;
        s->holdLeft = FCMeterPeakHoldSecs;
    } else if (s->holdLeft > 0.0) {
        s->holdLeft -= dt;
    } else {
        s->peakDb -= FCMeterReleaseDbPS * dt;
    }
    if (s->peakDb < s->levelDb) s->peakDb = s->levelDb;          // marker never sits below the bar
}

NSString *FCEighthBlockBar(double fraction, NSUInteger cells, NSString *empty) {
    static NSString *const partial[8] = { @"", @"▏", @"▎", @"▍", @"▌", @"▋", @"▊", @"▉" };
    if (!(fraction > 0.0)) fraction = 0.0;
    if (fraction > 1.0) fraction = 1.0;
    NSUInteger eighths = (NSUInteger)llround(fraction * (double)cells * 8.0);
    NSUInteger full = eighths / 8, rem = eighths % 8;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < full && i < cells; i++) [s appendString:@"█"];
    NSUInteger used = full;
    if (rem && used < cells) { [s appendString:partial[rem]]; used++; }
    for (; used < cells; used++) [s appendString:empty ?: @" "];
    return s;
}
