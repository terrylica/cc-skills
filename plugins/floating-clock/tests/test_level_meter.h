// Level-meter math + device-rail model tests (2026-10-15). Foundation-only halves of the two new
// rails: dB mapping and peak-hold ballistics, the eighth-block bar, dock-state derivation, the
// status-file parser and the rail's segment composition (including the "job died mid-run" case).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_level_meter_db_mapping(void);
void test_level_meter_ballistics(void);
void test_level_meter_eighth_bar(void);
void test_device_rail_dock_state(void);
void test_device_rail_status_parse(void);
void test_device_rail_segments(void);
void test_device_rail_steps_and_badge(void);

NS_ASSUME_NONNULL_END
