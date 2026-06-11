// Audio I/O status bar — user directive 2026-06-11.
//
// Always-visible (default ON) interactive bar pinned directly above the
// floating clock showing the CURRENT default input and output audio devices
// plus their volume levels as numbers (0–100). Replaces the decommissioned
// com.terryli.audio-device-monitor launchd service's automatic "plug and
// play" prioritization with fully MANUAL, clock-centric control:
//
//   · Click a device NAME   → switch that category (input/output,
//                             independently) to the next available device.
//   · Click the − / + glyphs → nudge that category's volume by AudioBarStep
//                             percent (default 5).
//   · Scroll over a zone    → fine-adjust that category's volume (±2/notch).
//
// Detection + control are both dynamic CoreAudio HAL reads — nothing is
// hardcoded to specific device names and NOTHING auto-switches. The bar is
// the bottom-most overlay in the indicator stack; the mic-mute bar and the
// VPN bar stack above it (see MicMuteIndicator / VPNStatusIndicator).
//
// Refresh model: driven from the clock's 1 Hz tick (6 cheap HAL property
// reads per second — no IOProcs, no listeners, no polling daemons),
// preserving the clock's sub-0.1% idle CPU budget. User-initiated changes
// re-read immediately for instant feedback.
//
// NSUserDefaults (domain com.terryli.floating-clock):
//   AudioBarEnabled  BOOL  YES   master on/off (always visible by default)
//   AudioBarStep     int   5     ± click step in percent (clamped 1–25)
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCAudioStatusIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;

// Re-read default devices + volumes and reposition. Call from the 1Hz tick.
- (void)refresh;

// Reposition the bar to track the clock (call from windowDidMove:).
- (void)syncPosition;

// YES while the bar is visible. Lets the mic-mute / VPN indicators stack
// themselves above this bar.
- (BOOL)isShowing;

// User actions (invoked by the zone views; exposed for testability).
- (void)cycleDeviceForInput:(BOOL)isInput;
- (void)adjustVolumeForInput:(BOOL)isInput byPercent:(NSInteger)deltaPercent;

@end

NS_ASSUME_NONNULL_END
