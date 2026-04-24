// Authoritative unwrapped multi-line measurement (width + height) for
// NSAttributedString with mixed per-range font/color attributes.
//
// NSAttributedString.size / boundingRectWithSize / NSCell.cellSizeForBounds all
// mismeasure mixed-attribute multi-line content. Only
// NSLayoutManager.usedRectForTextContainer (after forced layout) is correct.
//
// AppKit quirk: usedRectForTextContainer does NOT include the trailing line
// fragment when the string ends with "\n" — this function compensates by
// adding one defaultLineHeightForFont when the final character is a newline.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSSize FCMeasureAttributedUnwrapped(NSAttributedString *attr);

NS_ASSUME_NONNULL_END
