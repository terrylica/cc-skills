// v4 iter-90 per-segment canvas-opacity resolver.
//
// Separate from FontResolver because opacity is theme-state, not font
// resolution. Same 3-tier fallback pattern as FCResolveSegmentWeight:
//   1. NSUserDefaults[segmentKey] (LocalOpacity / ActiveOpacity / NextOpacity)
//      when present and > 0
//   2. NSUserDefaults[@"CanvasOpacity"] when present
//   3. themeFallback (the ClockTheme struct's `alpha` field)
//
// The returned value is pre-clamped to [0.10, 1.00] so callers can
// assign it directly to layer.backgroundColor without re-validating.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

CGFloat FCResolveSegmentOpacity(NSString *segmentKey, CGFloat themeFallback);

NS_ASSUME_NONNULL_END
