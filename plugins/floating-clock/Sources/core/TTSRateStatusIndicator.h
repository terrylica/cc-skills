// TTS-rate rail — sets how fast a text-to-speech reader speaks, from 1× (its
// normal speed, the floor) to 3×, live.
//
// WHY: reading selected text aloud is often too slow to follow comfortably, and
// the right speed changes from minute to minute. The rail writes ONE number to a
// rate file (TTSRateFile, default ~/.config/floating-clock/tts-rate). A reader
// that follows that file re-reads it while speaking and applies the rate through
// a pitch-preserving time-stretch, so dragging the rail speeds up or slows down
// a reading already in progress. The file is also the persisted setting: the
// rail shows whatever it holds, including edits made by hand.
//
//   · drag the track → a detent (1, 1.25, 1.5, 1.75, 2, 2.5, 3)
//   · −/+            → step 0.25;  scroll → 0.05
//   · the 🔊 icon    → back to 1×
//   · right-click    → presets
//
// REFRESH MODEL: the 1 Hz tick stats the rate file and re-reads it only when its
// modification time changed. In-process, no subprocess.
//
// SYSTEM MUTATION: none outside the rate file. The rail never starts, stops or
// signals a reader. With no reader installed it is inert, so it ships OFF.
//
// NSUserDefaults (the app's own defaults domain):
//   TTSBarEnabled  BOOL     NO    master on/off (also in the context menu)
//   TTSRateFile    string   ~/.config/floating-clock/tts-rate
#import <Cocoa/Cocoa.h>

@class FCAudioStatusIndicator;
@class FCMicMuteIndicator;
@class FCVPNStatusIndicator;
@class FCNetworkStatusIndicator;
@class FCBrightnessStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCTTSRateStatusIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;

// TOP of the indicator stack: shifts up one slot per visible junior.
@property(nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
@property(nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;
@property(nonatomic, weak, nullable) FCVPNStatusIndicator *vpnIndicator;
@property(nonatomic, weak, nullable) FCNetworkStatusIndicator *networkIndicator;
@property(nonatomic, weak, nullable) FCBrightnessStatusIndicator *brightnessIndicator;

- (void)refresh;        // 1 Hz tick
- (void)syncPosition;   // windowDidMove:
- (BOOL)isShowing;

// User actions, invoked by the zone view.
- (void)setRate:(double)rate;
- (void)adjustRateBy:(double)delta;
- (NSMenu *)presetMenu;

@end

NS_ASSUME_NONNULL_END
