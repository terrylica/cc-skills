#import "ShadowSpec.h"

FCShadowSpec FCShadowSpecForId(NSString *shadowId) {
    if ([shadowId isEqualToString:@"subtle"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.35, 0, -2, 3};
    if ([shadowId isEqualToString:@"lifted"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.55, 0, -4, 6};
    if ([shadowId isEqualToString:@"glow"])
        return (FCShadowSpec){YES, FCShadowColorThemeForeground,  0.60, 0,  0, 6};
    if ([shadowId isEqualToString:@"crisp"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.85, 1, -1, 0};
    if ([shadowId isEqualToString:@"plinth"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.70, 0, -8, 10};
    if ([shadowId isEqualToString:@"halo"])
        return (FCShadowSpec){YES, FCShadowColorThemeBackground,  0.50, 0,  0, 10};
    // v4 iter-217: two new soft-diffuse presets fill the gap between
    // crisp/lifted (sharp + offset) and glow/halo (radial).
    //   vignette — cinematic atmospheric drop (large radius, low opacity)
    //   floating — wide diffuse hover (deep offset, soft edges)
    if ([shadowId isEqualToString:@"vignette"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.40, 0, -3,  18};
    if ([shadowId isEqualToString:@"floating"])
        return (FCShadowSpec){YES, FCShadowColorBlack,            0.30, 0, -12, 14};
    // "none" (default) + any unknown / nil / empty id.
    return (FCShadowSpec){NO, FCShadowColorBlack, 0, 0, 0, 0};
}
