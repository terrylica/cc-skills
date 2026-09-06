// Network service catalog — pure parsing layer for the network picker bar.
//
// WHY THIS EXISTS AS ITS OWN AppKit-FREE MODULE
// Two independent enumerations of "network services" exist on macOS and they
// DISAGREE. Measured on a real machine while designing this feature:
//
//   SystemConfiguration  Setup:/Network/Service/*        22 services
//   networksetup         -listnetworkserviceorder        19 services
//
// SystemConfiguration additionally lists three "Ethernet Adapter (enN)"
// entries that networksetup omits, and where SystemConfiguration says
// "iPhone", networksetup says "iPhone USB".
//
// That matters because `networksetup -ordernetworkservices` takes SERVICE
// NAMES and requires ALL of them — a partial or mis-spelled list fails with
// "Wrong number of network services... No changes have been made." Driving it
// from SystemConfiguration names would therefore break on both count AND
// spelling. So networksetup's own listing is the single source of truth for
// names, and this module parses it.
//
// Kept free of AppKit (and of NSTask) so the parsing and ordering logic are
// pure functions over strings, unit-testable in the headless harness.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Keys in each catalog entry produced by FCParseNetworkServiceOrder.
extern NSString *const FCNetServiceName;      // NSString, e.g. @"Wi-Fi"
extern NSString *const FCNetServiceDevice;    // NSString BSD name, e.g. @"en0"; @"" when none
extern NSString *const FCNetServiceDisabled;  // NSNumber BOOL

// Parse the stdout of `networksetup -listnetworkserviceorder` into an ordered
// array of entries. Order is preserved exactly — index 0 is the highest
// priority service, which is what determines the default route.
//
// Tolerates: the leading "An asterisk (*) denotes..." header, the blank lines
// between records, services with no BSD device (VPN-style, e.g. Tailscale),
// and the "(*)" disabled marker. Returns @[] for nil/garbage input rather
// than throwing — a parse failure must never take the clock down.
NSArray<NSDictionary<NSString *, id> *> *FCParseNetworkServiceOrder(NSString *_Nullable output);

// Human service name whose BSD device matches `device` (e.g. @"en0" ->
// @"Wi-Fi"). nil when nothing matches — callers should fall back to showing
// the raw device name rather than inventing one.
NSString *_Nullable FCServiceNameForBSDDevice(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                              NSString *_Nullable device);

// The COMPLETE ordered list of service names with `chosenName` moved to the
// front and every other service kept in its existing relative order — exactly
// the argument vector `-ordernetworkservices` demands.
//
// Returns nil when `chosenName` is not in the catalog, so a caller can refuse
// to run a command that would certainly fail.
NSArray<NSString *> *_Nullable FCReorderServiceNamesFirst(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                                          NSString *_Nullable chosenName);

// Services a user could meaningfully switch TO. THREE conditions, all required:
// enabled, carrying a real BSD device, and currently holding an IPv4 address.
//
// The third condition is not fussiness — without it the picker is unusable.
// macOS registers every USB device that presents a modem/serial class as a
// network service, so a real machine's service list is dominated by things
// that can never carry traffic: monitor DDC control channels, phone USB
// links, composite-device endpoints. Measured on the development machine,
// `-listnetworkserviceorder` returned 19 services of which 15 were of that
// kind; only 3 held an IPv4 address. Offering the other 15 invites the user
// to reorder the route onto a dead service, which silently kills all
// connectivity — the precise failure this feature exists to prevent.
//
// The test is IPv4 liveness rather than a name pattern (e.g. matching
// "usbmodem") because names are vendor-controlled and would drift; liveness is
// what actually decides whether a service can carry the default route. Note it
// deliberately admits link-local 169.254.x addresses: a directly-attached
// device with no DHCP server is still a legitimate, selectable route.
//
// `liveDevices` is the set of BSD names holding IPv4 (see the indicator's
// SCDynamicStore reader). Pass nil ONLY when that lookup genuinely failed —
// the filter is then skipped, so a broken lookup degrades to an over-full menu
// instead of an empty one. An EMPTY set is meaningful and honoured: it means
// nothing is live, so nothing is offered.
NSArray<NSDictionary<NSString *, id> *> *FCSwitchableServices(NSArray<NSDictionary<NSString *, id> *> *catalog,
                                                              NSSet<NSString *> *_Nullable liveDevices);

NS_ASSUME_NONNULL_END
