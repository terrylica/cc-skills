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
        @"UrgencyFlash": @"subtle",  // iter-220: gentle hint matching its calm aesthetic
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
        @"UrgencyHorizon": @"5min",       // iter-216: terminal-precise alarm — only the final sprint glows red
        @"UrgencyFlash": @"off",          // iter-220: terminal-quiet — no pulse distractions, color shift is enough
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
        @"UrgencyHorizon": @"240min",  // iter-216: ethereal slow build — gradient drifts in over 4 hours
        @"UrgencyFlash": @"subtle",    // iter-220: gentle hint matching thin/airy aesthetic
    };
    NSDictionary *industrial = @{
        @"LocalTheme": @"espresso", @"ActiveTheme": @"espresso", @"NextTheme": @"espresso",
        @"CornerStyle": @"sharp", @"ShadowStyle": @"plinth", @"Density": @"compact",
        @"FontWeight": @"black", @"LetterSpacing": @"tight", @"LineSpacing": @"tight",
        @"TimeSeparator": @"dash",
        @"UrgencyHorizon": @"30min",   // iter-216: mechanical mid-range — half-hour assembly-line warning
        @"UrgencyFlash": @"intense",   // iter-220: mechanical strong-dim attention-grab matching black weight + crisp shadow
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
        @"UrgencyHorizon": @"15min",       // iter-216: tight closing-bell glow — only the final stretch alarms
        @"UrgencyFlash": @"intense",       // iter-220: strong attention-grab on the closing-bell pulse
    };
    NSDictionary *scholar = @{
        @"LocalTheme": @"paper_white", @"ActiveTheme": @"paper_white", @"NextTheme": @"paper_white",
        @"CornerStyle": @"rounded", @"ShadowStyle": @"subtle", @"Density": @"comfortable",
        @"FontWeight": @"regular", @"LetterSpacing": @"extrawide", @"LineSpacing": @"cavernous",
        @"TimeSeparator": @"middot",
        @"UrgencyHorizon": @"120min",  // iter-216: deliberate, studious 2-hour buildup
    };
    // v4 iter-170: pairs with iter-169's Carnival theme + iter-161's B3
    // addition. Festive Brazilian-flag feel — bold weight + warm yellow
    // on green + glow shadow for energetic dancing-data vibe.
    NSDictionary *samba = @{
        @"LocalTheme": @"carnival", @"ActiveTheme": @"carnival", @"NextTheme": @"carnival",
        @"CornerStyle": @"rounded", @"ShadowStyle": @"glow", @"Density": @"default",
        @"FontWeight": @"bold", @"LetterSpacing": @"airy", @"LineSpacing": @"normal",
        @"TimeSeparator": @"middot",
    };
    // v4 iter-196: pairs with iter-195's Aurora theme (cyan-green on
    // indigo). Cold-minimalist readout — thin weight + halo shadow
    // evokes the shimmering aurora borealis glow. Distinct from the
    // existing cool moods: Glacier uses nord (desaturated); Midnight
    // leans dense; Borealis is the luminous cool companion.
    NSDictionary *borealis = @{
        @"LocalTheme": @"aurora", @"ActiveTheme": @"aurora", @"NextTheme": @"aurora",
        @"CornerStyle": @"squircle", @"ShadowStyle": @"halo", @"Density": @"comfortable",
        @"FontWeight": @"thin", @"LetterSpacing": @"wide", @"LineSpacing": @"loose",
        @"TimeSeparator": @"middot",
    };
    // v4 iter-218: two moods exercising iter-217's new soft-diffuse shadows.
    // Cinema — film-noir movie-credits readout: midnight_blue palette +
    // vignette atmospheric drop + thin weight + airy spacings + space
    // separator (typewriter-on-black-card vibe). Distinct from Midnight
    // (dense halo) and Featherlight (lavender no-shadow).
    NSDictionary *cinema = @{
        @"LocalTheme": @"midnight_blue", @"ActiveTheme": @"midnight_blue", @"NextTheme": @"midnight_blue",
        @"CornerStyle": @"soft", @"ShadowStyle": @"vignette", @"Density": @"comfortable",
        @"FontWeight": @"thin", @"LetterSpacing": @"airy", @"LineSpacing": @"loose",
        @"TimeSeparator": @"space",
    };
    // Levitation — content-floats-above-desktop vibe: soft_glass palette
    // + floating shadow (deep wide-soft drop) + squircle corners +
    // spacious density + middot separator. Distinct from Zen (halo
    // shadow + soft_glass) — Levitation's deep offset adds tangible
    // depth where Zen's halo sits centered.
    NSDictionary *levitation = @{
        @"LocalTheme": @"soft_glass", @"ActiveTheme": @"soft_glass", @"NextTheme": @"soft_glass",
        @"CornerStyle": @"squircle", @"ShadowStyle": @"floating", @"Density": @"spacious",
        @"FontWeight": @"medium", @"LetterSpacing": @"normal", @"LineSpacing": @"airy",
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
        @[@"Samba",         samba],
        @[@"Borealis",      borealis],
        @[@"Cinema",        cinema],
        @[@"Levitation",    levitation],
    ];
}
