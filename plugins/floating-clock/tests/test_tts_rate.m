// TTS-rate rail fixtures. See test_tts_rate.h for scope.
#import "test_tts_rate.h"
#import "../Sources/core/TTSRateHelpers.h"
#import <math.h>

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

#define CHECK_CLOSE(got, want, label)                                          \
    CHECK(fabs((got) - (want)) <= 1e-9, "%@: got %.4f want %.4f", label, (double)(got), (double)(want))

void test_tts_rate_clamp(void) {
    CHECK_CLOSE(FCTTSRateClamp(1.5), 1.5, @"in range passes through");
    CHECK_CLOSE(FCTTSRateClamp(0.5), 1.0, @"below the floor -> 1.0 (never slower than normal)");
    CHECK_CLOSE(FCTTSRateClamp(9.0), 3.0, @"above the ceiling -> 3.0");
    CHECK_CLOSE(FCTTSRateClamp(1.27), 1.25, @"snaps to the 0.05 grid");
    CHECK_CLOSE(FCTTSRateClamp(1.33), 1.35, @"snaps to the 0.05 grid (up)");
    // A NaN or infinity must never reach the rate file the reader parses.
    CHECK_CLOSE(FCTTSRateClamp(NAN), 1.0, @"NaN -> floor");
    CHECK_CLOSE(FCTTSRateClamp(INFINITY), 1.0, @"inf -> floor");
}

void test_tts_rate_track_mapping(void) {
    NSUInteger n = 0;
    const double *d = FCTTSRateDetents(&n);
    CHECK(n == 7, "seven detents, got %lu", (unsigned long)n);
    CHECK_CLOSE(d[0], 1.0, @"first detent is the floor");
    CHECK_CLOSE(d[n - 1], 3.0, @"last detent is the ceiling");
    // Every detent sits at an EVEN fraction of the track, and round-trips.
    for (NSUInteger i = 0; i < n; i++) {
        double f = (double)i / (double)(n - 1);
        CHECK_CLOSE(FCTTSFractionForRate(d[i]), f, ([NSString stringWithFormat:@"detent %lu fraction", (unsigned long)i]));
        CHECK_CLOSE(FCTTSRateForFraction(f), d[i], ([NSString stringWithFormat:@"fraction -> detent %lu", (unsigned long)i]));
    }
    CHECK_CLOSE(FCTTSRateForFraction(-1.0), 1.0, @"left of the track -> floor");
    CHECK_CLOSE(FCTTSRateForFraction(2.0), 3.0, @"right of the track -> ceiling");
    CHECK_CLOSE(FCTTSRateForFraction(NAN), 1.0, @"NaN fraction -> floor");
    // Between 2 and 2.5 (fraction 4/6..5/6) the mapping is linear.
    CHECK_CLOSE(FCTTSRateForFraction(4.5 / 6.0), 2.25, @"midway between 2 and 2.5");
}

void test_tts_rate_nearest_detent(void) {
    CHECK_CLOSE(FCTTSRateNearestDetent(1.1), 1.0, @"1.1 -> 1");
    CHECK_CLOSE(FCTTSRateNearestDetent(1.2), 1.25, @"1.2 -> 1.25");
    CHECK_CLOSE(FCTTSRateNearestDetent(2.2), 2.0, @"2.2 -> 2");
    CHECK_CLOSE(FCTTSRateNearestDetent(2.3), 2.5, @"2.3 -> 2.5");
    CHECK_CLOSE(FCTTSRateNearestDetent(5.0), 3.0, @"beyond -> 3");
}

void test_tts_rate_delta_and_label(void) {
    CHECK_CLOSE(FCTTSRateApplyDelta(1.0, -0.25), 1.0, @"cannot step below normal speed");
    CHECK_CLOSE(FCTTSRateApplyDelta(2.9, 0.25), 3.0, @"cannot step above 3x");
    CHECK_CLOSE(FCTTSRateApplyDelta(1.5, 0.05), 1.55, @"fine step");
    CHECK([FCTTSRateLabel(1.0) isEqualToString:@"1×"], "label 1x: %@", FCTTSRateLabel(1.0));
    CHECK([FCTTSRateLabel(1.5) isEqualToString:@"1.5×"], "label 1.5x: %@", FCTTSRateLabel(1.5));
    CHECK([FCTTSRateLabel(1.25) isEqualToString:@"1.25×"], "label 1.25x: %@", FCTTSRateLabel(1.25));
    CHECK([FCTTSRateLabel(2.05) isEqualToString:@"2.05×"], "label 2.05x: %@", FCTTSRateLabel(2.05));
}

void test_tts_rate_file_roundtrip(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"tts-rate-test-%d", getpid()]];
    NSString *path = [dir stringByAppendingPathComponent:@"nested/rate"];
    CHECK(isnan(FCTTSReadRateFile(path)), "missing file reads as NaN (caller treats as 1x)");
    CHECK(FCTTSWriteRateFile(path, 1.75), "write creates the directory");
    CHECK_CLOSE(FCTTSReadRateFile(path), 1.75, @"round trip");
    NSString *body = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    CHECK([body isEqualToString:@"1.75\n"], "file format is \"%%.2f\\n\" (what the reader parses): %@", body);
    CHECK(FCTTSWriteRateFile(path, 7.0), "out-of-range write succeeds");
    CHECK_CLOSE(FCTTSReadRateFile(path), 3.0, @"and is clamped on write");
    [@"fast\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CHECK(isnan(FCTTSReadRateFile(path)), "garbage reads as NaN, never as a number");
    [@"   \n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CHECK(isnan(FCTTSReadRateFile(path)), "blank reads as NaN");
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}
