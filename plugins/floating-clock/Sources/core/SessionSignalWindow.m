#import "SessionSignalWindow.h"

NSInteger FCSessionSignalWindowMinutes(NSString *styleId) {
    if ([styleId isEqualToString:@"off"])   return 0;
    if ([styleId isEqualToString:@"5min"])  return 5;
    if ([styleId isEqualToString:@"15min"]) return 15;
    if ([styleId isEqualToString:@"30min"]) return 30;
    if ([styleId isEqualToString:@"60min"]) return 60;
    return 15;
}
