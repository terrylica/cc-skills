// The interactive half of the TTS-rate rail.
//
// Hit regions, left → right:
//   [🔊][ track with 7 detent ticks .............][−][ 1.5× ][+]
//
//   · click / drag the track → the nearest detent (1, 1.25, 1.5, 1.75, 2, 2.5, 3)
//   · −/+                    → step 0.25
//   · the number             → top half up, bottom half down (0.25)
//   · scroll                 → fine adjust, 0.05
//   · right-click            → presets
//
// Same house pattern as the brightness rail: a drawn track, a _renderKey
// composite so the 1 Hz tick allocates nothing at steady state, and -hitTest:
// routing every click here because NSTextField subviews would swallow them.
#import <Cocoa/Cocoa.h>

@class FCTTSRateStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCTTSRateZoneView : NSView

@property(nonatomic, weak) FCTTSRateStatusIndicator *owner;

- (instancetype)initWithFrame:(NSRect)frame owner:(FCTTSRateStatusIndicator *)owner;

/// Apply the current rate. Returns YES when the visible composite changed.
- (BOOL)renderRate:(double)rate;

/// Natural width of the drawn content (width-consensus contract).
- (CGFloat)naturalContentWidth;

@end

NS_ASSUME_NONNULL_END
