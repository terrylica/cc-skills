// Audio HAL reader tests (2026-10-21, cc-skills#37). FCAudioHALReader is driven with fake read and
// write blocks, so coalescing, write ordering, stale-read suppression and the overdue clock are
// checked without touching real audio hardware.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_audio_hal_reader_coalesces_reads(void);
void test_audio_hal_reader_write_then_read_order(void);
void test_audio_hal_reader_drops_read_started_before_write(void);
void test_audio_hal_reader_seconds_in_flight(void);
void test_audio_hal_snapshot_optimistic_default(void);

NS_ASSUME_NONNULL_END
