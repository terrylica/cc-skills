// v4 iter-113: `FCDateFormatPrefix` — the DateFormat preset dispatcher.
//
// Extracted from Runtime.m's static helper so tests can lock in
// the pattern strings for each preset id (especially iter-111's new
// locale-flavored entries). Runtime.m calls this at every tick for
// the LOCAL row's date prefix.
//
// Returns an NSDateFormatter pattern fragment with a trailing two-
// space gap (`"  "`) that separates the date from the time portion.
// Unknown / nil / empty ids fall back to `"short"` (`"EEE MMM d  "`).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *FCDateFormatPrefix(NSString * _Nullable presetId);

NS_ASSUME_NONNULL_END
