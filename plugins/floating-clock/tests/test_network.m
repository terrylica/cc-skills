// Network service catalog tests. See test_network.h for rationale.
//
// The primary fixture is VERBATIM `networksetup -listnetworkserviceorder`
// output shape, including the leading asterisk header, the blank line between
// records, a service with no BSD device (VPN-style), and a disabled service.
// Service names here are generic on purpose — this repo is public, so no
// fixture carries a real machine's hardware inventory.
#import "test_network.h"
#import "../Sources/core/NetworkServiceCatalog.h"

static NSString *SampleOutput(void) {
    return @"An asterisk (*) denotes that a network service is disabled.\n"
            "(1) Wi-Fi\n"
            "(Hardware Port: Wi-Fi, Device: en0)\n"
            "\n"
            "(2) Wired Adapter\n"
            "(Hardware Port: Wired Adapter, Device: en5)\n"
            "\n"
            "(3) USB 10/100/1000 LAN\n"
            "(Hardware Port: USB 10/100/1000 LAN, Device: en9)\n"
            "\n"
            "(*) Legacy Bridge\n"
            "(Hardware Port: Legacy Bridge, Device: bridge0)\n"
            "\n"
            "(4) Tunnel Service\n"
            "(Hardware Port: Tunnel Service, Device: )\n";
}

static void expectEq(const char *fn, NSString *what, id got, id want) {
    if (got == want || [got isEqual:want]) return;
    fprintf(stderr, "FAIL %s: %s expected '%s' got '%s'\n", fn,
            what.UTF8String,
            [[want description] UTF8String],
            [[got description] UTF8String]);
    failures++;
}

static void expectCount(const char *fn, NSString *what, NSUInteger got, NSUInteger want) {
    if (got == want) return;
    fprintf(stderr, "FAIL %s: %s expected %lu got %lu\n", fn, what.UTF8String,
            (unsigned long)want, (unsigned long)got);
    failures++;
}

void test_network_parse_basic(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    expectCount(__func__, @"service count", cat.count, 5);
    expectEq(__func__, @"first name", cat[0][FCNetServiceName], @"Wi-Fi");
    expectEq(__func__, @"first device", cat[0][FCNetServiceDevice], @"en0");
    // Order must be preserved exactly — index 0 is what owns the default route.
    expectEq(__func__, @"third name", cat[2][FCNetServiceName], @"USB 10/100/1000 LAN");
    expectEq(__func__, @"third device", cat[2][FCNetServiceDevice], @"en9");
}

void test_network_parse_tolerates_header_and_blanks(void) {
    // The "An asterisk..." header must not become a service.
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    for (NSDictionary *e in cat) {
        NSString *n = e[FCNetServiceName];
        if ([n hasPrefix:@"An asterisk"]) {
            fprintf(stderr, "FAIL %s: header line parsed as a service\n", __func__);
            failures++;
        }
        if ([n hasPrefix:@"Hardware Port:"]) {
            fprintf(stderr, "FAIL %s: device line parsed as a service ('%s')\n",
                    __func__, n.UTF8String);
            failures++;
        }
    }
}

void test_network_parse_disabled_marker(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    NSDictionary *legacy = nil;
    for (NSDictionary *e in cat) {
        if ([e[FCNetServiceName] isEqualToString:@"Legacy Bridge"]) legacy = e;
    }
    if (!legacy) {
        fprintf(stderr, "FAIL %s: disabled service missing from catalog\n", __func__);
        failures++;
        return;
    }
    expectEq(__func__, @"disabled flag", legacy[FCNetServiceDisabled], @YES);
    // The name must NOT retain the asterisk marker.
    expectEq(__func__, @"disabled name clean", legacy[FCNetServiceName], @"Legacy Bridge");
}

void test_network_parse_service_without_device(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    NSDictionary *tunnel = nil;
    for (NSDictionary *e in cat) {
        if ([e[FCNetServiceName] isEqualToString:@"Tunnel Service"]) tunnel = e;
    }
    if (!tunnel) {
        fprintf(stderr, "FAIL %s: deviceless service missing\n", __func__);
        failures++;
        return;
    }
    expectEq(__func__, @"empty device", tunnel[FCNetServiceDevice], @"");
}

void test_network_parse_garbage_is_empty(void) {
    // A parse failure must degrade to empty, never throw — the clock must not
    // die because networksetup changed its output format in a future macOS.
    expectCount(__func__, @"nil input", FCParseNetworkServiceOrder(nil).count, 0);
    expectCount(__func__, @"empty input", FCParseNetworkServiceOrder(@"").count, 0);
    expectCount(__func__, @"noise input",
                FCParseNetworkServiceOrder(@"total nonsense\nwith no records\n").count, 0);
}

void test_network_device_to_name_lookup(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    expectEq(__func__, @"en0", FCServiceNameForBSDDevice(cat, @"en0"), @"Wi-Fi");
    expectEq(__func__, @"en9", FCServiceNameForBSDDevice(cat, @"en9"), @"USB 10/100/1000 LAN");
    expectEq(__func__, @"unknown device", FCServiceNameForBSDDevice(cat, @"en99"), nil);
    expectEq(__func__, @"nil device", FCServiceNameForBSDDevice(cat, nil), nil);
    // A deviceless service must never be matched by an empty lookup.
    expectEq(__func__, @"empty device", FCServiceNameForBSDDevice(cat, @""), nil);
}

void test_network_reorder_puts_choice_first(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    NSArray<NSString *> *order = FCReorderServiceNamesFirst(cat, @"USB 10/100/1000 LAN");
    if (order.count == 0) {
        fprintf(stderr, "FAIL %s: reorder returned nothing\n", __func__);
        failures++;
        return;
    }
    expectEq(__func__, @"chosen first", order.firstObject, @"USB 10/100/1000 LAN");
}

void test_network_reorder_preserves_all_services(void) {
    // networksetup rejects the command unless EVERY service is listed, so the
    // reordered vector must be a permutation of the catalog, same length.
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    NSArray<NSString *> *order = FCReorderServiceNamesFirst(cat, @"Wired Adapter");
    expectCount(__func__, @"length preserved", order.count, cat.count);

    NSMutableSet *want = [NSMutableSet set];
    for (NSDictionary *e in cat) [want addObject:e[FCNetServiceName]];
    NSSet *got = [NSSet setWithArray:order];
    if (![got isEqualToSet:want]) {
        fprintf(stderr, "FAIL %s: reorder is not a permutation of the catalog\n", __func__);
        failures++;
    }
    // Relative order of the non-chosen services must be unchanged.
    expectEq(__func__, @"second stays Wi-Fi", order[1], @"Wi-Fi");
    expectEq(__func__, @"third stays USB LAN", order[2], @"USB 10/100/1000 LAN");
}

void test_network_reorder_rejects_unknown_service(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    if (FCReorderServiceNamesFirst(cat, @"Nonexistent") != nil) {
        fprintf(stderr, "FAIL %s: unknown service should return nil, not a bad list\n", __func__);
        failures++;
    }
    if (FCReorderServiceNamesFirst(cat, nil) != nil) {
        fprintf(stderr, "FAIL %s: nil service should return nil\n", __func__);
        failures++;
    }
    if (FCReorderServiceNamesFirst(@[], @"Wi-Fi") != nil) {
        fprintf(stderr, "FAIL %s: empty catalog should return nil\n", __func__);
        failures++;
    }
}

// A catalog dominated by USB modem-class pseudo-services, which is what a real
// machine actually looks like: on the development Mac, 15 of 19 services were
// of this kind (monitor control channels, phone USB links) and only 2 could
// carry traffic. They are enabled and DO have BSD device names, so structural
// filtering alone still offers them — only IPv4 liveness separates them.
static NSString *ModemHeavyOutput(void) {
    return @"An asterisk (*) denotes that a network service is disabled.\n"
            "(1) Peripheral Control\n"
            "(Hardware Port: Peripheral Control, Device: usbmodem0001)\n"
            "\n"
            "(2) Peripheral Control 2\n"
            "(Hardware Port: Peripheral Control 2, Device: usbmodem0002)\n"
            "\n"
            "(3) Wi-Fi\n"
            "(Hardware Port: Wi-Fi, Device: en0)\n"
            "\n"
            "(4) Wired Adapter\n"
            "(Hardware Port: Wired Adapter, Device: en5)\n";
}

void test_network_switchable_filters_deviceless_and_disabled(void) {
    NSArray *cat = FCParseNetworkServiceOrder(SampleOutput());
    // nil liveness ⇒ filter skipped, so this exercises the structural rules alone.
    NSArray *switchable = FCSwitchableServices(cat, nil);
    // 5 total - 1 deviceless (Tunnel) - 1 disabled (Legacy Bridge) = 3
    expectCount(__func__, @"switchable count", switchable.count, 3);
    for (NSDictionary *e in switchable) {
        NSString *n = e[FCNetServiceName];
        if ([n isEqualToString:@"Tunnel Service"]) {
            fprintf(stderr, "FAIL %s: deviceless service offered as switchable\n", __func__);
            failures++;
        }
        if ([n isEqualToString:@"Legacy Bridge"]) {
            fprintf(stderr, "FAIL %s: disabled service offered as switchable\n", __func__);
            failures++;
        }
    }
}

// The regression this filter exists for: a menu full of monitor-control and
// phone-USB entries the user cannot possibly route the internet through.
void test_network_switchable_excludes_dead_modem_services(void) {
    NSArray *cat = FCParseNetworkServiceOrder(ModemHeavyOutput());
    expectCount(__func__, @"catalog count", cat.count, 4);

    // Only the two real NICs hold an address.
    NSSet *live = [NSSet setWithArray:@[ @"en0", @"en5" ]];
    NSArray *switchable = FCSwitchableServices(cat, live);
    expectCount(__func__, @"switchable count", switchable.count, 2);
    for (NSDictionary *e in switchable) {
        NSString *d = e[FCNetServiceDevice];
        if ([d hasPrefix:@"usbmodem"]) {
            fprintf(stderr, "FAIL %s: dead modem service '%s' offered as switchable\n",
                    __func__, [e[FCNetServiceName] UTF8String]);
            failures++;
        }
    }
}

// Link-local is a legitimate route: a directly-attached device with no DHCP
// server still deserves to be selectable, so liveness must not imply routable.
void test_network_switchable_keeps_link_local_device(void) {
    NSArray *cat = FCParseNetworkServiceOrder(ModemHeavyOutput());
    // en5 carries only a 169.254.x address; it is still live, so still offered.
    NSArray *switchable = FCSwitchableServices(cat, [NSSet setWithArray:@[ @"en5" ]]);
    expectCount(__func__, @"switchable count", switchable.count, 1);
    expectEq(__func__, @"kept service", switchable[0][FCNetServiceName], @"Wired Adapter");
}

// nil and empty must NOT collapse to the same behaviour: nil means the liveness
// lookup failed (degrade to an over-full menu), empty means nothing is live
// (offer nothing). Conflating them would either wedge the picker or lie.
void test_network_switchable_nil_vs_empty_liveness(void) {
    NSArray *cat = FCParseNetworkServiceOrder(ModemHeavyOutput());
    expectCount(__func__, @"nil ⇒ unfiltered", FCSwitchableServices(cat, nil).count, 4);
    expectCount(__func__, @"empty ⇒ nothing",
                FCSwitchableServices(cat, [NSSet set]).count, 0);
}
