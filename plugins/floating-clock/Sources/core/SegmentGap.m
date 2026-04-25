#import "SegmentGap.h"

CGFloat FCSegmentGapPoints(NSString *gapId) {
    if ([gapId isEqualToString:@"flush"])     return 0;
    if ([gapId isEqualToString:@"tight"])     return 2;
    if ([gapId isEqualToString:@"snug"])      return 3;
    if ([gapId isEqualToString:@"cozy"])      return 6;   // iter-226
    if ([gapId isEqualToString:@"airy"])      return 8;
    if ([gapId isEqualToString:@"open"])      return 11;  // iter-226
    if ([gapId isEqualToString:@"spacious"])  return 14;
    if ([gapId isEqualToString:@"cavernous"]) return 24;
    return 4;  // "normal" default (also nil / unknown fallback)
}
