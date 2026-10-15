// Level-meter rail (2026-10-15) — live input and output levels, the "jumping bars".
//
// A thin rail directly above the clock and below the audio I/O bar (stack order 5). Its two halves
// line up under the audio bar's IN and OUT zones: green LED cells for what the default input hears,
// blue for what the Mac is playing, amber above -12 dBFS and red above -3 dBFS, with a ~1 s peak-hold
// tick. Ballistics: FCMeterStep (LevelMeterMath.h).
//
// Sources:
//  - Input: the mic-mute indicator's existing IOProc (no second capture). Bluetooth inputs are never
//    metered (that would force the headset into call mode), so the IN half stays dark for them.
//  - Output: FCOutputLevelTap, a Core Audio process tap that runs only while something is playing
//    (purple privacy dot while it runs; one-time "System Audio Recording Only" permission).
//
// Cost: the 30 Hz animation timer runs only while either side has signal; silent = the 1 Hz tick only.
// Off by default in the public build (LevelMeterEnabled), because the output tap asks for a permission.
#import <Cocoa/Cocoa.h>
#import "OverlayStack.h"

@class FCAudioStatusIndicator, FCMicMuteIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCLevelMeterIndicator : NSObject <FCStackRail>
- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;
@property (nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
@property (nonatomic, weak, nullable) FCMicMuteIndicator *micIndicator;
- (void)refresh;        // 1 Hz tick: visibility, output-tap gating
- (void)syncPosition;   // windowDidMove: / width consensus
- (BOOL)isShowing;
@end

NS_ASSUME_NONNULL_END
