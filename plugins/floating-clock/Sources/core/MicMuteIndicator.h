// Mic-mute indicator — user directive 2026-06-01.
//
// Watches one specific input device's CoreAudio mute state
// (kAudioDevicePropertyMute, input scope) and shows a red "MIC MUTED"
// banner pinned just above the floating clock whenever that mic is muted.
// Flips to just-below when the clock sits at the screen's top edge.
// Detection-only — no controls. Hidden entirely when unmuted.
//
// Why: the Antlion USB Microphone's inline button and macOS share the same
// UAC mute register (verified 2026-06-01), but there's no always-visible
// cue — so the user speaks into a muted mic unaware. This surfaces it on
// the always-on-top clock the user already watches.
//
// Event-driven (AudioObjectAddPropertyListenerBlock on the main queue) —
// no polling, preserving the clock's sub-0.1% idle CPU budget. Survives
// device unplug/replug via a kAudioHardwarePropertyDevices listener.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCMicMuteIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel
                        deviceName:(NSString *)deviceName;

// Re-read the live mute state AND reposition. Call from the clock's 1Hz tick.
// Polling here (not just relying on CoreAudio change-notifications) is what
// makes the banner track the HARDWARE mute button — many USB mics update the
// mute value without posting a property-listener notification, so a pure
// listener goes stale. One AudioObjectGetPropertyData per second is negligible.
- (void)refresh;

// Reposition the banner to track the clock (call from windowDidMove:).
// No-op while the mic is unmuted (banner hidden).
- (void)syncPosition;

@end

NS_ASSUME_NONNULL_END
