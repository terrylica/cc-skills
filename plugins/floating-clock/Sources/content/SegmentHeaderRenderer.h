// Shared table-layout helpers used by both ACTIVE and NEXT segment
// content builders. Extracted in v4 iter-73 to eliminate duplication
// of the "title + legend + hrule" opening block and the inter-row
// hrule divider — both sections now render as sibling tabulated
// tables via these helpers.
//
// The hrule glyph is U+2500 '─' × 44, a width that comfortably fits
// the NEXT/ACTIVE segment bounds at 11pt without wrapping. Kept as a
// compile-time constant so both callers stay synchronized.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kFCSegmentHRule;

// Append "TITLE\nlegend\nhrule\n" — the section-opening block.
void FCAppendSectionHeader(NSMutableAttributedString *out,
                           NSFont *font,
                           NSString *title,
                           NSString *legend,
                           NSColor *titleColor,
                           NSColor *dimColor,
                           NSColor *ruleColor);

// Append "hrule\n" — used between group/entry rows.
void FCAppendDividerRule(NSMutableAttributedString *out,
                         NSFont *font,
                         NSColor *ruleColor);

NS_ASSUME_NONNULL_END
