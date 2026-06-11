#import "SegmentBorderSpec.h"

FCSegmentBorderSpec FCSegmentBorderSpecForId(NSString *styleId) {
    if ([styleId isEqualToString:@"none"]) {
        return (FCSegmentBorderSpec){ .enabled = NO, .width = 0.0, .alpha = 0.0 };
    }
    if ([styleId isEqualToString:@"frame"]) {
        return (FCSegmentBorderSpec){ .enabled = YES, .width = 1.5, .alpha = 0.35 };
    }
    // "hairline" + nil/empty/unknown → the audio-bar recipe, on by default.
    return (FCSegmentBorderSpec){ .enabled = YES, .width = 1.0, .alpha = 0.22 };
}
