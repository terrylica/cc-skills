#import "UrgencyHorizon.h"
#import "UrgencyColors.h"  // kFCUrgencyHorizonSecs sentinel default

NSInteger FCUrgencyHorizonMinutes(NSString *presetId) {
    if ([presetId isEqualToString:@"5min"])   return 5;
    if ([presetId isEqualToString:@"15min"])  return 15;
    if ([presetId isEqualToString:@"30min"])  return 30;
    if ([presetId isEqualToString:@"60min"])  return 60;
    if ([presetId isEqualToString:@"120min"]) return 120;
    if ([presetId isEqualToString:@"240min"]) return 240;
    return 60;  // matches iter-212 hardcoded kFCUrgencyHorizonSecs / 60
}

long FCUrgencyHorizonSecsCurrent(void) {
    NSString *id = [[NSUserDefaults standardUserDefaults] stringForKey:@"UrgencyHorizon"];
    // Fast-path: nil/empty falls through to default branch in
    // FCUrgencyHorizonMinutes which returns 60 → 3600 s, which equals
    // kFCUrgencyHorizonSecs. Either route is correct; we return the
    // SSoT constant for the unset case so a future tweak to the
    // constant cascades automatically.
    if (id.length == 0) return kFCUrgencyHorizonSecs;
    return (long)FCUrgencyHorizonMinutes(id) * 60L;
}
