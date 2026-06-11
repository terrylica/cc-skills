// Bluetooth paired-audio-device connector — user directive 2026-06-11.
//
// Bridges the gap the CoreAudio-only audio bar cannot see: PAIRED Bluetooth
// audio devices that are not currently connected to this Mac (powered off,
// out of range, or — the interesting case — connected to ANOTHER host such
// as an iPhone). CoreAudio's HAL only lists devices with live endpoints, so
// these are invisible to FCDevicesForScope until a baseband connection is
// opened.
//
// SOTA pattern (verified 2026-06-11 against blueutil / BluetoothConnector /
// BluetoothAudioReceiver — the FOSS canon for this problem):
//   · IOBluetooth is the ONLY public classic-BT API (CoreBluetooth = BLE
//     only, useless for A2DP/HFP audio). Native in-process calls — no
//     subprocess spawning, no daemons, zero steady-state cost.
//   · -openConnection: doubles as the TAKEOVER request: audio devices
//     (AirPods/W1/H1 especially, multipoint headsets generally) switch to
//     the most recent host that asks. BluetoothConnector exists precisely
//     because the W1 chip "doesn't make the switch from iPhone to Mac
//     seamless" — this is that fix, in-app.
//   · Connect ≠ audio routed: the CoreAudio endpoint appears ASYNC after
//     the baseband link opens. Callers must poll the HAL until the device
//     registers (see FCAudioDeviceSelectionMenuController).
//
// Requires NSBluetoothAlwaysUsageDescription in Info.plist (macOS 11+ TCC).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// One paired Bluetooth audio device as IOBluetooth sees it.
@interface FCBluetoothAudioDevice : NSObject
@property (nonatomic, copy)   NSString *name;           // BT display name
@property (nonatomic, copy)   NSString *addressString;  // "aa-bb-cc-dd-ee-ff"
@property (nonatomic, assign) BOOL connectedToThisMac;  // baseband link to US
@end

// success=NO ⇒ failureReason is a short human-readable cause.
typedef void (^FCBluetoothConnectCompletion)(BOOL success,
                                             NSString *_Nullable failureReason);

@interface FCBluetoothPairedAudioDeviceConnector : NSObject

// All PAIRED devices whose Bluetooth major device class is Audio/Video
// (headphones, headsets, speakers). Includes devices currently connected
// elsewhere — they read connectedToThisMac == NO. Name-sorted. Returns @[]
// when Bluetooth is off or TCC denies access (never nil, never throws).
+ (NSArray<FCBluetoothAudioDevice *> *)pairedAudioDevices;

// Open (or take over) the baseband connection to a paired device. Async;
// completion fires on the MAIN queue exactly once — on connect callback,
// immediate failure, or timeout, whichever comes first. Safe to call for a
// device already connected to this Mac (completes success immediately).
+ (void)connectDeviceWithAddress:(NSString *)addressString
                         timeout:(NSTimeInterval)timeoutSeconds
                      completion:(FCBluetoothConnectCompletion)completion;

@end

NS_ASSUME_NONNULL_END
