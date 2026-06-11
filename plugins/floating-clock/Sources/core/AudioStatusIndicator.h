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
//
// 2026-06-11 pull-out menus: right-click / two-finger tap / ctrl-click on a
// zone pops an independent device-selection menu (live CoreAudio devices +
// paired-but-offline Bluetooth audio devices that connect-then-switch, incl.
// takeover from another host). See AudioDeviceSelectionMenuController.
#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>

@class FCMicMuteIndicator;   // mic-mute red-state source (2026-06-11 extras)

NS_ASSUME_NONNULL_BEGIN

@interface FCAudioStatusIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;

// 2026-06-11 extras (user-selected): when set, the IN zone renders red with
// a struck-through device name while the mic is muted — same OR'd signal the
// big "MIC MUTED" banner uses (CoreAudio mute flag OR analog-silence meter)
// plus a direct mute-flag read on the current default input. Set once after
// the mic indicator is created.
@property (nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;

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

#pragma mark Device-selection menu support (2026-06-11 pull-out menus)

// Pull-out menu for one zone — built fresh per right-click so the device
// list is always current. Zones return this from -menuForEvent:.
- (NSMenu *)deviceSelectionMenuForInput:(BOOL)isInput;

// Live (CoreAudio HAL) real devices in scope: @{ @"id": AudioObjectID as
// NSNumber, @"name": NSString }. Name-sorted, virtual/aggregate excluded —
// the same ring the left-click cycle walks.
- (NSArray<NSDictionary<NSString *, id> *> *)liveDevicesForInput:(BOOL)isInput;

- (AudioObjectID)currentDefaultDeviceForInput:(BOOL)isInput;

// Set the system default for the scope + refresh instantly.
- (void)selectDeviceID:(AudioObjectID)devID forInput:(BOOL)isInput;

// First live device whose name matches (case-insensitive, containment both
// ways — BT nicknames vs HAL names). 0 = no match.
- (AudioObjectID)liveDeviceIDMatchingName:(NSString *)name forInput:(BOOL)isInput;

// YES while the HAL still knows this ID — ANY transport, virtual included
// (hijack-guard restore targets may legitimately be Background Music etc.).
// HAL IDs are reassigned on unplug/replug, so cached IDs must be re-probed
// before use.
- (BOOL)deviceIDStillExists:(AudioObjectID)devID;

// Transient status text rendered in place of the device name (⏳ connecting /
// ✗ failed). nil clears immediately; otherwise auto-expires after `seconds`.
- (void)setTransientStatus:(nullable NSString *)status forInput:(BOOL)isInput seconds:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
