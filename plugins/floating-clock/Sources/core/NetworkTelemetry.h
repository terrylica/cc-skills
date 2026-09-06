// Live per-interface telemetry for the network bar.
//
// The bar was mostly empty space next to a service name, so it now carries the
// facts that actually matter when you are deciding whether a link is healthy or
// which one to route through: the address it holds, how much traffic is moving,
// and — on Wi-Fi — how good the radio link is.
//
// EVERYTHING HERE IS IN-PROCESS AND PERMISSION-FREE. That is a hard constraint,
// not a preference: this runs on the clock's 1 Hz tick, so a subprocess would
// wreck the idle-CPU budget and a permission prompt would ambush the user.
//
//   · Address + byte counters  getifaddrs(3) — plain syscall, no entitlement.
//   · RSSI / noise / Tx rate   CoreWLAN — VERIFIED to need no authorization.
//
// On the SSID, deliberately absent: CoreWLAN returns nil for -ssid unless the
// app holds Location authorization. That suits this bar exactly — the network
// NAME is the one field here that identifies a place or a person, so the bar
// shows link QUALITY instead and never asks for a permission it does not need.
//
// Split pure-from-impure on purpose: the rate arithmetic and the formatters are
// ordinary functions over numbers and are unit-tested, while the two readers
// that touch the system are thin and kept out of the test harness.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Pure: rate arithmetic and formatting

// Bytes/second between two counter samples `seconds` apart.
//
// Returns 0 for a non-positive interval, and ALSO when `now` < `previous`.
// That second case is real: interface counters reset when a device is
// re-plugged or the link renegotiates, and subtracting across a reset would
// otherwise produce a huge bogus spike right when the user is watching to see
// whether the link came back.
double FCComputeByteRate(uint64_t now, uint64_t previous, NSTimeInterval seconds);

// Compact fixed-width-ish rate label, e.g. @"0", @"940", @"1.2K", @"18M".
// Tuned for a status rail: at most one decimal, no unit suffix beyond the
// magnitude letter, so the bar does not jitter in width as traffic varies.
NSString *FCFormatByteRate(double bytesPerSecond);

// Left-pad with spaces to `width` characters (never truncates a longer string).
//
// WHY THE BAR NEEDS THIS. The telemetry group is right-aligned, so every field
// is positioned relative to the bar's right edge — which means a field that
// changes width pushes everything to its LEFT sideways. Throughput changes
// every second ("37K" → "108K" → "1.2M"), so without padding the address
// visibly jitters left and right once a second. The bar's font is monospaced,
// so padding to a constant character count is exactly a constant pixel width.
NSString *FCPadLeft(NSString *s, NSUInteger width);

// Character width every throughput field is padded to. The widest value this
// formatter can emit is 4 characters ("1.2M", "999", "45K"), so 4 is both
// sufficient and tight.
extern const NSUInteger FCByteRateFieldWidth;

// Wi-Fi signal quality bucket from RSSI in dBm, for colouring:
//   2 good (>= -60)   1 fair (-72 ..< -60)   0 poor (< -72)
// Thresholds match the conventional Wi-Fi planning bands: about -60 dBm is
// where high-rate links stay stable and about -72 dBm is where they start
// failing rather than merely slowing.
NSInteger FCSignalQualityBucket(NSInteger rssiDbm);

#pragma mark - Impure: system readers (no subprocess, no permission)

// Cumulative byte counters for a BSD device. NO on unknown device.
BOOL FCReadInterfaceByteCounters(NSString *bsdDevice, uint64_t *rxBytes, uint64_t *txBytes);

// First IPv4 address on a BSD device, or nil. Includes link-local 169.254.x —
// a directly-attached device with no DHCP server still has a real address, and
// hiding it would blank the bar in exactly the case the user most needs it.
NSString *_Nullable FCPrimaryIPv4ForDevice(NSString *bsdDevice);

// Wi-Fi radio stats for `bsdDevice`, when that device IS the Wi-Fi interface.
// Returns NO for wired devices or when CoreWLAN has nothing to report, leaving
// the outputs untouched. txRateMbps is the current PHY rate, not throughput.
BOOL FCReadWiFiStats(NSString *bsdDevice, NSInteger *rssiDbm, NSInteger *noiseDbm,
                     double *txRateMbps);

NS_ASSUME_NONNULL_END
