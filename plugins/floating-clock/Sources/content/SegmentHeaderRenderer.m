#import "SegmentHeaderRenderer.h"

NSString *const kFCSegmentHRule = @"────────────────────────────────────────────";

void FCAppendSectionHeader(NSMutableAttributedString *out,
                           NSFont *font,
                           NSString *title,
                           NSString *legend,
                           NSColor *titleColor,
                           NSColor *dimColor,
                           NSColor *ruleColor) {
    // v4 iter-201: skip the title line when empty. Callers pass @""
    // to suppress the "ACTIVE MARKETS" / "NEXT TO OPEN" text now that
    // the iter-199 bottom-left [ACTIVE]/[NEXT] canonical labels serve
    // as the section identifier. Legend + hrule still render — they
    // describe the row format, not the section name.
    if (title.length > 0) {
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:[title stringByAppendingString:@"\n"]
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor}]];
    }
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
