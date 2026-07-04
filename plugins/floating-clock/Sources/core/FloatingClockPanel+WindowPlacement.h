// Category: window placement + persistence for FloatingClockPanel.
//
//   primaryScreen              screens[0] (stable across hot-plug)
//   defaultFrame               bottom-center of primary
//   clampFrameToVisibleScreen  keep window inside visibleFrame
//   windowDidMove:             persist frame + screen number, re-sync bars
//   restorePosition            load saved frame with screen check
//   screensChanged:            hot-unplug re-home
//
// Split from FloatingClockPanel+Runtime (2026-06-12 modularization);
// Runtime keeps the timer + tick pipeline.
#import "FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (WindowPlacement)

- (NSScreen *)primaryScreen;
- (NSRect)defaultFrame;
- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed;
- (void)windowDidMove:(NSNotification *)n;
- (void)restorePosition;
- (void)screensChanged:(NSNotification *)n;

@end

NS_ASSUME_NONNULL_END
