#import "SegmentOpacityResolver.h"

CGFloat FCResolveSegmentOpacity(NSString *segmentKey, CGFloat themeFallback) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Tier 1: per-segment key wins when explicitly set to a positive
    // value. A stored 0 is treated as "unset" so toggling the menu back
    // to an unset state (via pref removal) falls through cleanly.
    if (segmentKey.length > 0 && [d objectForKey:segmentKey]) {
        CGFloat v = [d doubleForKey:segmentKey];
        if (v > 0) {
            if (v < 0.10) v = 0.10;
            if (v > 1.00) v = 1.00;
            return v;
        }
    }

    // Tier 2: global CanvasOpacity.
    if ([d objectForKey:@"CanvasOpacity"]) {
        CGFloat v = [d doubleForKey:@"CanvasOpacity"];
        if (v > 0) {
            if (v < 0.10) v = 0.10;
            if (v > 1.00) v = 1.00;
            return v;
        }
    }

    // Tier 3: theme's built-in alpha.
    CGFloat v = themeFallback;
    if (v < 0.10) v = 0.10;
    if (v > 1.00) v = 1.00;
    return v;
}
