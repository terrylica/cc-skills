// Category: layout / display-settings methods for FloatingClockPanel.
//
//   applyDisplaySettings      dispatches on DisplayMode pref
//   applyThreeSegmentLayout   lazy-create segments, theme them, run relayout
//   relayoutThreeSegmentIfNeeded   per-tick resize when content height changes
//   applyLocalOnlyLayout      single-line legacy mode
//   applySingleMarketLayout   two-line legacy mode
//
// Lives as an Objective-C category so clock.m's main @implementation
// doesn't carry the layout mass. Methods are declared here (not in the
// main @interface) to avoid -Wincomplete-implementation warnings.
#import "FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (Layout)

- (void)applyDisplaySettings;
- (void)applyThreeSegmentLayout;
- (void)relayoutThreeSegmentIfNeeded;
- (void)applyLocalOnlyLayout;
- (void)applySingleMarketLayout;

// 2026-06-11 solar canvas: recolor the compact modes' background from the
// live solar elevation at the user's location (CanvasColorMode pref).
// No-op in three-segment mode or when the mode is "theme". Call with
// force=NO from the 1Hz tick (quantized — skips redundant writes) and
// force=YES from layout passes (invalidates the quantization cache so a
// mode/theme switch always repaints).
- (void)refreshSolarCanvasForced:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
