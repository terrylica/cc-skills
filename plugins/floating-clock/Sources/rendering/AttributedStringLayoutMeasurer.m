#import "AttributedStringLayoutMeasurer.h"

NSSize FCMeasureAttributedUnwrapped(NSAttributedString *attr) {
    if (attr.length == 0) return NSZeroSize;
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:attr];
    NSTextContainer *container = [[NSTextContainer alloc]
        initWithContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [lm addTextContainer:container];
    [storage addLayoutManager:lm];
    container.lineFragmentPadding = 0.0;
    (void)[lm glyphRangeForTextContainer:container];
    NSSize s = [lm usedRectForTextContainer:container].size;
    NSString *str = attr.string;
    if (str.length > 0 && [str characterAtIndex:str.length - 1] == '\n') {
        NSFont *f = [attr attribute:NSFontAttributeName atIndex:str.length - 1 effectiveRange:NULL];
        if (!f) f = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        s.height += [lm defaultLineHeightForFont:f];
    }
    return s;
}
