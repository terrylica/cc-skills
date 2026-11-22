// Power rail (2026-11-15) — the Mac's battery and Bluetooth on one 20 pt rail.
//
//   BAT 79% ⏸ -0.8W AC 60W ♥92% 236cy 30°  │ BT ● ⌃⌥⇧B  AirPods Pro L82 R80 C45 · Trackpad 64%
//
// Stack order 35 (OverlayStack.h): directly below the network rail. Off by default
// (PowerRailEnabled), because listing Bluetooth devices asks for the Bluetooth permission.
//
// Left (BAT): the percentage and its state glyph (⚡ charging, ⏸ held on AC below full, ✓ full,
// ▾ on battery), then the optional fields chosen under the rail's right-click "Show on Bar"
// (PowerRailBatteryFields: time, power, adapter, health, cycles, temp). Everything is also in the
// hover tooltip and the right-click menu, whichever fields the bar shows.
//
// Right (BT): the power dot (click: on/off), the shortcut tip, then each connected device and each
// paired device reporting a battery (click a name: connect or disconnect).
//
// Bluetooth power is also driven from outside: `floating-clock --bluetooth on|off|toggle` posts
// `<bundle id>.bluetooth.power` (userInfo {"state": on|off|toggle}), which the running app acts on,
// so the permission stays with the app however the request was made (a hotkey runs the CLI). The
// tip shows the chord of the hotkey that runs that command, read from PowerRailHotkeyRegistry (a
// JSON file the Typeless bridge writes; contract in PowerRailModel.h), so it follows a re-bind.
#import <Cocoa/Cocoa.h>
#import "OverlayStack.h"

@class FCAudioStatusIndicator, FCMicMuteIndicator, FCVPNStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCPowerStatusIndicator : NSObject <FCStackRail>
- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;
// The unregistered rails below this one, whose slots it counts itself (as the network rail does).
@property (nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
@property (nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;
@property (nonatomic, weak, nullable) FCVPNStatusIndicator *vpnIndicator;
- (void)refresh;        // 1 Hz tick
- (void)syncPosition;
- (BOOL)isShowing;
@end

// `floating-clock --bluetooth on|off|toggle`: posts the request to the running app and returns YES;
// NO when argv has no --bluetooth. A missing or unknown state prints usage and exits 64.
BOOL FCHandlePowerCommandLine(int argc, const char *_Nonnull argv[_Nonnull]);
NSString *FCBluetoothPowerNotificationName(void);

NS_ASSUME_NONNULL_END
