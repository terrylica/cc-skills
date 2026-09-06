// Network picker bar — shows which network service currently carries the
// machine's internet traffic, and lets the user switch it.
//
// WHY: macOS resolves the default route from the network SERVICE ORDER, not
// from anything the user picks per-session. A newly attached USB Ethernet
// adapter can silently outrank Wi-Fi and take over all traffic, which is
// invisible until something breaks. This bar surfaces that, and makes the
// choice one click instead of a trip through System Settings.
//
//   · Click the name  → switch to the next switchable service.
//   · Right-click     → pull-out menu of switchable services (✓ on current).
//
// REFRESH MODEL — the one hard performance constraint. The 1 Hz tick reads
// only SCDynamicStore (in-process, cheap). It NEVER spawns a subprocess;
// doing that once a second would destroy the clock's sub-0.1% idle CPU
// budget. The service-name map requires running `networksetup`, so it is
// fetched LAZILY — on first show, when a menu opens, and when the primary
// interface changes to a BSD device not already in the cache — then cached.
//
// SWITCHING spawns `/usr/sbin/networksetup -ordernetworkservices`. That is
// this app's ONLY subprocess and its only system mutation; both are declared
// in the plugin's Touchpoints table. On machines where the account is not an
// administrator the command may prompt or fail — failure is surfaced as a
// transient ✗ in the bar rather than being swallowed.
//
// NOTHING about a particular machine is hardcoded. Service names, BSD device
// names and the current primary are all discovered at runtime, so this file
// carries no personal configuration.
//
// NSUserDefaults (domain com.terryli.floating-clock):
//   NetworkBarEnabled  BOOL  YES  master on/off (also in the context menu)
#import <Cocoa/Cocoa.h>

@class FCMicMuteIndicator;
@class FCAudioStatusIndicator;
@class FCVPNStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCNetworkStatusIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;

// This bar sits at the TOP of the indicator stack, so it must shift up by one
// slot for each junior overlay that is currently showing. Every indicator
// sums only its own juniors (see OverlayStackingPositioner.h), which is why
// the newcomer at the top is the one that has to ask all three. Set once
// after init; each is optional.
@property (nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
@property (nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;
@property (nonatomic, weak, nullable) FCVPNStatusIndicator *vpnIndicator;

// Re-read the primary interface and reposition. Call from the 1 Hz tick.
- (void)refresh;

// Reposition to track the clock (call from windowDidMove:).
- (void)syncPosition;

// YES while the bar is visible, so other overlays can stack around it.
- (BOOL)isShowing;

// User actions, invoked by the zone view.
- (void)cycleService;
- (NSMenu *)serviceSelectionMenu;
- (void)selectServiceNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
