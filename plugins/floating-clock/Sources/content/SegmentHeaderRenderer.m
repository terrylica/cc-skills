#import "SegmentHeaderRenderer.h"

NSString *const kFCSegmentHRule = @"────────────────────────────────────────────";

// DRY 2026-06-12: one constructor for the colored-line pattern repeated at
// every append site (font + foreground color + trailing newline).
static NSAttributedString *fcColoredLine(NSString *text, NSFont *font, NSColor *color) {
    return [[NSAttributedString alloc]
        initWithString:[text stringByAppendingString:@"\n"]
            attributes:@{NSFontAttributeName: font,
                         NSForegroundColorAttributeName: color}];
}

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
        [out appendAttributedString:fcColoredLine(title, font, titleColor)];
    }
    [out appendAttributedString:fcColoredLine(legend, font, dimColor)];
    FCAppendDividerRule(out, font, ruleColor);
}

void FCAppendDividerRule(NSMutableAttributedString *out,
                         NSFont *font,
                         NSColor *ruleColor) {
    [out appendAttributedString:fcColoredLine(kFCSegmentHRule, font, ruleColor)];
}
