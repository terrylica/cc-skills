// Overlay width agreement + network telemetry arithmetic.
//
// Two things worth locking here. The width consensus decides the geometry of
// EVERY overlay rail, so a regression shows up as a visibly ragged stack rather
// than as a crash — the kind of bug that survives a long time unnoticed. And the
// throughput math has one genuinely subtle case (interface counters resetting
// on re-plug) that produces a spectacular wrong number rather than a small one.
//
// Shared `failures` linkage matches test_levers.h — defined in test_session.m.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_overlay_width_takes_widest_need(void);
void test_overlay_width_floors_at_clock_width(void);
void test_overlay_width_hidden_overlay_stops_widening(void);
void test_overlay_width_posts_change_notification(void);

void test_telemetry_rate_basic(void);
void test_telemetry_rate_survives_counter_reset(void);
void test_telemetry_rate_formatting(void);
void test_telemetry_signal_buckets(void);
void test_telemetry_padding_stabilises_field_width(void);

NS_ASSUME_NONNULL_END
