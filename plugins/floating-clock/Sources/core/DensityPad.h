// v4 iter-116: `FCDensityPadPoints` — Density pref → inner-row padding.
//
// Extracted from Layout.m's inline if-else ladder so iter-99's
// 6-preset catalog can be locked by the test suite. Layout.m calls
// this at every relayout pass for the pad added to segment row
// heights + widths.
//
// Returns padding in points. Unknown / nil / empty ids fall back to
// 24pt (the registered "default" preset).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

CGFloat FCDensityPadPoints(NSString * _Nullable densityId);

NS_ASSUME_NONNULL_END
