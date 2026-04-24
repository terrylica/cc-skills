#import "FloatingClockQuickStyles.h"

NSArray<NSArray *> *buildQuickStyles(void) {
    NSDictionary *brutalist = @{
        @"LocalTheme": @"high_contrast", @"ActiveTheme": @"high_contrast", @"NextTheme": @"high_contrast",
        @"CornerStyle": @"sharp", @"ShadowStyle": @"crisp", @"Density": @"compact",
        @"FontWeight": @"heavy", @"LetterSpacing": @"wide", @"LineSpacing": @"tight",
        @"TimeSeparator": @"dash",
    };
    NSDictionary *zen = @{
        @"LocalTheme": @"soft_glass", @"ActiveTheme": @"soft_glass", @"NextTheme": @"soft_glass",
        @"CornerStyle": @"soft", @"ShadowStyle": @"halo", @"Density": @"comfortable",
        @"FontWeight": @"regular", @"LetterSpacing": @"airy", @"LineSpacing": @"loose",
        @"TimeSeparator": @"space",
    };
    NSDictionary *retro = @{
        @"LocalTheme": @"amber_crt", @"ActiveTheme": @"amber_crt", @"NextTheme": @"amber_crt",
        @"CornerStyle": @"sharp", @"ShadowStyle": @"none", @"Density": @"compact",
        @"FontWeight": @"medium", @"LetterSpacing": @"tight", @"LineSpacing": @"tight",
        @"TimeSeparator": @"colon",
    };
    NSDictionary *executive = @{
        @"LocalTheme": @"paper_white", @"ActiveTheme": @"paper_white", @"NextTheme": @"paper_white",
        @"CornerStyle": @"rounded", @"ShadowStyle": @"subtle", @"Density": @"default",
        @"FontWeight": @"semibold", @"LetterSpacing": @"tight", @"LineSpacing": @"normal",
        @"TimeSeparator": @"colon",
    };
    // v4 iter-105: two more moods.
    NSDictionary *neon = @{
        @"LocalTheme": @"synthwave", @"ActiveTheme": @"synthwave", @"NextTheme": @"synthwave",
        @"CornerStyle": @"hairline", @"ShadowStyle": @"glow", @"Density": @"compact",
        @"FontWeight": @"heavy", @"LetterSpacing": @"wide", @"LineSpacing": @"tight",
        @"TimeSeparator": @"dash",
    };
    NSDictionary *hacker = @{
        @"LocalTheme": @"green_phosphor", @"ActiveTheme": @"green_phosphor", @"NextTheme": @"green_phosphor",
        @"CornerStyle": @"sharp", @"ShadowStyle": @"none", @"Density": @"compact",
        @"FontWeight": @"bold", @"LetterSpacing": @"tight", @"LineSpacing": @"tight",
        @"TimeSeparator": @"colon",
    };
    // v4 iter-106: two cool-palette moods.
    NSDictionary *glacier = @{
        @"LocalTheme": @"nord", @"ActiveTheme": @"nord", @"NextTheme": @"nord",
        @"CornerStyle": @"squircle", @"ShadowStyle": @"subtle", @"Density": @"comfortable",
        @"FontWeight": @"regular", @"LetterSpacing": @"normal", @"LineSpacing": @"normal",
        @"TimeSeparator": @"middot",
    };
    NSDictionary *midnight = @{
        @"LocalTheme": @"midnight_blue", @"ActiveTheme": @"midnight_blue", @"NextTheme": @"midnight_blue",
        @"CornerStyle": @"soft", @"ShadowStyle": @"halo", @"Density": @"default",
        @"FontWeight": @"medium", @"LetterSpacing": @"normal", @"LineSpacing": @"normal",
        @"TimeSeparator": @"colon",
    };

    return @[
        @[@"Brutalist", brutalist],
        @[@"Zen",       zen],
        @[@"Retro CRT", retro],
        @[@"Executive", executive],
        @[@"Neon",      neon],
        @[@"Hacker",    hacker],
        @[@"Glacier",   glacier],
        @[@"Midnight",  midnight],
    ];
}
