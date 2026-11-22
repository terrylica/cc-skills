// Power rail readers (2026-11-15) — the system-facing half of the BAT | BT rail. Every read is in
// process and needs no subprocess; the pure half (parsing, merging, segments) is PowerRailModel.
//
//   · Battery: IOPSCopyPowerSourcesInfo, IOPSCopyExternalPowerAdapterDetails, and the
//     AppleSmartBattery registry entry. No permission.
//   · Accessory batteries: IOPSCopyPowerSourcesByType(kIOPSSourceForAccessories), resolved with
//     dlsym from IOKit (declared in Apple's IOPowerSourcesPrivate.h; pmset -g accps is built on it).
//     A missing symbol means no accessory batteries, never a failed launch. No entitlement needed
//     (measured 2026-11-15, macOS 26).
//   · HID batteries (Magic keyboard, mouse, trackpad): AppleDeviceManagementHIDEventService's
//     BatteryPercent, matched by class (Stats' approach), never a walk of the whole registry.
//   · Bluetooth devices and their link: IOBluetooth's pairedDevices, plus the private
//     batteryPercentLeft/Right/Case/Single properties (guarded by respondsToSelector:; Hammerspoon and
//     fastfetch read the same ones). Needs the Bluetooth permission the app already asks for.
//   · Bluetooth power: IOBluetoothPreferenceGetControllerPowerState / SetControllerPowerState, the
//     private pair blueutil (MIT) and Bluesnooze use; the setter is followed by polling the getter,
//     as blueutil does, because the switch takes a moment.
//
// Change notifications: IOPSNotificationCreateRunLoopSource (battery percent and time) and
// IOPSAccNotificationCreateRunLoopSource (accessory batteries) call `onChange` on the main run loop,
// so the rail updates when something changes rather than on a fast poll.
#import <Foundation/Foundation.h>
#import "PowerRailModel.h"

NS_ASSUME_NONNULL_BEGIN

FCBatterySnapshot *FCReadBatterySnapshot(void);
NSArray<FCAccessoryPart *> *FCReadAccessoryParts(void);
NSDictionary<NSString *, NSNumber *> *FCReadHIDBatteryLevels(void);

// Every paired device as @[name, address, @(connected)]. Battery levels IOBluetooth itself reports
// for connected devices are appended to `parts` (group = address), so the merge sees them.
NSArray<NSArray *> *FCReadPairedBluetoothDevices(NSMutableArray<FCAccessoryPart *> *parts);

// 1 on, 0 off, -1 the symbol is missing.
int FCReadBluetoothPower(void);
// Switch the controller on or off off the main thread, then wait (up to 10 s) for it to report the
// new state. `completion` runs on the main queue with whether it got there.
void FCSetBluetoothPower(BOOL on, void (^completion)(BOOL reached));
// Close this Mac's link to a connected device. Main queue.
BOOL FCDisconnectBluetoothDevice(NSString *address);

// Calls `onChange` on the main run loop when the battery or an accessory battery changes.
@interface FCPowerChangeObserver : NSObject
- (instancetype)initWithHandler:(void (^)(void))onChange;
@end

NS_ASSUME_NONNULL_END
