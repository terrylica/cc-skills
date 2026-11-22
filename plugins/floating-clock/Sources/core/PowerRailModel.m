#import "PowerRailModel.h"
#include <math.h>

#pragma mark - Small readers over plist values

static NSNumber *FCNum(id v) { return [v isKindOfClass:[NSNumber class]] ? v : nil; }
static NSString *FCStr(id v) { return [v isKindOfClass:[NSString class]] ? v : nil; }
static NSDictionary *FCDict(id v) { return [v isKindOfClass:[NSDictionary class]] ? v : nil; }

NSInteger FCSignedRegistryInteger(id value) {
    NSNumber *n = FCNum(value);
    if (!n) return 0;
    // Both spellings land on the same bit pattern: -65 stored signed, or 2^64 - 65 stored unsigned.
    return (NSInteger)(int64_t)[n unsignedLongLongValue];
}

#pragma mark - Battery fields

NSArray<NSString *> *FCBatteryFieldIDs(void) {
    return @[ @"time", @"power", @"adapter", @"health", @"cycles", @"temp" ];
}

NSString *FCBatteryFieldTitle(NSString *fieldID) {
    NSDictionary *t = @{ @"time": @"Time to Full / Empty", @"power": @"Power In / Out (W)",
                         @"adapter": @"Adapter Watts", @"health": @"Health",
                         @"cycles": @"Cycle Count", @"temp": @"Temperature" };
    return t[fieldID] ?: fieldID;
}

FCBatteryField FCBatteryFieldForID(NSString *fieldID) {
    NSDictionary *m = @{ @"time": @(FCBatteryFieldTime), @"power": @(FCBatteryFieldPower),
                         @"adapter": @(FCBatteryFieldAdapter), @"health": @(FCBatteryFieldHealth),
                         @"cycles": @(FCBatteryFieldCycles), @"temp": @(FCBatteryFieldTemp) };
    return (FCBatteryField)[m[fieldID] unsignedIntegerValue];
}

FCBatteryField FCBatteryFieldsFromIDs(NSArray *ids) {
    if (![ids isKindOfClass:[NSArray class]]) ids = FCBatteryFieldIDs();
    FCBatteryField f = 0;
    for (id x in ids) if ([x isKindOfClass:[NSString class]]) f |= FCBatteryFieldForID(x);
    return f;
}

#pragma mark - Battery snapshot

@implementation FCBatterySnapshot

- (instancetype)init {
    if ((self = [super init])) {
        _minutesToFull = -1; _minutesToEmpty = -1; _cycles = -1; _temperatureC = NAN;
    }
    return self;
}

+ (instancetype)snapshotFromPowerSource:(NSDictionary *)ps smartBattery:(NSDictionary *)sb adapter:(NSDictionary *)adapter {
    FCBatterySnapshot *b = [FCBatterySnapshot new];
    ps = FCDict(ps); sb = FCDict(sb); adapter = FCDict(adapter);
    if (!ps && !sb) return b;   // no battery at all
    b.present = ps ? (FCNum(ps[@"Is Present"]) ? [ps[@"Is Present"] boolValue] : YES) : YES;

    // Percentage: the power-source pair is the one macOS's own menu uses (current over max, both in
    // percent on Apple Silicon); the registry's CurrentCapacity is the fallback.
    NSNumber *cur = FCNum(ps[@"Current Capacity"]), *max = FCNum(ps[@"Max Capacity"]);
    if (cur && max.doubleValue > 0) b.percent = lround(cur.doubleValue * 100.0 / max.doubleValue);
    else if (FCNum(sb[@"CurrentCapacity"])) b.percent = [sb[@"CurrentCapacity"] integerValue];
    b.percent = MAX(0, MIN(100, b.percent));

    NSString *src = FCStr(ps[@"Power Source State"]);
    if (src) b.onAC = [src isEqualToString:@"AC Power"];
    else b.onAC = [sb[@"ExternalConnected"] boolValue];
    b.charging = FCNum(ps[@"Is Charging"]) ? [ps[@"Is Charging"] boolValue] : [sb[@"IsCharging"] boolValue];
    b.fullyCharged = FCNum(ps[@"Is Charged"]) ? [ps[@"Is Charged"] boolValue] : [sb[@"FullyCharged"] boolValue];
    b.optimizedChargingEngaged = [ps[@"Optimized Battery Charging Engaged"] boolValue];

    // Minutes: the power source's estimate (-1 while macOS is still computing it), else the
    // registry's averages, where 65535 means "no estimate".
    NSInteger toFull = FCNum(ps[@"Time to Full Charge"]) ? [ps[@"Time to Full Charge"] integerValue] : -1;
    NSInteger toEmpty = FCNum(ps[@"Time to Empty"]) ? [ps[@"Time to Empty"] integerValue] : -1;
    if (toFull < 0 && FCNum(sb[@"AvgTimeToFull"])) toFull = [sb[@"AvgTimeToFull"] integerValue];
    if (toEmpty < 0 && FCNum(sb[@"AvgTimeToEmpty"])) toEmpty = [sb[@"AvgTimeToEmpty"] integerValue];
    b.minutesToFull = (toFull >= 0 && toFull < 65535) ? toFull : -1;
    b.minutesToEmpty = (toEmpty >= 0 && toEmpty < 65535) ? toEmpty : -1;

    b.voltageMV = FCNum(sb[@"Voltage"]) ? [sb[@"Voltage"] integerValue] : 0;
    id amps = sb[@"InstantAmperage"] ?: sb[@"Amperage"];
    b.amperageMA = FCSignedRegistryInteger(amps);
    b.cycles = FCNum(sb[@"CycleCount"]) ? [sb[@"CycleCount"] integerValue] : -1;
    if (FCNum(sb[@"Temperature"])) b.temperatureC = [sb[@"Temperature"] doubleValue] / 100.0;

    NSDictionary *bd = FCDict(sb[@"BatteryData"]);
    b.designMAh = FCNum(sb[@"DesignCapacity"]) ? [sb[@"DesignCapacity"] integerValue]
                : (FCNum(bd[@"DesignCapacity"]) ? [bd[@"DesignCapacity"] integerValue] : 0);
    NSNumber *full = FCNum(sb[@"AppleRawMaxCapacity"]) ?: FCNum(sb[@"NominalChargeCapacity"]) ?: FCNum(bd[@"NominalChargeCapacity"]);
    b.fullMAh = full.integerValue;
    b.currentMAh = [FCNum(sb[@"AppleRawCurrentCapacity"]) integerValue];
    b.notChargingReason = [FCNum(FCDict(sb[@"ChargerData"])[@"NotChargingReason"]) integerValue];

    NSNumber *w = FCNum(adapter[@"Watts"]) ?: FCNum(FCDict(sb[@"AdapterDetails"])[@"Watts"]);
    b.adapterWatts = b.onAC ? w.integerValue : 0;
    NSString *an = FCStr(adapter[@"Name"]) ?: FCStr(FCDict(sb[@"AdapterDetails"])[@"Name"]);
    b.adapterName = b.onAC ? an : nil;
    return b;
}

- (FCBatteryState)state {
    if (!self.present) return FCBatteryStateNone;
    if (!self.onAC) return FCBatteryStateDischarging;
    if (self.charging) return FCBatteryStateCharging;
    if (self.fullyCharged || self.percent >= 100) return FCBatteryStateFull;
    return FCBatteryStateHeld;
}

- (double)watts {
    if (self.voltageMV <= 0) return 0;
    return (double)self.voltageMV * (double)self.amperageMA / 1.0e6;
}

- (double)healthPercent {
    if (self.designMAh <= 0 || self.fullMAh <= 0) return -1;
    return 100.0 * (double)self.fullMAh / (double)self.designMAh;
}

@end

NSString *FCBatteryMinutesLabel(NSInteger minutes) {
    if (minutes < 0 || minutes >= 100 * 60) return @"";
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(minutes / 60), (long)(minutes % 60)];
}

NSString *FCSignedWattsLabel(double watts) {
    double a = fabs(watts);
    if (a < 0.05) return @"0W";
    NSString *sign = watts > 0 ? @"+" : @"-";
    if (a < 9.95) return [NSString stringWithFormat:@"%@%.1fW", sign, a];
    return [NSString stringWithFormat:@"%@%.0fW", sign, a];
}

#pragma mark - Accessory parts

@implementation FCAccessoryPart

+ (FCAccessoryPart *)partFrom:(NSDictionary *)d group:(NSString *)group {
    NSNumber *cur = FCNum(d[@"Current Capacity"]);
    NSString *name = FCStr(d[@"Name"]);
    if (!cur || !name.length) return nil;
    FCAccessoryPart *p = [FCAccessoryPart new];
    p.name = name;
    p.group = FCStr(d[@"Group Identifier"]) ?: group ?: name;
    p.part = FCStr(d[@"Part Identifier"]) ?: @"";
    NSNumber *max = FCNum(d[@"Max Capacity"]);
    double pct = (max.doubleValue > 0 && max.doubleValue != 100) ? cur.doubleValue * 100.0 / max.doubleValue : cur.doubleValue;
    p.percent = MAX(0, MIN(100, lround(pct)));
    p.charging = [d[@"Is Charging"] boolValue];
    return p;
}

+ (NSArray<FCAccessoryPart *> *)partsFromDescriptions:(NSArray<NSDictionary *> *)descriptions {
    NSMutableArray *out = [NSMutableArray array];
    for (id x in descriptions) {
        NSDictionary *d = FCDict(x);
        if (!d) continue;
        NSString *group = FCStr(d[@"Group Identifier"]) ?: FCStr(d[@"Name"]);
        NSArray *sub = [d[@"Combined Parts"] isKindOfClass:[NSArray class]] ? d[@"Combined Parts"] : nil;
        NSUInteger before = out.count;
        for (id s in sub) {
            NSDictionary *sd = FCDict(s);
            if (!sd) continue;
            NSMutableDictionary *m = [sd mutableCopy];
            if (!FCStr(m[@"Name"])) m[@"Name"] = FCStr(d[@"Name"]) ?: @"";
            FCAccessoryPart *p = [self partFrom:m group:group];
            if (p) [out addObject:p];
        }
        if (out.count == before) {   // no usable sub-parts: the entry is the battery
            FCAccessoryPart *p = [self partFrom:d group:group];
            if (p) [out addObject:p];
        }
    }
    return out;
}

@end

@implementation FCBTDevice
@end

static NSString *FCPartKey(NSString *part) {
    if ([part isEqualToString:@"Left"]) return @"L";
    if ([part isEqualToString:@"Right"]) return @"R";
    if ([part isEqualToString:@"Case"]) return @"C";
    return @"";
}

// "Owner’s AirPods Pro Case" -> "Owner’s AirPods Pro": the device a lone part belongs to.
static NSString *FCStripPartSuffix(NSString *name) {
    for (NSString *suffix in @[ @" Case", @" Left", @" Right" ]) {
        if ([name hasSuffix:suffix]) return [name substringToIndex:name.length - suffix.length];
    }
    return name;
}

static NSString *FCOwnerless(NSString *name);

NSString *FCShortDeviceName(NSString *name) {
    NSString *s = FCOwnerless(name);
    if ([s hasPrefix:@"Magic "] && s.length > 6) s = [s substringFromIndex:6];
    if (s.length > 16) s = [[s substringToIndex:15] stringByAppendingString:@"…"];
    return s;
}

// "Owner’s AirPods Pro" -> "AirPods Pro": the same pair can be named with or without its owner by
// different sources (measured 2026-11-15: IOBluetooth said "AirPods Pro", the accessory power source
// "Owner’s AirPods Pro" for the same buds).
static NSString *FCOwnerless(NSString *name) {
    NSString *s = name ?: @"";
    NSRegularExpression *owner = [NSRegularExpression regularExpressionWithPattern:@"^[^’']{1,40}[’']s\\s+" options:0 error:nil];
    NSTextCheckingResult *m = [owner firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    return (m && m.range.length < s.length) ? [s substringFromIndex:NSMaxRange(m.range)] : s;
}

static BOOL FCNameStartsWith(NSString *name, NSString *prefix) {
    return prefix.length && name.length >= prefix.length
        && [name compare:prefix options:NSCaseInsensitiveSearch range:NSMakeRange(0, prefix.length)] == NSOrderedSame;
}

NSArray<FCBTDevice *> *FCMergeBluetoothDevices(NSArray<NSArray *> *paired, NSArray<FCAccessoryPart *> *parts,
                                              NSDictionary<NSString *, NSNumber *> *hidLevels) {
    NSMutableArray<FCBTDevice *> *devices = [NSMutableArray array];
    for (NSArray *p in paired) {
        if (![p isKindOfClass:[NSArray class]] || p.count < 3 || !FCStr(p[0]).length) continue;
        FCBTDevice *d = [FCBTDevice new];
        d.name = p[0];
        d.address = FCStr(p[1]).length ? p[1] : nil;
        d.connected = [p[2] boolValue];
        d.levels = @{};
        [devices addObject:d];
    }
    // Name candidates: longest name first (so "AirPods Pro" never claims the parts of "AirPods Pro 2"),
    // and among equal names the connected pairing first (two pairings can share a name).
    NSArray *byName = [devices sortedArrayUsingComparator:^NSComparisonResult(FCBTDevice *a, FCBTDevice *b) {
        NSUInteger la = FCOwnerless(a.name).length, lb = FCOwnerless(b.name).length;
        if (la != lb) return la > lb ? NSOrderedAscending : NSOrderedDescending;
        if (a.connected != b.connected) return a.connected ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    FCBTDevice *(^byAddress)(NSString *) = ^FCBTDevice *(NSString *group) {
        for (FCBTDevice *d in devices) if (d.address && [d.address caseInsensitiveCompare:group] == NSOrderedSame) return d;
        return nil;
    };
    // Parts keyed by a device address (IOBluetooth's own readings of a connected device) go first: they
    // are exact, and a device that has them takes name-matched parts only to fill what they lack.
    NSArray *ordered = [parts sortedArrayUsingComparator:^NSComparisonResult(FCAccessoryPart *a, FCAccessoryPart *b) {
        BOOL ka = byAddress(a.group) != nil, kb = byAddress(b.group) != nil;
        return ka == kb ? NSOrderedSame : (ka ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSMutableSet<FCBTDevice *> *exact = [NSMutableSet set];
    NSMutableDictionary<NSString *, FCBTDevice *> *byGroup = [NSMutableDictionary dictionary];
    for (FCAccessoryPart *part in ordered) {
        FCBTDevice *owner = byGroup[part.group];
        BOOL keyed = NO;
        if (!owner) { owner = byAddress(part.group); keyed = owner != nil; }
        if (!owner) {
            NSString *pn = FCOwnerless(part.name);
            for (FCBTDevice *d in byName) if (FCNameStartsWith(pn, FCOwnerless(d.name))) { owner = d; break; }
        }
        if (!owner) {   // a battery group no pairing explains: show it, with nothing to click
            owner = [FCBTDevice new];
            owner.name = FCStripPartSuffix(part.name);
            owner.levels = @{};
            [devices addObject:owner];
        }
        byGroup[part.group] = owner;
        NSString *key = FCPartKey(part.part);
        NSMutableDictionary *lv = [owner.levels mutableCopy];
        if (keyed) {
            [exact addObject:owner];
            lv[key] = @(part.percent);
        } else if ([exact containsObject:owner]) {
            // Fill only what the exact readings lack (the case), and never a combined figure beside
            // left and right ones it could contradict.
            BOOL hasBuds = lv[@"L"] || lv[@"R"];
            if (!lv[key] && !(key.length == 0 && hasBuds)) lv[key] = @(part.percent);
        } else {
            lv[key] = @(part.percent);
        }
        owner.levels = lv;
        if (part.charging) owner.charging = YES;
    }
    for (FCBTDevice *d in devices) {
        NSNumber *h = hidLevels[d.name];
        if (h && !d.levels[@""]) {
            NSMutableDictionary *lv = [d.levels mutableCopy];
            lv[@""] = h;
            d.levels = lv;
        }
    }
    NSArray *shown = [devices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FCBTDevice *d, id _) {
        return d.connected || d.levels.count > 0;
    }]];
    return [shown sortedArrayUsingComparator:^NSComparisonResult(FCBTDevice *a, FCBTDevice *b) {
        if (a.connected != b.connected) return a.connected ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
}

#pragma mark - Segments

static NSArray *FCSeg(NSString *text, FCPowerRole role, NSString *action) {
    return @[ text, @(role), action ?: @"" ];
}

static FCPowerRole FCLevelRole(NSInteger pct, BOOL dimmed) {
    if (pct <= 10) return FCPowerRoleError;
    if (pct <= 20) return FCPowerRoleWarn;
    return dimmed ? FCPowerRoleDim : FCPowerRoleText;
}

NSArray<NSArray *> *FCBatterySegments(FCBatterySnapshot *b, FCBatteryField fields) {
    NSMutableArray *s = [NSMutableArray arrayWithObject:FCSeg(@"BAT", FCPowerRoleHeading, nil)];
    FCBatteryState st = [b state];
    if (st == FCBatteryStateNone) {
        [s addObject:FCSeg(@" none · AC", FCPowerRoleDim, nil)];
        return s;
    }
    // Low is only alarming while draining; a low battery on a charger is already being fixed.
    FCPowerRole pctRole = st == FCBatteryStateDischarging ? FCLevelRole(b.percent, NO) : FCPowerRoleText;
    [s addObject:FCSeg([NSString stringWithFormat:@" %ld%%", (long)b.percent], pctRole, nil)];
    switch (st) {
        case FCBatteryStateCharging:    [s addObject:FCSeg(@" ⚡", FCPowerRoleOK, nil)]; break;
        case FCBatteryStateHeld:        [s addObject:FCSeg(@" ⏸", FCPowerRoleDim, nil)]; break;
        case FCBatteryStateFull:        [s addObject:FCSeg(@" ✓", FCPowerRoleOK, nil)]; break;
        case FCBatteryStateDischarging: [s addObject:FCSeg(@" ▾", FCPowerRoleText, nil)]; break;
        default: break;
    }
    if (fields & FCBatteryFieldTime) {
        NSInteger m = st == FCBatteryStateCharging ? b.minutesToFull : (st == FCBatteryStateDischarging ? b.minutesToEmpty : -1);
        NSString *t = FCBatteryMinutesLabel(m);
        if (t.length) [s addObject:FCSeg([@" " stringByAppendingString:t], FCPowerRoleText, nil)];
    }
    if ((fields & FCBatteryFieldPower) && b.voltageMV > 0) {
        [s addObject:FCSeg([@" " stringByAppendingString:FCSignedWattsLabel([b watts])], FCPowerRoleDim, nil)];
    }
    if ((fields & FCBatteryFieldAdapter) && b.onAC) {
        NSString *a = b.adapterWatts > 0 ? [NSString stringWithFormat:@" AC %ldW", (long)b.adapterWatts] : @" AC";
        [s addObject:FCSeg(a, FCPowerRoleDim, nil)];
    }
    double h = [b healthPercent];
    if ((fields & FCBatteryFieldHealth) && h > 0) {
        [s addObject:FCSeg([NSString stringWithFormat:@" ♥%.0f%%", MIN(h, 999.0)], h < 80.0 ? FCPowerRoleWarn : FCPowerRoleText, nil)];
    }
    if ((fields & FCBatteryFieldCycles) && b.cycles >= 0) {
        [s addObject:FCSeg([NSString stringWithFormat:@" %ldcy", (long)b.cycles], FCPowerRoleDim, nil)];
    }
    if ((fields & FCBatteryFieldTemp) && !isnan(b.temperatureC)) {
        FCPowerRole r = b.temperatureC >= 45.0 ? FCPowerRoleError : (b.temperatureC >= 40.0 ? FCPowerRoleWarn : FCPowerRoleDim);
        [s addObject:FCSeg([NSString stringWithFormat:@" %.0f°", b.temperatureC], r, nil)];
    }
    return s;
}

NSArray<NSArray *> *FCBluetoothSegments(BOOL known, BOOL poweredOn, NSString *hint, NSArray<FCBTDevice *> *devices,
                                       NSUInteger maxDevices) {
    NSMutableArray *s = [NSMutableArray arrayWithObject:FCSeg(@"BT", FCPowerRoleHeading, nil)];
    if (!known) [s addObject:FCSeg(@" ?", FCPowerRoleDim, @"bt.power")];
    else if (poweredOn) [s addObject:FCSeg(@" ●", FCPowerRoleOK, @"bt.power")];
    else [s addObject:FCSeg(@" ○ off", FCPowerRoleDim, @"bt.power")];
    if (hint.length) [s addObject:FCSeg([@" " stringByAppendingString:hint], FCPowerRoleHint, @"bt.power")];
    if (!known || !poweredOn) return s;
    NSUInteger shown = 0;
    for (FCBTDevice *d in devices) {
        if (shown == maxDevices) {
            [s addObject:FCSeg([NSString stringWithFormat:@" +%lu", (unsigned long)(devices.count - shown)], FCPowerRoleDim, nil)];
            break;
        }
        NSString *action = d.address.length ? [@"bt.device:" stringByAppendingString:d.address] : @"";
        [s addObject:FCSeg(shown == 0 ? @"  " : @" · ", FCPowerRoleDim, nil)];
        [s addObject:FCSeg(FCShortDeviceName(d.name), d.connected ? FCPowerRoleName : FCPowerRoleDim, action)];
        BOOL dim = !d.connected;
        NSNumber *single = d.levels[@""];
        if (single) {
            [s addObject:FCSeg([NSString stringWithFormat:@" %ld%%", (long)single.integerValue], FCLevelRole(single.integerValue, dim), nil)];
        }
        for (NSString *k in @[ @"L", @"R", @"C" ]) {
            NSNumber *v = d.levels[k];
            if (v) [s addObject:FCSeg([NSString stringWithFormat:@" %@%ld", k, (long)v.integerValue], FCLevelRole(v.integerValue, dim), nil)];
        }
        if (d.charging) [s addObject:FCSeg(@"⚡", FCPowerRoleOK, nil)];
        shown++;
    }
    return s;
}

#pragma mark - Shortcut tips

NSString *FCChordGlyphs(NSString *keys) {
    if (!keys.length) return @"";
    NSArray *parts = [[keys lowercaseString] componentsSeparatedByString:@"+"];
    BOOL ctrl = NO, opt = NO, shift = NO, cmd = NO, fn = NO;
    NSString *key = @"";
    for (NSString *raw in parts) {
        NSString *p = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([@[ @"ctrl", @"control", @"⌃" ] containsObject:p]) ctrl = YES;
        else if ([@[ @"opt", @"option", @"alt", @"⌥" ] containsObject:p]) opt = YES;
        else if ([@[ @"shift", @"⇧" ] containsObject:p]) shift = YES;
        else if ([@[ @"cmd", @"command", @"⌘" ] containsObject:p]) cmd = YES;
        else if ([@[ @"fn", @"globe" ] containsObject:p]) fn = YES;
        else if (p.length) key = p;
    }
    NSDictionary *named = @{ @"space": @"Space", @"esc": @"⎋", @"escape": @"⎋", @"return": @"↩", @"enter": @"↩",
                             @"tab": @"⇥", @"delete": @"⌫", @"backspace": @"⌫", @"up": @"↑", @"down": @"↓",
                             @"left": @"←", @"right": @"→" };
    NSString *k = named[key] ?: key.uppercaseString;
    return [NSString stringWithFormat:@"%@%@%@%@%@%@", fn ? @"fn" : @"", ctrl ? @"⌃" : @"", opt ? @"⌥" : @"",
            shift ? @"⇧" : @"", cmd ? @"⌘" : @"", k];
}

NSString *FCHotkeyKeysForCommand(NSData *registryJSON, NSArray<NSString *> *args) {
    if (!registryJSON.length) return nil;
    NSDictionary *root = FCDict([NSJSONSerialization JSONObjectWithData:registryJSON options:0 error:nil]);
    if ([root[@"v"] integerValue] != 1) return nil;
    NSArray *list = [root[@"hotkeys"] isKindOfClass:[NSArray class]] ? root[@"hotkeys"] : nil;
    for (id x in list) {
        NSDictionary *h = FCDict(x);
        NSArray *run = [h[@"run"] isKindOfClass:[NSArray class]] ? h[@"run"] : nil;
        NSString *keys = FCStr(h[@"keys"]);
        if (!keys.length || run.count < 1 + args.count || !FCStr(run[0])) continue;
        if (FCNum(h[@"enabled"]) && ![h[@"enabled"] boolValue]) continue;
        if (![[run[0] lastPathComponent] isEqualToString:@"floating-clock"]) continue;
        for (NSUInteger i = 1; i + args.count <= run.count; i++) {
            if ([[run subarrayWithRange:NSMakeRange(i, args.count)] isEqualToArray:args]) return keys;
        }
    }
    return nil;
}
