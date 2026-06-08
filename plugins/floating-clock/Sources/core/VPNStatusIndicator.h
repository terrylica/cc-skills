// Generic external-state status banner for the floating clock.
//
// Shows a colored bar (default violet) above the clock — and above the
// mic-mute bar when that one is visible — whenever an external "active"
// state file exists on disk. It is deliberately GENERIC and secret-free:
// it has no idea what the state represents (a VPN, a tunnel, a build, …).
// Everything is configured via NSUserDefaults, and it is DISABLED by
// default, so the public build ships inert until a deployment opts in.
//
// Defaults domain (com.terryli.floating-clock):
//   VPNIndicatorEnabled   BOOL    default NO   — master on/off
//   VPNIndicatorStateFile string  default ~/.config/floating-clock/vpn-active
//                                  — the bar shows iff this path exists
//   VPNIndicatorLabel     string  default "VPN"      — bar text
//   VPNIndicatorColorHex  string  default "#8B2FE6"  — bar color (#RRGGBB)
//
// Mirrors FCMicMuteIndicator's banner mechanics (AppKit NSPanel + CALayer,
// 1 Hz refresh off the clock tick). Detection-only; no controls.
#import <Cocoa/Cocoa.h>

@class FCMicMuteIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCVPNStatusIndicator : NSObject

// micIndicator is optional; when provided, this bar stacks directly above
// the mic-mute bar while that one is showing (else above the clock).
- (instancetype)initWithClockPanel:(NSPanel *)clockPanel
                      micIndicator:(nullable FCMicMuteIndicator *)micIndicator;

// Re-read the live state (defaults + state-file existence) AND reposition.
// Call from the clock's 1 Hz tick.
- (void)refresh;

// Reposition the banner to track the clock (call from windowDidMove:).
// No-op while inactive (banner hidden).
- (void)syncPosition;

@end

NS_ASSUME_NONNULL_END
