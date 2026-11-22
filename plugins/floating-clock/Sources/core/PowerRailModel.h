// Power rail model (2026-11-15) — pure, AppKit-free, unit-tested (tests/test_power_rail.m).
//
// The power rail is one 20 pt rail: the Mac's battery on the left (BAT), Bluetooth on the right
// (BT: power, the shortcut tip, and each device with its battery). Everything here is arithmetic and
// formatting over values the readers (PowerRailReaders) already took from the system, so it can be
// tested with recorded dictionaries and no hardware.
//
// Sources, and why each (references read at pinned commits, 2026-11-15):
//   · Battery: IOPSCopyPowerSourcesInfo + the AppleSmartBattery registry entry, the chain Stats
//     (exelban/stats, MIT, Modules/Battery/readers.swift) uses; on Apple Silicon the full-charge
//     capacity is AppleRawMaxCapacity (MaxCapacity is a percentage there), with NominalChargeCapacity
//     and BatteryData.NominalChargeCapacity as fallbacks (newer macOS moved the key, stats#3392).
//     Amperage is a signed mA value the registry hands back as an unsigned 64-bit number.
//   · Accessory batteries (AirPods left, right and case, Magic devices): the accessory power sources
//     pmset -g accps reads (IOPSCopyPowerSourcesByType(kIOPSSourceForAccessories) in Apple's
//     IOPowerSourcesPrivate.h). Measured on this Mac: no entitlement needed, and an AirPods case is
//     reported over Bluetooth LE even while the buds are not connected to the Mac.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Battery

// The optional battery facts, each a separate "Show on Bar" item. The percentage and the state glyph
// are always shown. Stored by name (PowerRailBatteryFields), so a later field never shifts old ones.
typedef NS_OPTIONS(NSUInteger, FCBatteryField) {
    FCBatteryFieldTime    = 1 << 0,   // 1:05 to full / to empty
    FCBatteryFieldPower   = 1 << 1,   // +18W charging, -9.4W draining (voltage × current)
    FCBatteryFieldHealth  = 1 << 2,   // ♥92% full-charge capacity / design capacity
    FCBatteryFieldCycles  = 1 << 3,   // 236cy
    FCBatteryFieldAdapter = 1 << 4,   // AC 60W
    FCBatteryFieldTemp    = 1 << 5,   // 30°
};
NSArray<NSString *> *FCBatteryFieldIDs(void);                  // in bar order
NSString *FCBatteryFieldTitle(NSString *fieldID);              // menu title
FCBatteryField FCBatteryFieldForID(NSString *fieldID);         // 0 for an unknown id
FCBatteryField FCBatteryFieldsFromIDs(NSArray *_Nullable ids); // nil = every field

typedef NS_ENUM(NSInteger, FCBatteryState) {
    FCBatteryStateNone = 0,     // no internal battery (desktop Mac)
    FCBatteryStateDischarging,  // ▾ on battery
    FCBatteryStateCharging,     // ⚡
    FCBatteryStateHeld,         // ⏸ on AC, not charging, not full: a charge limit or optimized charging
    FCBatteryStateFull,         // ✓ on AC and full
};

@interface FCBatterySnapshot : NSObject
@property (nonatomic) BOOL present;
@property (nonatomic) NSInteger percent;          // 0-100
@property (nonatomic) BOOL onAC;
@property (nonatomic) BOOL charging;
@property (nonatomic) BOOL fullyCharged;
@property (nonatomic) NSInteger minutesToFull;    // -1 unknown or still being computed
@property (nonatomic) NSInteger minutesToEmpty;   // -1 unknown or still being computed
@property (nonatomic) NSInteger voltageMV;        // 0 unknown
@property (nonatomic) NSInteger amperageMA;       // signed: + into the battery, - out of it
@property (nonatomic) NSInteger adapterWatts;     // 0 unknown or none
@property (nonatomic, copy, nullable) NSString *adapterName;
@property (nonatomic) NSInteger designMAh;        // 0 unknown
@property (nonatomic) NSInteger fullMAh;          // full-charge capacity now, 0 unknown
@property (nonatomic) NSInteger currentMAh;       // 0 unknown
@property (nonatomic) NSInteger cycles;           // -1 unknown
@property (nonatomic) double temperatureC;        // NAN unknown
@property (nonatomic) BOOL optimizedChargingEngaged;
@property (nonatomic) NSInteger notChargingReason; // ChargerData.NotChargingReason, 0 = none

// Builds a snapshot from IOPSGetPowerSourceDescription's dictionary for the internal battery, the
// AppleSmartBattery registry properties, and IOPSCopyExternalPowerAdapterDetails (each may be nil).
+ (instancetype)snapshotFromPowerSource:(nullable NSDictionary *)ps
                           smartBattery:(nullable NSDictionary *)sb
                                adapter:(nullable NSDictionary *)adapter;
- (FCBatteryState)state;
- (double)watts;          // signed, voltage × current; 0 when either is unknown
- (double)healthPercent;  // fullMAh / designMAh × 100; -1 unknown
@end

// The registry stores a signed mA as an unsigned 64-bit value (18446744073709551551 = -65).
NSInteger FCSignedRegistryInteger(id _Nullable value);
// "1:05"; "" for a negative or absurd (>= 100 h) value.
NSString *FCBatteryMinutesLabel(NSInteger minutes);
// "+18W", "-9.4W", "0W": one decimal below 10 W.
NSString *FCSignedWattsLabel(double watts);

#pragma mark - Bluetooth devices

// One accessory power source part (pmset -g accps): a whole device, or one part of a group such as
// the AirPods' left bud, right bud and case.
@interface FCAccessoryPart : NSObject
@property (nonatomic, copy) NSString *name;       // "Owner’s AirPods Pro Case"
@property (nonatomic, copy) NSString *group;      // Group Identifier, or the name when there is none
@property (nonatomic, copy) NSString *part;       // "Left" "Right" "Case" "Combined" "Single" or ""
@property (nonatomic) NSInteger percent;
@property (nonatomic) BOOL charging;
// Parts from IOPSGetPowerSourceDescription dictionaries; a "Combined Parts" array is expanded into
// its own parts. Entries without a Current Capacity are dropped.
+ (NSArray<FCAccessoryPart *> *)partsFromDescriptions:(NSArray<NSDictionary *> *)descriptions;
@end

// One Bluetooth device as the rail shows it.
@interface FCBTDevice : NSObject
@property (nonatomic, copy) NSString *name;              // full Bluetooth name
@property (nonatomic, copy, nullable) NSString *address; // nil for a battery-only entry (no pairing seen)
@property (nonatomic) BOOL connected;
// Battery by part: @"L" @"R" @"C" (case) or @"" (one battery). Missing = not reported.
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *levels;
@property (nonatomic) BOOL charging;
@end

// "Owner’s AirPods Pro" -> "AirPods Pro"; "Owner’s Magic Trackpad" -> "Trackpad". Drops an owner's
// possessive prefix and a leading "Magic ", then caps the length at 16 with an ellipsis.
NSString *FCShortDeviceName(NSString *name);

// Merges what the readers found into the rail's device list:
//   · `paired`: every paired device as @[name, address, @(connected to this Mac)];
//   · `parts`: accessory battery parts; a group belongs to the paired device whose name its part's
//     name starts with ("Owner’s AirPods Pro Case" belongs to "Owner’s AirPods Pro");
//   · `hidLevels`: name -> percent from the HID battery service (Magic keyboard, mouse, trackpad).
// Shown: every connected device, plus a paired device that is not connected but reports a battery
// (an AirPods case seen over Bluetooth LE); a battery group matching no paired device is kept too,
// with no address. Connected devices first, then by name.
NSArray<FCBTDevice *> *FCMergeBluetoothDevices(NSArray<NSArray *> *paired,
                                              NSArray<FCAccessoryPart *> *parts,
                                              NSDictionary<NSString *, NSNumber *> *hidLevels);

#pragma mark - Rail segments

// Colour roles the view maps to its palette.
typedef NS_ENUM(NSInteger, FCPowerRole) {
    FCPowerRoleHeading = 0,  // BAT / BT
    FCPowerRoleText,
    FCPowerRoleDim,
    FCPowerRoleOK,
    FCPowerRoleWarn,
    FCPowerRoleError,
    FCPowerRoleName,         // a device name
    FCPowerRoleHint,         // the shortcut tip
};

// A segment is @[text, @(FCPowerRole), action-or-@""]. Actions: @"bt.power" (the power dot) and
// @"bt.device:<address>" (a device name, connect/disconnect). The battery side has no actions.
NSArray<NSArray *> *FCBatterySegments(FCBatterySnapshot *battery, FCBatteryField fields);
NSArray<NSArray *> *FCBluetoothSegments(BOOL known, BOOL poweredOn, NSString *_Nullable hint,
                                       NSArray<FCBTDevice *> *devices, NSUInteger maxDevices);

#pragma mark - Shortcut tips

// "ctrl+opt+shift+b" -> "⌃⌥⇧B": modifiers in the order macOS draws them, the key upper-cased, a few
// named keys as their symbols. nil or "" -> "".
NSString *FCChordGlyphs(NSString *_Nullable keys);

// The chord of the hotkey that runs this app with `args`, read from the hotkey registry file the
// Typeless bridge writes ({"v":1,"hotkeys":[{"id","keys","run":[argv...]}...]}): the first entry
// whose run[0] is a floating-clock binary and whose remaining argv contains `args` in order.
// Returns the keys string ("ctrl+opt+shift+b") or nil.
NSString *_Nullable FCHotkeyKeysForCommand(NSData *_Nullable registryJSON, NSArray<NSString *> *args);

NS_ASSUME_NONNULL_END
