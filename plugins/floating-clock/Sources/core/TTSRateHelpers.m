#import "TTSRateHelpers.h"
#import <math.h>

const double FCTTSRateMin  = 1.0;
const double FCTTSRateMax  = 3.0;
const double FCTTSRateStep = 0.25;
const double FCTTSRateFine = 0.05;

static const double kDetents[] = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0};
static const NSUInteger kDetentCount = sizeof(kDetents) / sizeof(kDetents[0]);

const double *FCTTSRateDetents(NSUInteger *count) {
    if (count) *count = kDetentCount;
    return kDetents;
}

double FCTTSRateClamp(double rate) {
    if (!isfinite(rate)) return FCTTSRateMin;
    double r = round(rate / FCTTSRateFine) * FCTTSRateFine;   // 0.05 grid
    if (r < FCTTSRateMin) r = FCTTSRateMin;
    if (r > FCTTSRateMax) r = FCTTSRateMax;
    return round(r * 100.0) / 100.0;   // shed binary noise so equality and labels behave
}

double FCTTSRateForFraction(double fraction) {
    if (!isfinite(fraction) || fraction <= 0.0) return kDetents[0];
    if (fraction >= 1.0) return kDetents[kDetentCount - 1];
    double pos = fraction * (double)(kDetentCount - 1);
    NSUInteger i = (NSUInteger)floor(pos);
    double t = pos - (double)i;
    return kDetents[i] + t * (kDetents[i + 1] - kDetents[i]);
}

double FCTTSFractionForRate(double rate) {
    if (!isfinite(rate) || rate <= kDetents[0]) return 0.0;
    if (rate >= kDetents[kDetentCount - 1]) return 1.0;
    for (NSUInteger i = 0; i + 1 < kDetentCount; i++) {
        if (rate <= kDetents[i + 1]) {
            double t = (rate - kDetents[i]) / (kDetents[i + 1] - kDetents[i]);
            return ((double)i + t) / (double)(kDetentCount - 1);
        }
    }
    return 1.0;
}

double FCTTSRateNearestDetent(double rate) {
    double best = kDetents[0], bestD = INFINITY;
    for (NSUInteger i = 0; i < kDetentCount; i++) {
        double d = fabs(kDetents[i] - rate);
        if (d < bestD) { bestD = d; best = kDetents[i]; }
    }
    return best;
}

double FCTTSRateApplyDelta(double rate, double delta) {
    return FCTTSRateClamp(rate + delta);
}

NSString *FCTTSRateLabel(double rate) {
    double r = FCTTSRateClamp(rate);
    NSString *s = [NSString stringWithFormat:@"%.2f", r];
    while ([s hasSuffix:@"0"]) s = [s substringToIndex:s.length - 1];
    if ([s hasSuffix:@"."]) s = [s substringToIndex:s.length - 1];
    return [s stringByAppendingString:@"×"];
}

double FCTTSReadRateFile(NSString *path) {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!s) return NAN;
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return NAN;
    NSScanner *sc = [NSScanner scannerWithString:t];
    double v;
    if (![sc scanDouble:&v] || !sc.isAtEnd) return NAN;
    return FCTTSRateClamp(v);
}

BOOL FCTTSWriteRateFile(NSString *path, double rate) {
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                    attributes:nil error:NULL]) return NO;
    NSString *body = [NSString stringWithFormat:@"%.2f\n", FCTTSRateClamp(rate)];
    // atomically: the reader polls the file, and must never read a half-written number.
    return [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

NSString *FCTTSRateFilePath(void) {
    NSString *p = [[NSUserDefaults standardUserDefaults] stringForKey:@"TTSRateFile"];
    if (p.length == 0) p = @"~/.config/floating-clock/tts-rate";
    return [p stringByExpandingTildeInPath];
}
