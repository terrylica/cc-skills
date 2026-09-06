// Shared width agreement for the overlay stack.
//
// THE PROBLEM. Each overlay used to size itself independently. The mic and VPN
// banners took the clock's width; the audio bar took its own content width
// floored at the clock width, so whenever a device name was long the audio bar
// grew and the stack developed ragged left and right edges — one rail visibly
// protruding past its neighbours. Adding the network bar made it worse, since
// that one is content-sized too.
//
// THE RULE. Every overlay is the SAME width: the widest content need any of
// them currently has, floored at the clock's width. The stack then reads as one
// column with flush edges, and no bar ever has to truncate to achieve it.
//
// Growing to the max (rather than shrinking everyone to the clock) is
// deliberate: the audio bar's width exists so a full device name never
// truncates, and the network bar's extra space carries live telemetry. Both
// would lose information under a shrink-to-fit rule.
//
// ORDERING. Overlays register during the 1 Hz tick and position themselves in
// the same pass, so a late registrant could otherwise leave an earlier one a
// tick stale. Any change to the agreed width therefore posts
// FCOverlayWidthConsensusDidChangeNotification, and each overlay re-syncs on
// it. That keeps the stack correct regardless of refresh order — no overlay
// needs to know which of its peers is currently the widest.
//
// Foundation-only (no AppKit), so it links into the headless test harness.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when the agreed width changes. Observers should call syncPosition.
extern NSString *const FCOverlayWidthConsensusDidChangeNotification;

@interface FCOverlayWidthConsensus : NSObject

+ (instancetype)shared;

// Record this overlay's natural content width. `key` identifies the overlay
// (its class name is fine). A width <= 0 is treated as "no need" — equivalent
// to clearOverlay:, so a hidden bar stops widening the stack.
- (void)setNeed:(CGFloat)width forOverlay:(NSString *)key;

// Withdraw an overlay's claim entirely; call when it hides.
- (void)clearOverlay:(NSString *)key;

// The agreed width: max(clockWidth, widest registered need). Passing a
// clockWidth of 0 yields the widest need alone, or 0 when nothing is
// registered — callers should treat that as "no constraint".
- (CGFloat)widthForClockWidth:(CGFloat)clockWidth;

// Test seam: drop all registrations so one test cannot leak into the next.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
