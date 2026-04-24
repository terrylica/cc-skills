// Builds the attributed string shown in the NEXT segment — top-N
// upcoming opens (closed markets sorted by seconds-to-next-open,
// plus lunch-resume markets from currently-on-lunch exchanges).
//
// Stateless: reads NSUserDefaults (NextTheme, NextItemCount) and iterates
// kMarkets. Returns a fresh attributed string every call.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSAttributedString *FCBuildNextSegmentContent(void);

NS_ASSUME_NONNULL_END
