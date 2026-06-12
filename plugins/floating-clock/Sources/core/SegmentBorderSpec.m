#import "SegmentBorderSpec.h"
#import "RelativeLuminance.h"
#import <Cocoa/Cocoa.h>

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

void FCApplyBorderSpecToLayer(CALayer *layer, FCSegmentBorderSpec bs,
                              double bgR, double bgG, double bgB) {
    if (!bs.enabled) { layer.borderWidth = 0; return; }
    double lum = FCRelativeLuminance(bgR, bgG, bgB);
    NSColor *col = (lum < 0.5)
        ? [NSColor colorWithWhite:1.0 alpha:bs.alpha]
        : [NSColor colorWithWhite:0.0 alpha:bs.alpha + 0.08];
    layer.borderWidth = bs.width;
    layer.borderColor = col.CGColor;
}

