// Builds the attributed string shown in the ACTIVE segment — live markets
// grouped by IANA timezone, each with a state glyph + progress bar + countdown.
//
// Stateless: reads NSUserDefaults (ActiveTheme, ActiveBarCells) and
// iterates the compile-time kMarkets catalog. Returns a fresh attributed
// string every call.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSAttributedString *FCBuildActiveSegmentContent(void);

NS_ASSUME_NONNULL_END
