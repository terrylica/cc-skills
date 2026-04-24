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
        @"SessionSignalWindow": @"off",  // iter-158: minimalism — no auction glyphs
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
    // v4 iter-130: two moods exercising iter-129's new thin/black weight
    // extremes. Showcasing what the expanded 7-preset range opens up.
    NSDictionary *featherlight = @{
        @"LocalTheme": @"lavender_dream", @"ActiveTheme": @"lavender_dream", @"NextTheme": @"lavender_dream",
        @"CornerStyle": @"hairline", @"ShadowStyle": @"none", @"Density": @"spacious",
        @"FontWeight": @"thin", @"LetterSpacing": @"airy", @"LineSpacing": @"loose",
        @"TimeSeparator": @"space",
    };
    NSDictionary *industrial = @{
        @"LocalTheme": @"espresso", @"ActiveTheme": @"espresso", @"NextTheme": @"espresso",
        @"CornerStyle": @"sharp", @"ShadowStyle": @"plinth", @"Density": @"compact",
        @"FontWeight": @"black", @"LetterSpacing": @"tight", @"LineSpacing": @"tight",
        @"TimeSeparator": @"dash",
    };
    // v4 iter-144: two more moods. Trading Floor leans into the amber-CRT
    // analog trading vibe with a new pipe separator (iter-139). Scholar
    // exercises the upper-LineSpacing brackets from iter-138 for a
    // deliberate, studious readout.
    NSDictionary *tradingFloor = @{
        @"LocalTheme": @"amber_crt", @"ActiveTheme": @"amber_crt", @"NextTheme": @"amber_crt",
        @"CornerStyle": @"pill", @"ShadowStyle": @"glow", @"Density": @"compact",
        @"FontWeight": @"bold", @"LetterSpacing": @"tight", @"LineSpacing": @"tight",
        @"TimeSeparator": @"pipe",
        @"SessionSignalWindow": @"60min",  // iter-158: macro-trader wants full pre-open awareness
    };
    NSDictionary *scholar = @{
        @"LocalTheme": @"paper_white", @"ActiveTheme": @"paper_white", @"NextTheme": @"paper_white",
        @"CornerStyle": @"rounded", @"ShadowStyle": @"subtle", @"Density": @"comfortable",
        @"FontWeight": @"regular", @"LetterSpacing": @"extrawide", @"LineSpacing": @"cavernous",
        @"TimeSeparator": @"middot",
    };

    return @[
        @[@"Brutalist",     brutalist],
        @[@"Zen",           zen],
        @[@"Retro CRT",     retro],
        @[@"Executive",     executive],
        @[@"Neon",          neon],
        @[@"Hacker",        hacker],
        @[@"Glacier",       glacier],
        @[@"Midnight",      midnight],
        @[@"Featherlight",  featherlight],
        @[@"Industrial",    industrial],
        @[@"Trading Floor", tradingFloor],
        @[@"Scholar",       scholar],
    ];
}
