#import "DensityPad.h"

CGFloat FCDensityPadPoints(NSString *densityId) {
    if ([densityId isEqualToString:@"ultracompact"]) return 4;
    if ([densityId isEqualToString:@"tight"])        return 8;   // iter-225
    if ([densityId isEqualToString:@"compact"])      return 12;
    if ([densityId isEqualToString:@"comfortable"])  return 36;
    if ([densityId isEqualToString:@"roomy"])        return 42;  // iter-225
    if ([densityId isEqualToString:@"spacious"])     return 48;
    if ([densityId isEqualToString:@"cavernous"])    return 64;
    return 24;  // "default" (also nil / unknown fallback)
}
