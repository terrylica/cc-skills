// Power rail model fixtures. See test_power_rail.h for scope.
#import "test_power_rail.h"
#import "../Sources/core/PowerRailModel.h"
#import <math.h>

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

static NSString *FCJoinPower(NSArray<NSArray *> *segs) {
    NSMutableString *s = [NSMutableString string];
    for (NSArray *seg in segs) [s appendString:seg[0]];
    return s;
}

static NSString *FCActionFor(NSArray<NSArray *> *segs, NSString *text) {
    for (NSArray *seg in segs) if ([seg[0] isEqualToString:text]) return seg[2];
    return nil;
}

// Recorded on an Apple Silicon MacBook Pro on AC, held at about 80% by the charge limit
// (2026-11-15): pmset said "79%; AC attached; not charging".
static NSDictionary *FCHeldPS(void) {
    return @{ @"Current Capacity": @79, @"Max Capacity": @100, @"Power Source State": @"AC Power",
              @"Is Charging": @NO, @"Is Charged": @NO, @"Time to Full Charge": @0, @"Time to Empty": @0,
              @"Is Present": @YES };
}
static NSDictionary *FCHeldSB(void) {
    return @{ @"CurrentCapacity": @79, @"CycleCount": @236, @"DesignCapacity": @8579, @"AppleRawMaxCapacity": @7879,
              @"AppleRawCurrentCapacity": @5899, @"Voltage": @12134,
              @"Amperage": [NSNumber numberWithUnsignedLongLong:18446744073709551551ULL],
              @"Temperature": @3003, @"AvgTimeToFull": @65535, @"AvgTimeToEmpty": @11417,
              @"ExternalConnected": @YES, @"IsCharging": @NO, @"FullyCharged": @NO,
              @"AdapterDetails": @{ @"Watts": @60 } };
}

void test_power_battery_snapshot(void) {
    CHECK(FCSignedRegistryInteger([NSNumber numberWithUnsignedLongLong:18446744073709551551ULL]) == -65, "unsigned -> -65");
    CHECK(FCSignedRegistryInteger(@(-65)) == -65, "signed stays -65");
    CHECK(FCSignedRegistryInteger(@"x") == 0, "non-number -> 0");

    FCBatterySnapshot *b = [FCBatterySnapshot snapshotFromPowerSource:FCHeldPS() smartBattery:FCHeldSB() adapter:nil];
    CHECK(b.present && b.percent == 79 && b.onAC && !b.charging, "basic state");
    CHECK(b.amperageMA == -65 && b.voltageMV == 12134, "amperage %ld", (long)b.amperageMA);
    CHECK(fabs([b watts] - (-0.78871)) < 0.001, "watts %f", [b watts]);
    CHECK(fabs([b healthPercent] - 91.84) < 0.01, "health %f", [b healthPercent]);
    CHECK(b.cycles == 236 && fabs(b.temperatureC - 30.03) < 0.001, "cycles/temp");
    CHECK(b.adapterWatts == 60, "adapter watts from AdapterDetails");
    CHECK(b.minutesToFull == 0 && b.minutesToEmpty == 0, "IOPS minutes win over the registry averages");

    // Newer macOS: the full-charge capacity lives only inside BatteryData (stats#3392).
    NSMutableDictionary *sb = [FCHeldSB() mutableCopy];
    [sb removeObjectForKey:@"AppleRawMaxCapacity"];
    sb[@"BatteryData"] = @{ @"NominalChargeCapacity": @8000 };
    FCBatterySnapshot *nb = [FCBatterySnapshot snapshotFromPowerSource:FCHeldPS() smartBattery:sb adapter:nil];
    CHECK(nb.fullMAh == 8000, "BatteryData fallback %ld", (long)nb.fullMAh);

    // Registry only (no power source): 65535 is "no estimate"; an explicit adapter dictionary wins.
    FCBatterySnapshot *rb = [FCBatterySnapshot snapshotFromPowerSource:nil smartBattery:FCHeldSB() adapter:@{ @"Watts": @96, @"Name": @"96W USB-C" }];
    CHECK(rb.percent == 79 && rb.minutesToFull == -1 && rb.minutesToEmpty == 11417, "registry fallback");
    CHECK(rb.adapterWatts == 96 && [rb.adapterName isEqualToString:@"96W USB-C"], "adapter dict wins");

    FCBatterySnapshot *none = [FCBatterySnapshot snapshotFromPowerSource:nil smartBattery:nil adapter:nil];
    CHECK(!none.present && [none state] == FCBatteryStateNone, "desktop Mac: no battery");
}

void test_power_battery_states(void) {
    FCBatterySnapshot *b = [FCBatterySnapshot snapshotFromPowerSource:FCHeldPS() smartBattery:FCHeldSB() adapter:nil];
    CHECK([b state] == FCBatteryStateHeld, "on AC, not charging, below 100 -> held");
    b.charging = YES;
    CHECK([b state] == FCBatteryStateCharging, "charging");
    b.charging = NO; b.percent = 100;
    CHECK([b state] == FCBatteryStateFull, "full");
    b.onAC = NO;
    CHECK([b state] == FCBatteryStateDischarging, "on battery");
    CHECK([FCBatteryMinutesLabel(65) isEqualToString:@"1:05"], "1:05");
    CHECK([FCBatteryMinutesLabel(-1) isEqualToString:@""] && [FCBatteryMinutesLabel(6000) isEqualToString:@""], "unknown/absurd");
    CHECK([FCSignedWattsLabel(18.2) isEqualToString:@"+18W"], "%@", FCSignedWattsLabel(18.2));
    CHECK([FCSignedWattsLabel(-9.44) isEqualToString:@"-9.4W"], "%@", FCSignedWattsLabel(-9.44));
    CHECK([FCSignedWattsLabel(0.01) isEqualToString:@"0W"], "near zero");
}

void test_power_battery_segments_and_fields(void) {
    FCBatterySnapshot *b = [FCBatterySnapshot snapshotFromPowerSource:FCHeldPS() smartBattery:FCHeldSB() adapter:nil];
    NSString *all = FCJoinPower(FCBatterySegments(b, FCBatteryFieldsFromIDs(nil)));
    CHECK([all isEqualToString:@"BAT 79% ⏸ -0.8W AC 60W ♥92% 236cy 30°"], "every field, held: %@", all);
    NSString *bare = FCJoinPower(FCBatterySegments(b, 0));
    CHECK([bare isEqualToString:@"BAT 79% ⏸"], "no optional field: %@", bare);
    CHECK(FCBatteryFieldsFromIDs(@[ @"health", @"nonsense", @7 ]) == FCBatteryFieldHealth, "unknown ids ignored");
    CHECK(FCBatteryFieldsFromIDs(@[]) == 0, "empty list = nothing optional");
    CHECK(FCBatteryFieldIDs().count == 6 && FCBatteryFieldTitle(@"temp").length, "six fields with titles");

    b.onAC = NO; b.percent = 15; b.minutesToEmpty = 42; b.amperageMA = -780;
    NSArray *segs = FCBatterySegments(b, FCBatteryFieldTime | FCBatteryFieldPower | FCBatteryFieldAdapter);
    NSString *drain = FCJoinPower(segs);
    CHECK([drain isEqualToString:@"BAT 15% ▾ 0:42 -9.5W"], "draining, no adapter on battery: %@", drain);
    CHECK([segs[1][1] integerValue] == FCPowerRoleWarn, "15%% draining is a warning");
    b.onAC = YES; b.charging = YES; b.minutesToFull = 70;
    NSArray *chg = FCBatterySegments(b, FCBatteryFieldTime);
    CHECK([FCJoinPower(chg) isEqualToString:@"BAT 15% ⚡ 1:10"], "charging shows time to full: %@", FCJoinPower(chg));
    CHECK([chg[1][1] integerValue] == FCPowerRoleText, "low but charging is not a warning");
    for (NSArray *seg in FCBatterySegments(b, FCBatteryFieldsFromIDs(nil))) CHECK([seg[2] length] == 0, "battery side has no actions");
}

void test_power_accessory_parts_and_merge(void) {
    // The case alone, as measured while the buds were not connected to the Mac.
    NSDictionary *caseOnly = @{ @"Name": @"Owner’s AirPods Pro Case", @"Part Identifier": @"Case", @"Current Capacity": @78,
                                @"Max Capacity": @100, @"Group Identifier": @"G1", @"Is Charging": @NO };
    NSDictionary *combined = @{ @"Name": @"Owner’s AirPods Pro", @"Part Identifier": @"Combined", @"Group Identifier": @"G1",
                                @"Current Capacity": @80,
                                @"Combined Parts": @[ @{ @"Part Identifier": @"Left", @"Current Capacity": @82 },
                                                      @{ @"Part Identifier": @"Right", @"Current Capacity": @80, @"Is Charging": @YES } ] };
    NSArray *mixed = @[ caseOnly, combined, @{ @"Name": @"no level" }, (id)@"junk" ];   // junk must be skipped, not crash
    NSArray *parts = [FCAccessoryPart partsFromDescriptions:mixed];
    CHECK(parts.count == 3, "case + left + right, junk dropped: %lu", (unsigned long)parts.count);

    NSArray *paired = @[ @[ @"Owner’s AirPods Pro", @"aa-bb", @YES ], @[ @"Owner’s Magic Trackpad", @"cc-dd", @YES ],
                         @[ @"Office Speaker", @"ee-ff", @NO ] ];
    NSArray<FCBTDevice *> *devs = FCMergeBluetoothDevices(paired, parts, @{ @"Owner’s Magic Trackpad": @64 });
    CHECK(devs.count == 2, "the speaker is neither connected nor reporting: %lu", (unsigned long)devs.count);
    FCBTDevice *pods = devs[0];
    CHECK([pods.name isEqualToString:@"Owner’s AirPods Pro"] && [pods.levels[@"L"] integerValue] == 82
          && [pods.levels[@"R"] integerValue] == 80 && [pods.levels[@"C"] integerValue] == 78 && pods.charging, "pods parts merged");
    CHECK([devs[1].levels[@""] integerValue] == 64, "trackpad HID level");

    // Buds not connected: the case still shows, dimmed, with its address so a click can connect.
    NSArray<FCBTDevice *> *idle = FCMergeBluetoothDevices(@[ @[ @"Owner’s AirPods Pro", @"aa-bb", @NO ] ],
                                                         [FCAccessoryPart partsFromDescriptions:@[ caseOnly ]], @{});
    CHECK(idle.count == 1 && !idle[0].connected && [idle[0].address isEqualToString:@"aa-bb"], "case-only keeps the pairing");
    // A battery group no pairing explains is shown under its own name, with nothing to click.
    NSArray<FCBTDevice *> *orphan = FCMergeBluetoothDevices(@[], [FCAccessoryPart partsFromDescriptions:@[ caseOnly ]], @{});
    CHECK(orphan.count == 1 && [orphan[0].name isEqualToString:@"Owner’s AirPods Pro"] && !orphan[0].address, "orphan group");
    // Longest name wins: the "Pro 2" case is not claimed by "AirPods Pro".
    NSArray<FCBTDevice *> *two = FCMergeBluetoothDevices(@[ @[ @"AirPods Pro", @"a", @YES ], @[ @"AirPods Pro 2", @"b", @YES ] ],
        [FCAccessoryPart partsFromDescriptions:@[ @{ @"Name": @"AirPods Pro 2 Case", @"Part Identifier": @"Case", @"Current Capacity": @50 } ]], @{});
    for (FCBTDevice *d in two) {
        if ([d.name isEqualToString:@"AirPods Pro 2"]) CHECK([d.levels[@"C"] integerValue] == 50, "Pro 2 owns its case");
        else CHECK(d.levels.count == 0, "Pro does not");
    }
    // Live on 2026-11-15: two pairings both named "AirPods Pro", the connected one read by IOBluetooth
    // (L34 R28, keyed by its address), and two accessory sources, "AirPods Pro" combined 90 and
    // "Owner’s AirPods Pro" combined 28. The rail showed the buds twice. One device, the connected one,
    // with its exact readings and no contradicting combined figure.
    FCAccessoryPart *(^part)(NSString *, NSString *, NSString *, NSInteger) = ^(NSString *n, NSString *g, NSString *k, NSInteger v) {
        FCAccessoryPart *p = [FCAccessoryPart new]; p.name = n; p.group = g; p.part = k; p.percent = v; return p;
    };
    NSArray<FCBTDevice *> *twins = FCMergeBluetoothDevices(
        @[ @[ @"AirPods Pro", @"14-14", @YES ], @[ @"AirPods Pro", @"30-d8", @NO ] ],
        @[ part(@"AirPods Pro", @"EF6F", @"Combined", 90), part(@"Owner’s AirPods Pro", @"88CA", @"Combined", 28),
           part(@"AirPods Pro", @"14-14", @"Left", 34), part(@"AirPods Pro", @"14-14", @"Right", 28) ], @{});
    CHECK(twins.count == 1, "one device, not two: %lu", (unsigned long)twins.count);
    CHECK([twins.firstObject.address isEqualToString:@"14-14"] && twins.firstObject.connected, "the connected pairing");
    CHECK(([twins.firstObject.levels isEqualToDictionary:@{ @"L": @34, @"R": @28 }]), "exact L/R only: %@", twins.firstObject.levels);
    // The exact readings still take what they lack: the case, from the accessory source.
    NSArray<FCBTDevice *> *withCase = FCMergeBluetoothDevices(@[ @[ @"AirPods Pro", @"14-14", @YES ] ],
        @[ part(@"AirPods Pro", @"14-14", @"Left", 34), part(@"Owner’s AirPods Pro Case", @"88CA", @"Case", 61) ], @{});
    CHECK(([withCase.firstObject.levels isEqualToDictionary:@{ @"L": @34, @"C": @61 }]), "case filled in: %@", withCase.firstObject.levels);
    CHECK([FCShortDeviceName(@"Owner’s AirPods Pro") isEqualToString:@"AirPods Pro"], "owner dropped");
    CHECK([FCShortDeviceName(@"Owner's Magic Trackpad") isEqualToString:@"Trackpad"], "straight quote + Magic");
    CHECK([FCShortDeviceName(@"A very long headphone name") isEqualToString:@"A very long hea…"], "%@", FCShortDeviceName(@"A very long headphone name"));
}

void test_power_bluetooth_segments(void) {
    FCBTDevice *pods = [FCBTDevice new];
    pods.name = @"Owner’s AirPods Pro"; pods.address = @"aa-bb"; pods.connected = YES; pods.levels = @{ @"L": @82, @"R": @8, @"C": @45 };
    FCBTDevice *pad = [FCBTDevice new];
    pad.name = @"Owner’s Magic Trackpad"; pad.address = @"cc-dd"; pad.connected = YES; pad.levels = @{ @"": @64 };
    NSArray *segs = FCBluetoothSegments(YES, YES, @"⌃⌥⇧B", @[ pods, pad ], 4);
    NSString *line = FCJoinPower(segs);
    CHECK([line isEqualToString:@"BT ● ⌃⌥⇧B  AirPods Pro L82 R8 C45 · Trackpad 64%"], "%@", line);
    CHECK([FCActionFor(segs, @" ●") isEqualToString:@"bt.power"], "dot toggles power");
    CHECK([FCActionFor(segs, @" ⌃⌥⇧B") isEqualToString:@"bt.power"], "the tip toggles power too");
    CHECK([FCActionFor(segs, @"AirPods Pro") isEqualToString:@"bt.device:aa-bb"], "a name connects/disconnects");
    for (NSArray *seg in segs) if ([seg[0] isEqualToString:@" R8"]) CHECK([seg[1] integerValue] == FCPowerRoleError, "8%% is red");

    NSString *off = FCJoinPower(FCBluetoothSegments(YES, NO, @"⌃⌥⇧B", @[ pods ], 4));
    CHECK([off isEqualToString:@"BT ○ off ⌃⌥⇧B"], "off hides devices: %@", off);
    NSString *unknown = FCJoinPower(FCBluetoothSegments(NO, NO, nil, @[], 4));
    CHECK([unknown isEqualToString:@"BT ?"], "unknown power: %@", unknown);
    NSString *capped = FCJoinPower(FCBluetoothSegments(YES, YES, nil, @[ pods, pad ], 1));
    CHECK([capped hasSuffix:@"C45 +1"], "cap with a count: %@", capped);
}

void test_power_chord_glyphs_and_registry(void) {
    CHECK([FCChordGlyphs(@"ctrl+opt+shift+b") isEqualToString:@"⌃⌥⇧B"], "%@", FCChordGlyphs(@"ctrl+opt+shift+b"));
    CHECK([FCChordGlyphs(@"cmd+shift+ctrl+space") isEqualToString:@"⌃⇧⌘Space"], "drawn order: %@", FCChordGlyphs(@"cmd+shift+ctrl+space"));
    CHECK([FCChordGlyphs(nil) isEqualToString:@""], "nil -> empty");

    NSData *reg = [@"{\"v\":1,\"hotkeys\":["
        "{\"id\":\"tts\",\"keys\":\"opt+s\",\"run\":[\"/x/read.sh\",\"en\"]},"
        "{\"id\":\"bt-off\",\"keys\":\"ctrl+opt+shift+o\",\"enabled\":false,\"run\":[\"/Applications/FloatingClock.app/Contents/MacOS/floating-clock\",\"--bluetooth\",\"toggle\"]},"
        "{\"id\":\"bt\",\"keys\":\"ctrl+opt+shift+b\",\"run\":[\"/Applications/FloatingClock.app/Contents/MacOS/floating-clock\",\"--bluetooth\",\"toggle\"]}]}"
        dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([FCHotkeyKeysForCommand(reg, @[ @"--bluetooth", @"toggle" ]) isEqualToString:@"ctrl+opt+shift+b"], "disabled entry skipped");
    CHECK(!FCHotkeyKeysForCommand(reg, @[ @"--bluetooth", @"on" ]), "other args do not match");
    CHECK(!FCHotkeyKeysForCommand([@"{\"v\":2,\"hotkeys\":[]}" dataUsingEncoding:NSUTF8StringEncoding], @[ @"--bluetooth", @"toggle" ]), "unknown schema");
    CHECK(!FCHotkeyKeysForCommand([@"garbage" dataUsingEncoding:NSUTF8StringEncoding], @[ @"x" ]), "garbage");
    CHECK(!FCHotkeyKeysForCommand(nil, @[ @"x" ]), "no file");
}
