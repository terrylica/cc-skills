// Vertically-centering NSTextFieldCell for multi-line attributed strings.
//
// NSTextFieldCell has no built-in vertical centering — multi-line text anchors
// to the cell top, and any extra frame height manifests as bottom whitespace.
// This subclass overrides drawingRectForBounds: to shift the drawing rect
// down by half the vertical slack, producing true vertical centering.
//
// Height measurement uses NSLayoutManager.usedRectForTextContainer — the
// authoritative answer for mixed-attribute text — and pads one line-height
// when the string ends with "\n" (an AppKit line-fragment quirk).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VerticallyCenteredTextFieldCell : NSTextFieldCell

- (CGFloat)measuredHeightForWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
