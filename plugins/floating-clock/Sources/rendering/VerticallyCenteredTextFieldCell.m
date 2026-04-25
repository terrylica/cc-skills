#import "VerticallyCenteredTextFieldCell.h"

@implementation VerticallyCenteredTextFieldCell

- (CGFloat)measuredHeightForWidth:(CGFloat)width {
    NSAttributedString *attr = self.attributedStringValue;
    if (attr.length == 0) return 0;
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:attr];
    NSTextContainer *container = [[NSTextContainer alloc]
        initWithContainerSize:NSMakeSize(width > 0 ? width : FLT_MAX, FLT_MAX)];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [lm addTextContainer:container];
    [storage addLayoutManager:lm];
    container.lineFragmentPadding = 0.0;
    (void)[lm glyphRangeForTextContainer:container];
    CGFloat h = [lm usedRectForTextContainer:container].size.height;
    NSString *str = attr.string;
    if (str.length > 0 && [str characterAtIndex:str.length - 1] == '\n') {
        NSFont *f = [attr attribute:NSFontAttributeName atIndex:str.length - 1 effectiveRange:NULL];
        if (!f) f = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        h += [lm defaultLineHeightForFont:f];
    }
    return h;
}

// v4 iter-253d: small downward visual offset per user. NSCell coords
// are flipped (Y increases DOWN), so a POSITIVE offset shifts visible
// content downward. Compensates for cap-height midpoint sitting above
// the line-height geometric center.
static const CGFloat kFCVCenterDownNudgeY = +3.0;

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    CGFloat measured = [self measuredHeightForWidth:theRect.size.width];
    if (measured <= 0) return theRect;
    CGFloat heightDelta = theRect.size.height - measured;
    if (heightDelta > 0) {
        theRect.origin.y += heightDelta / 2.0 + kFCVCenterDownNudgeY;
        theRect.size.height = measured;
    }
    return theRect;
}

@end
