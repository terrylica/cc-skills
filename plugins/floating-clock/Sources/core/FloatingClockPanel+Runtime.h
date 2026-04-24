// Category: runtime-side of FloatingClockPanel — the 1Hz tick pipeline and
// the window-positioning helpers (default-frame, clamp, restore, hot-unplug).
//
// Tick pipeline:
//   setupTimer        dispatch_source_t aligned to second boundary
//   tick              dispatches on DisplayMode
//   tickThreeSegment  LOCAL + ACTIVE + NEXT content + relayout
//   tickLegacy        single-market / local-only legacy paths
//
// Positioning:
//   primaryScreen              screens[0] (stable across hot-plug)
//   defaultFrame               bottom-center of primary
//   clampFrameToVisibleScreen  keep window inside visibleFrame
//   windowDidMove:             persist frame + screen number
//   restorePosition            load saved frame with screen check
//   screensChanged:            hot-unplug re-home
#import "FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (Runtime)

- (void)setupTimer;
- (NSScreen *)primaryScreen;
- (void)windowDidMove:(NSNotification *)n;
- (void)restorePosition;
- (void)screensChanged:(NSNotification *)n;

@end

NS_ASSUME_NONNULL_END
