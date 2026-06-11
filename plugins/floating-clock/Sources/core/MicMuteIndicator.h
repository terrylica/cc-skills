// Mic-mute indicator — user directive 2026-06-01.
//
// Watches the CURRENT DEFAULT INPUT device's mute state — the CoreAudio
// mute flag (software mutes) OR sustained digital silence (the Antlion's
// analog hardware button) — and shows a red "MIC MUTED" banner pinned just
// above the floating clock whenever the ACTIVE mic is muted. Flips to
// just-below when the clock sits at the screen's top edge. Detection-only —
// no controls. Hidden entirely when unmuted.
//
// Why: the Antlion USB Microphone's inline button and macOS share the same
// UAC mute register (verified 2026-06-01), but there's no always-visible
// cue — so the user speaks into a muted mic unaware. This surfaces it on
// the always-on-top clock the user already watches.
//
// 2026-06-11 semantics flip (user bug report): previously bound to the
// NAMED device (the Antlion) whenever present, so the Antlion's hardware
// button falsely flagged the IN zone red while AirPods were the default
// input. Now binds default-input-first — a muted mic that is not the
// active input is irrelevant. The constructor's deviceName is only the
// fallback when the HAL reports no default input. Bluetooth-transport
// devices are never metered (a persistent IOProc would lock the headset
// into HFP/SCO call mode); their software mute flag is still read.
//
// Event-driven (AudioObjectAddPropertyListenerBlock on the main queue) —
// no polling, preserving the clock's sub-0.1% idle CPU budget. Survives
// device unplug/replug via a kAudioHardwarePropertyDevices listener and
// default-input changes via a kAudioHardwarePropertyDefaultInputDevice
// listener (plus a 1Hz drift backstop in -refresh).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class FCAudioStatusIndicator;  // always-visible audio I/O bar (2026-06-11)

@interface FCMicMuteIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel
                        deviceName:(NSString *)deviceName;

// When the always-visible audio I/O bar (2026-06-11) is showing, this banner
// stacks one slot higher so the two never overlap. Set once after init.
@property (nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;

// Re-read the live mute state AND reposition. Call from the clock's 1Hz tick.
// Polling here (not just relying on CoreAudio change-notifications) is what
// makes the banner track the HARDWARE mute button — many USB mics update the
// mute value without posting a property-listener notification, so a pure
// listener goes stale. One AudioObjectGetPropertyData per second is negligible.
- (void)refresh;

// Reposition the banner to track the clock (call from windowDidMove:).
// No-op while the mic is unmuted (banner hidden).
- (void)syncPosition;

// YES while the "MIC MUTED" banner is visible. Lets a second indicator
// (e.g. FCVPNStatusIndicator) stack itself directly above this bar.
- (BOOL)isShowing;

@end

NS_ASSUME_NONNULL_END
