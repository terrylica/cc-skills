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


// Menu presentation pairs for the date-format catalog (label, id) — DRY
// 2026-06-12: this list was duplicated verbatim in the full-preferences
// menu AND the LOCAL segment menu. Living next to FCDateFormatPrefix keeps
// the format ids and their human labels in ONE file: add a format = one
// implementation branch + one row here, and every menu picks it up.
NSArray<NSArray<NSString *> *> *FCDateFormatMenuPairs(void);

NS_ASSUME_NONNULL_END
