#import "NetworkServiceCatalog.h"

NSString *const FCNetServiceName = @"name";
NSString *const FCNetServiceDevice = @"device";
NSString *const FCNetServiceDisabled = @"disabled";

// `networksetup -listnetworkserviceorder` emits two lines per service:
//
//   (1) Wi-Fi
//   (Hardware Port: Wi-Fi, Device: en0)
//
// Disabled services carry an asterisk in the index slot; VPN-style services
// have an empty Device. Both shapes are covered by the fixtures in
// tests/test_network.m.
static NSRegularExpression *FCIndexLineRegex(void) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\(\\*?[0-9]*\\)[ \t]*(.+?)[ \t]*$"
                                                       options:0
                                                         error:NULL];
    });
    return re;
}

static NSRegularExpression *FCDeviceLineRegex(void) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\(Hardware Port:.*?,[ \t]*Device:[ \t]*(.*?)[ \t]*\\)[ \t]*$"
                                                       options:0
                                                         error:NULL];
    });
    return re;
}

static NSString *FCFirstGroup(NSRegularExpression *re, NSString *line) {
    if (!re || line.length == 0) return nil;
    NSTextCheckingResult *m = [re firstMatchInString:line
                                             options:0
                                               range:NSMakeRange(0, line.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    return [line substringWithRange:r];
}

NSArray<NSDictionary<NSString *, id> *> *FCParseNetworkServiceOrder(NSString *output) {
    if (output.length == 0) return @[];

    NSMutableArray<NSDictionary<NSString *, id> *> *out = [NSMutableArray array];
    NSString *pendingName = nil;
    BOOL pendingDisabled = NO;

    for (NSString *raw in [output componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0) continue;

        // The device line must be tested FIRST: both shapes start with "(",
        // and a Hardware Port line would otherwise match the index pattern
        // and be mistaken for a service named "Hardware Port: ...".
        NSString *device = FCFirstGroup(FCDeviceLineRegex(), line);
        if (device) {
            if (pendingName) {
                [out addObject:@{
                    FCNetServiceName: pendingName,
                    FCNetServiceDevice: device,
                    FCNetServiceDisabled: @(pendingDisabled),
                }];
                pendingName = nil;
                pendingDisabled = NO;
            }
            continue;
        }

        NSString *name = FCFirstGroup(FCIndexLineRegex(), line);
        if (name) {
            // A service whose device line never arrived (malformed tail)
            // is still recorded, with no device, rather than dropped.
            if (pendingName) {
                [out addObject:@{
                    FCNetServiceName: pendingName,
                    FCNetServiceDevice: @"",
                    FCNetServiceDisabled: @(pendingDisabled),
                }];
            }
            pendingName = name;
            pendingDisabled = [line hasPrefix:@"(*"];
        }
        // Anything else (the "An asterisk (*) denotes..." header) is ignored.
    }

    if (pendingName) {
        [out addObject:@{
            FCNetServiceName: pendingName,
            FCNetServiceDevice: @"",
            FCNetServiceDisabled: @(pendingDisabled),
        }];
    }
    return out;
}

NSString *FCServiceNameForBSDDevice(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                    NSString *device) {
    if (device.length == 0) return nil;
    for (NSDictionary<NSString *, id> *e in catalog) {
        NSString *d = e[FCNetServiceDevice];
        if ([d isKindOfClass:[NSString class]] && [d isEqualToString:device]) {
            NSString *n = e[FCNetServiceName];
            return [n isKindOfClass:[NSString class]] ? n : nil;
        }
    }
    return nil;
}

NSArray<NSString *> *FCReorderServiceNamesFirst(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                                NSString *chosenName) {
    if (chosenName.length == 0 || catalog.count == 0) return nil;

    BOOL found = NO;
    for (NSDictionary<NSString *, id> *e in catalog) {
        NSString *n = e[FCNetServiceName];
        if ([n isKindOfClass:[NSString class]] && [n isEqualToString:chosenName]) {
            found = YES;
            break;
        }
    }
    // Refuse rather than emit a list networksetup would certainly reject.
    if (!found) return nil;

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:catalog.count];
    [names addObject:chosenName];
    for (NSDictionary<NSString *, id> *e in catalog) {
        NSString *n = e[FCNetServiceName];
        if (![n isKindOfClass:[NSString class]]) continue;
        if ([n isEqualToString:chosenName]) continue;
        [names addObject:n];
    }
    return names;
}

NSArray<NSDictionary<NSString *, id> *> *FCSwitchableServices(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                                              NSSet<NSString *> *liveDevices) {
    NSMutableArray<NSDictionary<NSString *, id> *> *out = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *e in catalog) {
        NSString *d = e[FCNetServiceDevice];
        NSNumber *disabled = e[FCNetServiceDisabled];
        if (![d isKindOfClass:[NSString class]] || d.length == 0) continue;
        if ([disabled isKindOfClass:[NSNumber class]] && disabled.boolValue) continue;
        // nil means "liveness unknown" (lookup failed) → keep everything.
        // An empty set means "nothing is live" → keep nothing. See the header.
        if (liveDevices && ![liveDevices containsObject:d]) continue;
        [out addObject:e];
    }
    return out;
}
