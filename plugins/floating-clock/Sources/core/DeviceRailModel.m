#import "DeviceRailModel.h"
#import "LevelMeterMath.h"

FCDockState FCDeriveDockState(BOOL devicePresent, BOOL dockPortKnown, BOOL dockPortConnected) {
    if (devicePresent) return FCDockStateAttached;
    if (!dockPortKnown) return FCDockStateUnknown;
    return dockPortConnected ? FCDockStateEmpty : FCDockStateUnplugged;
}

NSString *FCCompactAge(double secs) {
    if (!(secs >= 0)) return @"";
    long s = (long)secs;
    if (s < 60) return [NSString stringWithFormat:@"%lds", s];
    if (s < 3600) return [NSString stringWithFormat:@"%ldm", s / 60];
    if (s < 86400) return [NSString stringWithFormat:@"%ldh%02ldm", s / 3600, (s % 3600) / 60];
    return [NSString stringWithFormat:@"%ldd", s / 86400];
}

static NSString *FCStr(id v) { return [v isKindOfClass:[NSString class]] ? v : @""; }

@implementation FCDeviceRailStatus
+ (instancetype)statusFromJSONData:(NSData *)data {
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = obj;
    if (![d[@"v"] isKindOfClass:[NSNumber class]] || [d[@"v"] intValue] != 1) return nil;
    FCDeviceRailStatus *s = [FCDeviceRailStatus new];
    s.pid      = [d[@"pid"] isKindOfClass:[NSNumber class]] ? [d[@"pid"] intValue] : 0;
    s.updated  = [d[@"updated"] isKindOfClass:[NSNumber class]] ? [d[@"updated"] doubleValue] : 0;
    s.phase    = FCStr(d[@"phase"]);
    s.tone     = FCStr(d[@"tone"]);
    s.text     = FCStr(d[@"text"]);
    s.detail   = FCStr(d[@"detail"]);
    s.progress = [d[@"progress"] isKindOfClass:[NSNumber class]] ? [d[@"progress"] doubleValue] : -1.0;
    s.summary  = FCStr(d[@"summary"]);
    return s;
}
@end

static FCRailRole FCRoleForTone(NSString *tone) {
    if ([tone isEqualToString:@"active"]) return FCRailRoleActive;
    if ([tone isEqualToString:@"ok"])     return FCRailRoleOK;
    if ([tone isEqualToString:@"warn"])   return FCRailRoleWarn;
    if ([tone isEqualToString:@"error"])  return FCRailRoleError;
    return FCRailRoleDim;
}

NSArray<NSArray *> *FCDeviceRailSegments(NSString *label, FCDockState dock, double dockSecs, BOOL blip,
                                         FCDeviceRailStatus *status, BOOL pidAlive, NSUInteger spin) {
    NSMutableArray *out = [NSMutableArray array];
    void (^add)(NSString *, FCRailRole) = ^(NSString *t, FCRailRole r) { if (t.length) [out addObject:@[ t, @(r) ]]; };

    add([label stringByAppendingString:@" "], FCRailRoleLabel);
    NSString *age = FCCompactAge(dockSecs);
    switch (dock) {
        case FCDockStateAttached:
            add(blip ? @"↻ " : @"● ", blip ? FCRailRoleWarn : FCRailRoleOK);
            add(age.length ? [NSString stringWithFormat:@"docked %@", age] : @"docked", FCRailRoleText);
            break;
        case FCDockStateEmpty:
            add(@"◌ ", FCRailRoleWarn);
            add(age.length ? [NSString stringWithFormat:@"off dock %@", age] : @"off dock", FCRailRoleText);
            break;
        case FCDockStateUnplugged:
            add(@"○ ", FCRailRoleDim);
            add(@"dock unplugged", FCRailRoleDim);
            break;
        case FCDockStateUnknown:
            add(@"? ", FCRailRoleDim);
            add(@"not seen yet", FCRailRoleDim);
            break;
    }
    if (!status) return out;
    add(@"  │ ", FCRailRoleDim);

    BOOL activeTone = [status.tone isEqualToString:@"active"];
    if (status.pid > 0 && activeTone && !pidAlive) {
        // The job died mid-way (crash, kill, logout). Say so instead of freezing on a stale phase.
        add(@"⚠ stopped during ", FCRailRoleWarn);
        add(status.phase.length ? status.phase : @"run", FCRailRoleWarn);
        if (status.summary.length) { add(@" · ", FCRailRoleDim); add(status.summary, FCRailRoleDim); }
        return out;
    }
    if (activeTone && pidAlive) {
        // Quarter-circle spinner: legible at 10 pt (braille frames were too faint) and the same
        // glyph family as the ●◌○ dock marks.
        static NSString *const frames[4] = { @"◐", @"◓", @"◑", @"◒" };
        add([frames[spin % 4] stringByAppendingString:@" "], FCRailRoleActive);
        add(status.text, FCRailRoleText);
        if (status.progress >= 0) {
            add(@" ", FCRailRoleDim);
            add(FCEighthBlockBar(status.progress, 10, @"░"), FCRailRoleActive);
            add([NSString stringWithFormat:@" %3d%%", (int)llround(status.progress * 100.0)], FCRailRoleText);
        }
        if (status.detail.length) { add(@" · ", FCRailRoleDim); add(status.detail, FCRailRoleDim); }
        return out;
    }
    // Resting: this pass's outcome (if it carries news) and the standing summary.
    FCRailRole r = FCRoleForTone(status.tone);
    BOOL news = status.text.length && ![status.tone isEqualToString:@"idle"];
    if (news) add(status.text, r);
    if (status.summary.length) {
        if (news) add(@" · ", FCRailRoleDim);
        add(status.summary, news ? FCRailRoleDim : FCRailRoleOK);
    } else if (!news && status.text.length) {
        add(status.text, FCRailRoleDim);
    }
    return out;
}
