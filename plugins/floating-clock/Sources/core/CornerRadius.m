#import "CornerRadius.h"

CGFloat FCCornerRadiusPoints(NSString *cornerId, CGFloat width, CGFloat height) {
    if ([cornerId isEqualToString:@"sharp"])    return 0.0;
    if ([cornerId isEqualToString:@"hairline"]) return 1.0;
    if ([cornerId isEqualToString:@"micro"])    return 3.0;
    if ([cornerId isEqualToString:@"cushion"])  return 8.0;   // iter-224
    if ([cornerId isEqualToString:@"soft"])     return 10.0;
    if ([cornerId isEqualToString:@"squircle"]) return 14.0;
    if ([cornerId isEqualToString:@"chunky"])   return 18.0;  // iter-224
    if ([cornerId isEqualToString:@"jumbo"])    return 22.0;
    if ([cornerId isEqualToString:@"pill"]) {
        CGFloat shorter = width < height ? width : height;
        return shorter / 2.0;
    }
    return 6.0;  // "rounded" default (also nil / unknown fallback)
}
