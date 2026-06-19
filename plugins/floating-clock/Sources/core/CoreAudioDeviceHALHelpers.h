// CoreAudio HAL device helpers — split from AudioStatusIndicator during the
// 2026-06-12 modularization (the indicator had breached the 500-line cap).
// THE canonical home for default-device reads/writes, device enumeration,
// volume, and mute-flag access used by the audio bar and its menus. All
// stack-allocated property reads — no per-call heap churn, safe at 1Hz.
//
// NOTE: MicMuteIndicator keeps its own narrower readers by design — its
// fallback semantics differ (see the 2026-06-12 DRY hunt disposition).
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

#ifdef __cplusplus
extern "C" {
#endif

AudioObjectID FCDefaultDevice(BOOL input);
void FCSetDefaultDevice(AudioObjectID dev, BOOL input);
NSString *_Nullable FCAudioDeviceName(AudioObjectID dev);
BOOL FCDeviceHasChannels(AudioObjectID dev, BOOL input);
BOOL FCReadInputMute(AudioObjectID dev);
// Output-scope (playback) mute on the default output device — the system mute
// the mute key / "set volume output muted" toggles. See the .m: unlike the
// input reader it must NOT gate on AudioObjectHasProperty (output-scope quirk).
BOOL FCReadOutputMute(AudioObjectID dev);
// Volume as 0.0–1.0, or -1 when the device exposes no volume control.
float FCReadVolume(AudioObjectID dev, BOOL input);
BOOL FCWriteVolume(AudioObjectID dev, BOOL input, float v);
// Virtual/aggregate transports (BackgroundMusic, loopbacks, multi-output).
BOOL FCDeviceIsVirtual(AudioObjectID dev);
// All REAL devices with channels in scope, name-sorted (NSNumber-boxed ids).
NSArray<NSNumber *> *_Nonnull FCDevicesForScope(BOOL input);

#ifdef __cplusplus
}
#endif
