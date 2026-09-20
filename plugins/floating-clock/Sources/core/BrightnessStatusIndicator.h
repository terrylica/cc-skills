// Brightness rail — one continuous control from 0 % to 140 % of the built-in
// display's brightness.
//
// WHY: the macOS brightness slider stops at the panel's SDR maximum, but an
// Apple Liquid Retina XDR panel has substantial headroom above that which no
// first-party GUI exposes. This rail covers the ordinary range and the
// headroom in a single drag, with the hand-over at 100 % marked by a tick on
// the track. The engine and the full mechanism live in FCXDRBrightness.h.
//
//   · drag the track → set brightness (past the tick engages EDR boost)
//   · −/+ or scroll  → step by BrightnessBarStep
//   · right-click    → presets, including "Maximum safe"
//
// REFRESH MODEL: the 1 Hz tick makes one dlsym'd DisplayServices call and
// reads one NSScreen property — both in-process, comparable to the CoreAudio
// property reads the audio bar already does several times a second. It must
// never spawn a subprocess; that rule cost the network bar a redesign.
//
// SYSTEM MUTATION: this bar changes system-wide display state — the macOS
// brightness value (shared with F1/F2 and Control Center) and, while boosted,
// the display's gamma transfer table. Both are declared in the plugin's
// Touchpoints table. The gamma override is owned by this process and reverts
// automatically when it exits, including on SIGKILL.
//
// DEGRADATION: on a Mac whose built-in panel reports no extra EDR headroom,
// `maximumLevel` is 100 and the rail is an ordinary brightness slider. With
// no controllable built-in display at all (clamshell on an external monitor)
// the rail renders "--" and ignores input rather than pretending.
//
// NSUserDefaults (domain com.terryli.floating-clock):
//   BrightnessBarEnabled  BOOL  YES  master on/off (also in the context menu)
//   BrightnessBarStep     int   5    −/+ step size, 1..25
#import <Cocoa/Cocoa.h>

@class FCAudioStatusIndicator;
@class FCMicMuteIndicator;
@class FCVPNStatusIndicator;
@class FCNetworkStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCBrightnessStatusIndicator : NSObject

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;

// This rail sits at the TOP of the indicator stack, so it shifts up one slot
// per visible junior. Every indicator sums only its own juniors (see
// OverlayStackingPositioner.h), which is why the newcomer at the top is the
// one that has to ask all four. Set once after init; each is optional.
@property(nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
@property(nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;
@property(nonatomic, weak, nullable) FCVPNStatusIndicator *vpnIndicator;
@property(nonatomic, weak, nullable) FCNetworkStatusIndicator *networkIndicator;

// Re-read hardware brightness and reposition. Call from the 1 Hz tick.
- (void)refresh;

// Reposition to track the clock (call from windowDidMove:).
- (void)syncPosition;

// YES while the bar is visible, so other overlays can stack around it.
- (BOOL)isShowing;

// User actions, invoked by the zone view.
- (void)setLevel:(NSInteger)level;
- (void)adjustLevelBy:(NSInteger)delta;
- (void)cyclePreset;
- (NSMenu *)presetMenu;

@end

NS_ASSUME_NONNULL_END
