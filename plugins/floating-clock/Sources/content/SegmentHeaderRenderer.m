#import "SegmentHeaderRenderer.h"

NSString *const kFCSegmentHRule = @"────────────────────────────────────────────";

void FCAppendSectionHeader(NSMutableAttributedString *out,
                           NSFont *font,
                           NSString *title,
                           NSString *legend,
                           NSColor *titleColor,
                           NSColor *dimColor,
                           NSColor *ruleColor) {
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:[title stringByAppendingString:@"\n"]
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor}]];
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:[legend stringByAppendingString:@"\n"]
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: dimColor}]];
    FCAppendDividerRule(out, font, ruleColor);
}

void FCAppendDividerRule(NSMutableAttributedString *out,
                         NSFont *font,
                         NSColor *ruleColor) {
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:[kFCSegmentHRule stringByAppendingString:@"\n"]
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: ruleColor}]];
}
