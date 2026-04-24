// v4 iter-117: `FCCornerRadiusPoints` — CornerStyle pref → layer radius.
//
// Extracted from Layout.m's inline cornerRadiusFor block so iter-97's
// 8-preset catalog can be locked by the test suite. Unique to this
// dispatcher: the `pill` preset's radius depends on the segment's
// shorter axis, so the function takes width + height args.
//
// Unknown / nil / empty ids fall back to 6pt (the registered "rounded"
// default).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

CGFloat FCCornerRadiusPoints(NSString * _Nullable cornerId,
                              CGFloat width, CGFloat height);

NS_ASSUME_NONNULL_END
