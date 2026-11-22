// Power rail model tests (2026-11-15). The Foundation-only half of the BAT | BT rail: battery
// snapshot parsing from recorded IOPS and AppleSmartBattery dictionaries (including the signed
// amperage the registry stores unsigned), the optional bar fields, accessory battery parts and their
// merge onto paired Bluetooth devices, the rail's segments and click actions, and the shortcut tip
// read from the Typeless bridge's hotkey registry file.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_power_battery_snapshot(void);
void test_power_battery_states(void);
void test_power_battery_segments_and_fields(void);
void test_power_accessory_parts_and_merge(void);
void test_power_bluetooth_segments(void);
void test_power_chord_glyphs_and_registry(void);

NS_ASSUME_NONNULL_END
