#import "UrgencyFlash.h"
#import "UrgencyColors.h"  // kFCUrgencyFlashDimAlpha sentinel default

CGFloat FCUrgencyFlashDimAlphaForId(NSString *presetId) {
    if ([presetId isEqualToString:@"off"])     return 1.0;
    if ([presetId isEqualToString:@"subtle"])  return 0.80;
    if ([presetId isEqualToString:@"normal"])  return 0.45;
    if ([presetId isEqualToString:@"intense"]) return 0.15;
    return kFCUrgencyFlashDimAlpha;  // matches iter-212 hardcoded default
}

CGFloat FCUrgencyFlashDimAlphaCurrent(void) {
    NSString *id = [[NSUserDefaults standardUserDefaults] stringForKey:@"UrgencyFlash"];
    if (id.length == 0) return kFCUrgencyFlashDimAlpha;
    return FCUrgencyFlashDimAlphaForId(id);
}

BOOL FCUrgencyFlashIsDisabled(void) {
    NSString *id = [[NSUserDefaults standardUserDefaults] stringForKey:@"UrgencyFlash"];
    return [id isEqualToString:@"off"];
}
