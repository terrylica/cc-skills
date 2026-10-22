// Output level tap (2026-10-15) — the live level of what the Mac is PLAYING, for the level-meter rail.
//
// macOS has no public "current output level" property (kAudioDevicePropertyVolumeScalar is the
// slider, not the signal), so this uses a Core Audio process tap (macOS 14.2+): a private global
// tap of all system output, unmuted (playback is untouched), inside a private aggregate device whose
// IOProc computes peak + RMS per buffer.
//
// Consequences, by design:
//  - Permission: "System Audio Recording Only" (NSAudioCaptureUsageDescription), asked once on the
//    first start. Denied => silent buffers; the meter then just reads zero.
//  - Privacy indicator: macOS shows its purple "system audio recording" dot while the tap runs.
//  - Gating: the tap runs ONLY while some other process is producing output
//    (kAudioProcessPropertyIsRunningOutput), and stops ~3 s after playback ends. That keeps the dot
//    honest and avoids coreaudiod's idle-sleep assertion during silence (FineTune#465).
//  - Rebuilt when the default output device or its sample rate changes (taps do not follow).
//
// Driven by -tick (1 Hz, from the clock tick), which only enqueues work: every HAL call runs on a
// private control queue, never on the main thread (cc-skills#37). The IOProc runs on its own queue and
// publishes through atomics; the UI reads with -readPeak:rms:.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCOutputLevelTap : NSObject
@property (nonatomic, readonly) BOOL running;
@property (nonatomic) BOOL enabled;          // master switch; NO stops and never starts
- (void)tick;                                 // gate on playback activity, rebuild on device change
// Peak and RMS (linear 0..1) of the buffers since the previous call. NO when nothing new arrived.
- (BOOL)readPeak:(float *)peak rms:(float *)rms;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
