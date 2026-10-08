// TTS-rate rail arithmetic tests (2026-10-08). Covers TTSRateHelpers only, the
// Foundation half; the indicator and zone view are AppKit and excluded from the
// test link. What matters most: the floor (never below 1x, NaN never escapes to
// the reader), the evenly spaced detents round-tripping through the track, and
// the rate-file format the reader parses.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_tts_rate_clamp(void);
void test_tts_rate_track_mapping(void);
void test_tts_rate_nearest_detent(void);
void test_tts_rate_delta_and_label(void);
void test_tts_rate_file_roundtrip(void);

NS_ASSUME_NONNULL_END
