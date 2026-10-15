// Overlay stack registry (2026-10-15).
//
// The original rails each hard-code which rails sit below them ("juniors") and add one fixed
// 20+3 pt slot per visible junior. New rails (the level-meter strip, the external status rail)
// have their own heights and slot into the middle of the stack, so instead of teaching every
// rail about every newcomer, newcomers register here with an ORDER, and each rail adds
// `-offsetBelowOrder:` for its own order — the summed height+gap of every REGISTERED rail that
// is showing and sits lower. Existing juniors keep their old arithmetic; only registered rails
// flow through this registry.
//
// Order (bottom → top): clock · level meter (5) · audio I/O (10) · external status (15) ·
// mic-mute (20) · VPN (30) · network (40) · brightness (50) · TTS speed (60).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

static const NSInteger FCStackOrderLevelMeter     = 5;
static const NSInteger FCStackOrderAudio          = 10;
static const NSInteger FCStackOrderExternalStatus = 15;
static const NSInteger FCStackOrderMic            = 20;
static const NSInteger FCStackOrderVPN            = 30;
static const NSInteger FCStackOrderNetwork        = 40;
static const NSInteger FCStackOrderBrightness     = 50;
static const NSInteger FCStackOrderTTS            = 60;

@protocol FCStackRail <NSObject>
- (BOOL)isShowing;
- (CGFloat)railHeight;   // panel height; the registry adds the rail's gap
- (CGFloat)railGap;
@end

@interface FCOverlayStack : NSObject
+ (instancetype)shared;
- (void)registerRail:(id<FCStackRail>)rail order:(NSInteger)order;
// Summed (height + gap) of registered, showing rails whose order is < `order`.
- (CGFloat)offsetBelowOrder:(NSInteger)order;
// A registered rail's visibility or height changed: ask every rail to re-position now
// (posts FCOverlayWidthConsensusDidChangeNotification, which every rail already observes).
- (void)noteChanged;
@end

NS_ASSUME_NONNULL_END
