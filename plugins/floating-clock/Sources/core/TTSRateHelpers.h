// TTS-rate rail arithmetic (Foundation only, unit-tested in tests/test_tts_rate.m).
//
// The rail sets the PLAYBACK RATE of a text-to-speech reader that follows a
// one-line rate file (e.g. "1.50"): 1.0 is the reader's normal speed and the
// floor, 3.0 the ceiling. The reader re-reads the file while it speaks, so a
// change applies mid-sentence. The rail never talks to the reader directly —
// the file is the whole contract, and it is also the persisted setting.
//
// Track geometry: the seven detents (1, 1.25, 1.5, 1.75, 2, 2.5, 3) sit at
// EVEN spacing along the track, so the mapping between track fraction and rate
// is piecewise-linear between neighbouring detents. A drag snaps to the nearest
// detent; −/+ step 0.25 and scroll steps 0.05 reach the values in between.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const double FCTTSRateMin;     // 1.0 — today's speed; never slower
extern const double FCTTSRateMax;     // 3.0
extern const double FCTTSRateStep;    // 0.25 — −/+
extern const double FCTTSRateFine;    // 0.05 — scroll

/// The detents, ascending. `count` receives the number of entries.
const double *FCTTSRateDetents(NSUInteger *count);

/// Clamp to [Min, Max] and round to the 0.05 grid. NaN/inf become Min.
double FCTTSRateClamp(double rate);

/// Rate at a track fraction 0..1 (piecewise-linear between evenly spaced detents).
double FCTTSRateForFraction(double fraction);

/// Track fraction 0..1 for a rate (inverse of the above).
double FCTTSFractionForRate(double rate);

/// The detent nearest to `rate`.
double FCTTSRateNearestDetent(double rate);

/// rate + delta, clamped and gridded.
double FCTTSRateApplyDelta(double rate, double delta);

/// "1×", "1.25×", "1.5×", "2.05×" — no trailing zeros.
NSString *FCTTSRateLabel(double rate);

/// The rate in the file at `path`, clamped; NAN when missing, empty or unparsable.
double FCTTSReadRateFile(NSString *path);

/// Write `rate` (clamped, "%.2f\n") atomically, creating the directory. YES on success.
BOOL FCTTSWriteRateFile(NSString *path, double rate);

/// The configured rate-file path (TTSRateFile default, "~" expanded).
NSString *FCTTSRateFilePath(void);

NS_ASSUME_NONNULL_END
