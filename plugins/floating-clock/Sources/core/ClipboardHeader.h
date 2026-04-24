// v4 iter-160: extracted from ActionHandlers.m's static fcCopyWithHeader
// helper. Used by the Copy cluster (Copy Time / Copy Active Markets /
// Copy Next Opens / Copy Clock State) to produce self-documenting
// clipboard output.
//
// Output format:
//   # Floating Clock · <label> · yyyy-MM-dd HH:mm:ss UTC\n<body>
//
// UTC in the stamp so snapshots stay unambiguous across the user's
// possibly-changed local zone. Empty body returns empty string —
// callers short-circuit without writing to the pasteboard.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure-function variant: returns the composed string given a "now" date.
// Tests pass a fixed date; ActionHandlers passes [NSDate date].
NSString *FCComposeClipboardSnapshot(NSString * _Nullable label,
                                     NSString * _Nullable body,
                                     NSDate * _Nullable now);

NS_ASSUME_NONNULL_END
