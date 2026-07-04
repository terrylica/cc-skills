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
// Compact-mode layouts + solar canvas: FloatingClockPanel+CompactLayout.h
// (2026-06-12 modularization split).

@end

NS_ASSUME_NONNULL_END
