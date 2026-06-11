// Audio device selection pull-out menu — user directive 2026-06-11.
//
// Right-click / two-finger-tap / ctrl-click on either audio-bar zone pops a
// context menu for DIRECT device selection (the left-click cycle toggle is
// untouched). The IN and OUT zones get fully independent menus.
//
// Menu anatomy per zone:
//   INPUT DEVICE              (header, disabled)
//   ✓ Antlion USB             ← live CoreAudio devices; click = switch now
//     MacBook Pro Microphone
//   ───────────────────────
//   BLUETOOTH — CONNECT       (header; only when offline paired BT exists)
//   ○ AirPods Pro             ← paired but not connected here; click =
//                               openConnection (TAKEOVER from iPhone et al.)
//                               → poll HAL until endpoint appears → switch
//
// Connect orchestration mirrors the FOSS canon (blueutil / SwitchAudioSource
// loop): baseband connect first, then bounded 0.5s-step polling for the
// CoreAudio endpoint, with transient ⏳/✗ status rendered in the bar zone.
#import <Cocoa/Cocoa.h>

@class FCAudioStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCAudioDeviceSelectionMenuController : NSObject

- (instancetype)initWithIndicator:(FCAudioStatusIndicator *)indicator;

// Build the menu for one zone. Called from the zone's -menuForEvent:, which
// AppKit invokes for right-click, two-finger tap, AND ctrl-click — all three
// activation gestures in the directive, for free.
- (NSMenu *)menuForInput:(BOOL)isInput;

// Scope-independence guard bookkeeping (2026-06-11 fix). macOS auto-routes
// the OTHER scope's default to a Bluetooth device the moment it connects
// (verified: AirPods are TWO AudioObjects — 24kHz HFP mic + 48kHz A2DP out —
// and selecting only the input still flipped the output, because coreaudiod
// is a second writer, not because the defaults are bound). After a menu
// connect, this controller watches the other scope for ~8s and restores the
// pre-connect default if it was hijacked BY THE CONNECTED DEVICE. Any
// explicit user selection in that scope cancels the guard — call this from
// every user-initiated device switch (the left-click cycle included).
- (void)noteExplicitDeviceSelectionForInput:(BOOL)isInput;

@end

NS_ASSUME_NONNULL_END
