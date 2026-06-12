// Category: compact-mode (legacy) layouts + the solar canvas painter.
//
//   applyLocalOnlyLayout      single-line legacy mode
//   applySingleMarketLayout   two-line legacy mode
//   refreshSolarCanvasForced: solar-elevation background (compact modes)
//
// Split from FloatingClockPanel+Layout (2026-06-12 modularization). The
// three-segment family and the applyDisplaySettings dispatcher remain in
// the Layout category; this file owns everything whose canvas is the
// window contentView pill.
#import "FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (CompactLayout)

- (void)applyLocalOnlyLayout;
- (void)applySingleMarketLayout;

// Recolor the compact modes' background from the live solar elevation at
// the user's location (CanvasColorMode pref). No-op in three-segment mode
// or when the mode is "theme". force=NO from the 1Hz tick (quantized);
// force=YES from layout passes (invalidates the quantization cache).
- (void)refreshSolarCanvasForced:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
