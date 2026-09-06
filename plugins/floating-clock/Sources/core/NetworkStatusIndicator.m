#import "NetworkStatusIndicator.h"
#import "NetworkBarZoneView.h"
#import "NetworkServiceCatalog.h"
#import "NetworkTelemetry.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import "ClockChildWindowAttachment.h"
#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "VPNStatusIndicator.h"
#import <SystemConfiguration/SystemConfiguration.h>

// Matches the other overlay rails so the stack reads as one column.
static const CGFloat kNetBarHeight = 20.0;
static const CGFloat kNetBarGap    = 3.0;
// Floor so a very short service name still yields a bar that reads as a rail
// rather than a chip. The content width itself now comes from the zone, which
// measures the strings it actually drew.
static const CGFloat kMinBarW      = 92.0;

static NSString *const kNetworksetupPath = @"/usr/sbin/networksetup";

@implementation FCNetworkStatusIndicator {
    __weak NSPanel      *_clock;
    NSPanel             *_bar;
    FCNetworkZoneView   *_zone;

    // Lazily-fetched, cached parse of `networksetup -listnetworkserviceorder`.
    // NEVER refreshed from the tick — see the header's refresh-model note.
    NSArray<NSDictionary<NSString *, id> *> *_catalog;

    NSString      *_primaryDevice;   // BSD name from SCDynamicStore, e.g. "en0"
    NSString      *_transientText;
    CFAbsoluteTime _transientUntil;
    CGFloat        _contentNeed;
    CGFloat        _lastBarW;

    // Throughput is a DERIVATIVE, so it needs the previous sample. Keyed by
    // device: when the route moves, the old counters belong to a different
    // interface and differencing across them would invent a burst of traffic.
    NSString      *_rateDevice;
    uint64_t       _prevRx;
    uint64_t       _prevTx;
    CFAbsoluteTime _prevSampleAt;
    double         _rxRate;
    double         _txRate;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _lastBarW = -1.0;
        [self buildBar];
        // Any peer overlay growing or shrinking changes the agreed stack width,
        // and this bar may already have positioned itself for the old one.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification
                                                   object:nil];
        [self refresh];
    }
    return self;
}

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"NetworkBarEnabled"];
}

- (BOOL)isShowing { return [self enabled]; }

#pragma mark Bar window

- (void)buildBar {
    NSRect r = NSMakeRect(0, 0, 200, kNetBarHeight);
    _bar = FCCreateOverlayPanel(_clock, r.size, NO);   // interactive

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    // Same dual-layer treatment as the other bars: hairline border defines the
    // edge on pure black where the panel shadow is invisible, elevated surface
    // separates the fill from #000, panel shadow handles light backgrounds.
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth     = 1.0;
    bg.layer.borderColor     = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _bar.contentView         = bg;

    _zone = [[FCNetworkZoneView alloc] initWithFrame:r owner:self];
    _zone.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [bg addSubview:_zone];

    [_bar orderOut:nil];   // shown on first refresh when enabled
}

#pragma mark Primary-interface read (in-process, tick-safe)

// BSD name of the interface currently carrying the default route, e.g. "en0".
// Pure SystemConfiguration — no subprocess, safe to call at 1 Hz.
- (NSString *)readPrimaryDevice {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("FloatingClock"), NULL, NULL);
    if (!store) return nil;
    NSString *primary = nil;
    CFPropertyListRef v = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
    if (v) {
        if (CFGetTypeID(v) == CFDictionaryGetTypeID()) {
            NSDictionary *d = (__bridge NSDictionary *)v;
            id iface = d[@"PrimaryInterface"];
            if ([iface isKindOfClass:[NSString class]]) primary = iface;
        }
        CFRelease(v);
    }
    CFRelease(store);
    return primary;
}

// BSD names of every interface that currently holds an IPv4 address. This is
// what separates a real route candidate from the crowd of USB modem-class
// pseudo-services macOS also registers (see FCSwitchableServices' header note).
//
// One SCDynamicStoreCopyMultiple pattern query, no subprocess. Returns nil —
// distinct from an empty set — when the lookup itself failed, so the caller can
// tell "nothing is live" apart from "we do not know".
- (NSSet<NSString *> *)readDevicesWithIPv4 {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("FloatingClock"), NULL, NULL);
    if (!store) return nil;

    NSArray *patterns = @[ @"State:/Network/Service/[^/]+/IPv4" ];
    CFDictionaryRef found = SCDynamicStoreCopyMultiple(store, NULL, (__bridge CFArrayRef)patterns);
    CFRelease(store);
    if (!found) return nil;

    NSMutableSet<NSString *> *devices = [NSMutableSet set];
    for (id value in [(__bridge NSDictionary *)found allValues]) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        id name = ((NSDictionary *)value)[@"InterfaceName"];
        if ([name isKindOfClass:[NSString class]] && [name length]) [devices addObject:name];
    }
    CFRelease(found);
    return devices;
}

// The switchable ring, freshly computed. Both user actions need exactly this
// pair of lookups, and keeping them together is what stops the liveness filter
// from being forgotten at one call site but not the other.
- (NSArray<NSDictionary<NSString *, id> *> *)switchableServices {
    return FCSwitchableServices([self catalogForcingRefresh:YES], [self readDevicesWithIPv4]);
}

#pragma mark Service catalog (lazy, subprocess-backed)

// Run `networksetup -listnetworkserviceorder` and parse it. Callers must only
// reach this off the tick path. Returns @[] on any failure — a missing binary
// or a changed output format must degrade, never throw.
- (NSArray<NSDictionary<NSString *, id> *> *)fetchCatalog {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:kNetworksetupPath]) return @[];

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:kNetworksetupPath];
    t.arguments = @[ @"-listnetworkserviceorder" ];
    NSPipe *out = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError  = [NSPipe pipe];

    NSError *err = nil;
    if (![t launchAndReturnError:&err]) return @[];
    NSData *data = [out.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (t.terminationStatus != 0) return @[];

    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return FCParseNetworkServiceOrder(s);
}

// Cached catalog, fetched on demand. `force` re-reads even when warm (used
// after a successful switch, since the order itself has changed).
- (NSArray<NSDictionary<NSString *, id> *> *)catalogForcingRefresh:(BOOL)force {
    if (force || _catalog.count == 0) {
        _catalog = [self fetchCatalog];
    }
    return _catalog;
}

#pragma mark Telemetry (in-process, tick-safe)

// Re-sample the interface counters and update the cached rates. Called once per
// tick; the rate is the delta over the ACTUAL elapsed time rather than an
// assumed 1 s, so a stalled or coalesced tick cannot inflate the reading.
- (void)sampleThroughputForDevice:(NSString *)device {
    uint64_t rx = 0, tx = 0;
    if (device.length == 0 || !FCReadInterfaceByteCounters(device, &rx, &tx)) {
        _rateDevice = nil;
        _rxRate = _txRate = 0.0;
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // First sample for this device establishes a baseline only — reporting a
    // rate now would divide a lifetime byte count by one tick.
    if (![device isEqualToString:_rateDevice] || _prevSampleAt == 0.0) {
        _rateDevice = [device copy];
        _prevRx = rx; _prevTx = tx; _prevSampleAt = now;
        _rxRate = _txRate = 0.0;
        return;
    }

    NSTimeInterval dt = now - _prevSampleAt;
    _rxRate = FCComputeByteRate(rx, _prevRx, dt);
    _txRate = FCComputeByteRate(tx, _prevTx, dt);
    _prevRx = rx; _prevTx = tx; _prevSampleAt = now;
}

static void FCAppend(NSMutableAttributedString *s, NSString *text, NSColor *color,
                     NSFontWeight weight) {
    if (text.length == 0) return;
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:text
        attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:weight],
                      NSForegroundColorAttributeName: color }]];
}

// The right-hand telemetry run: address · throughput · radio quality. Every
// field is omitted rather than faked when unavailable, so a wired link simply
// shows no signal group instead of a zeroed one.
- (NSAttributedString *)composeStatsForDevice:(NSString *)device {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    if (device.length == 0) return s;

    NSColor *dim   = [NSColor colorWithWhite:1.0 alpha:0.62];
    NSColor *down  = [NSColor colorWithSRGBRed:0.45 green:0.85 blue:0.55 alpha:1.0];
    NSColor *up    = [NSColor colorWithSRGBRed:0.45 green:0.72 blue:0.98 alpha:1.0];

    NSString *addr = FCPrimaryIPv4ForDevice(device);
    if (addr.length) FCAppend(s, addr, dim, NSFontWeightMedium);

    // Every numeric field below is padded to a CONSTANT character count. The
    // group is right-aligned, so an unpadded field that grows or shrinks drags
    // everything to its left along with it — throughput changes every second,
    // which made the address jitter once a second. Monospaced font ⇒ constant
    // character count is constant pixel width.
    if (s.length) FCAppend(s, @"   ", dim, NSFontWeightMedium);
    FCAppend(s, @"↓", down, NSFontWeightHeavy);
    FCAppend(s, FCPadLeft(FCFormatByteRate(_rxRate), FCByteRateFieldWidth), down, NSFontWeightMedium);
    FCAppend(s, @" ↑", up, NSFontWeightHeavy);
    FCAppend(s, FCPadLeft(FCFormatByteRate(_txRate), FCByteRateFieldWidth), up, NSFontWeightMedium);

    NSInteger rssi = 0, noise = 0;
    double txMbps = 0.0;
    if (FCReadWiFiStats(device, &rssi, &noise, &txMbps)) {
        // Colour by link health, so a marginal link is noticeable without
        // having to read the number.
        NSInteger bucket = FCSignalQualityBucket(rssi);
        NSColor *sig = (bucket == 2) ? [NSColor colorWithSRGBRed:0.45 green:0.85 blue:0.55 alpha:1.0]
                     : (bucket == 1) ? [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0]
                                     : [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0];
        // Widths chosen for the worst case each field can reach: RSSI down to
        // -100, SNR to two digits, PHY rate to four ("1361Mb").
        FCAppend(s, @"   ", dim, NSFontWeightMedium);
        FCAppend(s, [NSString stringWithFormat:@"%@dBm",
                     FCPadLeft([NSString stringWithFormat:@"%ld", (long)rssi], 4)],
                 sig, NSFontWeightHeavy);
        if (noise != 0) {
            // Signal-to-noise is the number that actually predicts whether a
            // link will hold, which raw RSSI alone does not.
            FCAppend(s, [NSString stringWithFormat:@" snr%@",
                         FCPadLeft([NSString stringWithFormat:@"%ld", (long)(rssi - noise)], 2)],
                     dim, NSFontWeightMedium);
        }
        if (txMbps > 0.0) {
            FCAppend(s, [NSString stringWithFormat:@" %@Mb",
                         FCPadLeft([NSString stringWithFormat:@"%.0f", txMbps], 4)],
                     dim, NSFontWeightMedium);
        }
    }
    return s;
}

#pragma mark Refresh (1 Hz tick driver)

- (void)refresh {
    if (![self enabled]) {
        FCHideOverlay(_bar);
        // Stop widening the stack while hidden, or the other rails would stay
        // padded to a width nothing is using.
        [[FCOverlayWidthConsensus shared] clearOverlay:NSStringFromClass(self.class)];
        return;
    }

    NSString *device = [self readPrimaryDevice];
    _primaryDevice = device;
    [self sampleThroughputForDevice:device];

    NSString *shown = [self transientText];
    BOOL degraded = (shown != nil);

    if (!shown) {
        NSString *name = FCServiceNameForBSDDevice(_catalog, device);
        // Cache miss: either first paint, or the primary moved to a device we
        // have never seen. Both are rare and user-visible, so a one-off
        // subprocess here is justified — the steady-state tick still spawns
        // nothing because the cache satisfies it.
        if (!name && device.length) {
            name = FCServiceNameForBSDDevice([self catalogForcingRefresh:YES], device);
        }
        if (name) {
            shown = name;
        } else if (device.length) {
            // Honest fallback: show the raw BSD name rather than inventing a
            // friendly label we cannot substantiate.
            shown = device;
            degraded = YES;
        } else {
            shown = @"(offline)";
            degraded = YES;
        }
    }

    // A degraded read means the identity is already suspect, so telemetry about
    // it would be noise at best and misleading at worst.
    NSAttributedString *stats = degraded ? nil : [self composeStatsForDevice:device];
    [_zone renderService:shown degraded:degraded stats:stats];

    // Measured from what the zone actually drew, so the published need can
    // never drift from the rendered content.
    _contentNeed = [_zone naturalContentWidth];
    if (_contentNeed < kMinBarW) _contentNeed = kMinBarW;
    [[FCOverlayWidthConsensus shared] setNeed:_contentNeed
                                   forOverlay:NSStringFromClass(self.class)];
    [self syncPosition];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || ![self enabled]) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    // TOP of the indicator stack: shift up one slot per visible junior, so
    // none of the existing three need to learn about this one. Stacking
    // POLICY lives here; the geometry SSoT is OverlayStackingPositioner.
    CGFloat slot = kNetBarHeight + kNetBarGap;
    CGFloat offset = 0.0;
    if (self.audioIndicator && [self.audioIndicator isShowing]) offset += slot;
    if (self.micIndicator   && [self.micIndicator   isShowing]) offset += slot;
    if (self.vpnIndicator   && [self.vpnIndicator   isShowing]) offset += slot;

    // Width is the STACK's agreed width, not this bar's own need, so every rail
    // shares one left and right edge. See OverlayWidthConsensus.h.
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kNetBarHeight, offset,
                                              kNetBarGap, agreed);
    if (!NSEqualRects(f, _bar.frame)) [_bar setFrame:f display:YES];
    if (fabs(f.size.width - _lastBarW) >= 0.5) {
        _lastBarW = f.size.width;
        _zone.frame = NSMakeRect(0, 0, f.size.width, kNetBarHeight);
        _zone.needsLayout = YES;
    }
    if (!_bar.visible) [_bar orderFront:nil];
    [_bar orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _bar);   // drag-welding; idempotent
}

#pragma mark User actions

- (void)cycleService {
    NSArray *sw = [self switchableServices];
    if (sw.count < 2) return;   // nothing to toggle to

    NSString *current = FCServiceNameForBSDDevice(_catalog, _primaryDevice);
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < sw.count; i++) {
        if ([sw[i][FCNetServiceName] isEqualToString:current]) { idx = i; break; }
    }
    // Primary not in the switchable ring (e.g. a VPN owns the route) → jump to
    // the first switchable service rather than wedging.
    NSUInteger next = (idx == NSNotFound) ? 0 : ((idx + 1) % sw.count);
    [self selectServiceNamed:sw[next][FCNetServiceName]];
}

- (NSMenu *)serviceSelectionMenu {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Network"];
    NSArray *sw = [self switchableServices];
    NSString *current = FCServiceNameForBSDDevice(_catalog, _primaryDevice);

    NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"ROUTE INTERNET VIA" action:NULL keyEquivalent:@""];
    hdr.enabled = NO;
    [m addItem:hdr];

    if (sw.count == 0) {
        NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No switchable services" action:NULL keyEquivalent:@""];
        none.enabled = NO;
        [m addItem:none];
        return m;
    }

    for (NSDictionary *e in sw) {
        NSString *name = e[FCNetServiceName];
        NSString *dev  = e[FCNetServiceDevice];
        NSMenuItem *it = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithFormat:@"%@  (%@)", name, dev]
                   action:@selector(networkMenuPick:)
            keyEquivalent:@""];
        it.target = self;
        it.representedObject = name;
        it.state = [name isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
        [m addItem:it];
    }
    return m;
}

- (void)networkMenuPick:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if ([name isKindOfClass:[NSString class]]) [self selectServiceNamed:name];
}

- (void)selectServiceNamed:(NSString *)name {
    if (name.length == 0) return;

    NSArray<NSString *> *order = FCReorderServiceNamesFirst([self catalogForcingRefresh:NO], name);
    // nil ⇒ the service is not in the catalog, so the command would certainly
    // be rejected. Refuse rather than run it.
    if (order.count == 0) {
        [self setTransientStatus:@"✗ unknown service" seconds:2.5];
        return;
    }

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:kNetworksetupPath];
    // Names contain spaces ("USB 10/100/1000 LAN") — pass as discrete
    // arguments, never a joined shell string.
    t.arguments = [@[ @"-ordernetworkservices" ] arrayByAddingObjectsFromArray:order];
    t.standardOutput = [NSPipe pipe];
    t.standardError  = [NSPipe pipe];

    NSError *err = nil;
    if (![t launchAndReturnError:&err]) {
        [self setTransientStatus:@"✗ launch failed" seconds:2.5];
        return;
    }
    [t waitUntilExit];
    if (t.terminationStatus != 0) {
        // Most likely cause on a non-admin account: macOS refused the change.
        [self setTransientStatus:@"✗ needs admin" seconds:3.0];
        return;
    }

    // The order changed, so the cached catalog is stale.
    [self catalogForcingRefresh:YES];
    [self refresh];
}

#pragma mark Transient status

- (void)setTransientStatus:(NSString *)status seconds:(NSTimeInterval)seconds {
    _transientText  = [status copy];
    _transientUntil = status ? (CFAbsoluteTimeGetCurrent() + seconds) : 0;
    [self refresh];
}

// Expiry is lazy — the 1 Hz tick calls refresh anyway, so no timer is needed.
- (NSString *)transientText {
    if (!_transientText) return nil;
    if (CFAbsoluteTimeGetCurrent() >= _transientUntil) {
        _transientText = nil;
        return nil;
    }
    return _transientText;
}

@end
