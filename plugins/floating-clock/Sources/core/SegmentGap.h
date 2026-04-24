// v4 iter-115: `FCSegmentGapPoints` — SegmentGap pref → gap in points.
//
// Extracted from Layout.m's inline if-else ladder so a test can lock
// iter-108's 7-preset catalog values. Layout.m calls this at every
// relayout pass for the ACTIVE+NEXT horizontal gap.
//
// Returns the gap width in points. Unknown / nil / empty ids fall
// back to 4pt (the registered "normal" default).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

CGFloat FCSegmentGapPoints(NSString * _Nullable gapId);

NS_ASSUME_NONNULL_END
