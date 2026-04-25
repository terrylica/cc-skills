// v4 iter-118: lever / dispatcher test fixtures, split from test_session.m.
// See test_levers.h for rationale and the shared `failures` linkage.
#import "test_levers.h"
#import "../Sources/rendering/FontResolver.h"
#import "../Sources/rendering/SegmentOpacityResolver.h"
#import "../Sources/data/MarketSessionCalculator.h"
#import "../Sources/data/ThemeCatalog.h"
#import "../Sources/core/DateFormatPrefix.h"
#import "../Sources/core/CornerRadius.h"
#import "../Sources/core/DensityPad.h"
#import "../Sources/core/SegmentGap.h"
#import "../Sources/core/SkyGlyph.h"
#import "../Sources/core/ShadowSpec.h"
#import "../Sources/core/SessionSignalWindow.h"
#import "../Sources/core/ClipboardHeader.h"
#import "../Sources/content/UrgencyColors.h"
#import "../Sources/content/UrgencyHorizon.h"
#import "../Sources/content/UrgencyFlash.h"
#import "../Sources/content/WeekProgressBar.h"
#import "../Sources/preferences/FloatingClockQuickStyles.h"

void test_font_weight_parser(void) {
    // Known ids map to their NSFontWeight constants.
    struct { NSString *id; NSFontWeight w; } cases[] = {
        {@"thin",     NSFontWeightThin},      // iter-129
        {@"regular",  NSFontWeightRegular},
        {@"medium",   NSFontWeightMedium},
        {@"semibold", NSFontWeightSemibold},
        {@"bold",     NSFontWeightBold},
        {@"heavy",    NSFontWeightHeavy},
        {@"black",    NSFontWeightBlack},     // iter-129
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSFontWeight got = FCParseFontWeight(cases[i].id);
        if (fabs(got - cases[i].w) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.2f got %.2f\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].w, (double)got);
            failures++;
        }
    }
    if (fabs(FCParseFontWeight(nil) - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: nil → Medium\n", __func__); failures++;
    }
    if (fabs(FCParseFontWeight(@"") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: empty → Medium\n", __func__); failures++;
    }
    if (fabs(FCParseFontWeight(@"ultrablack") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: unknown → Medium\n", __func__); failures++;
    }
}

void test_segment_weight_fallback(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"FontWeight"];
    [d removeObjectForKey:@"TestSegWeight"];

    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightMedium) > 0.001) {
        fprintf(stderr, "FAIL %s: unset → Medium\n", __func__); failures++;
    }
    [d setObject:@"bold" forKey:@"FontWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightBold) > 0.001) {
        fprintf(stderr, "FAIL %s: global bold → Bold\n", __func__); failures++;
    }
    [d setObject:@"heavy" forKey:@"TestSegWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightHeavy) > 0.001) {
        fprintf(stderr, "FAIL %s: override heavy → Heavy\n", __func__); failures++;
    }
    [d setObject:@"" forKey:@"TestSegWeight"];
    if (fabs(FCResolveSegmentWeight(@"TestSegWeight") - NSFontWeightBold) > 0.001) {
        fprintf(stderr, "FAIL %s: empty override → global Bold\n", __func__); failures++;
    }
    [d removeObjectForKey:@"FontWeight"];
    [d removeObjectForKey:@"TestSegWeight"];
}

void test_segment_opacity_fallback(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"CanvasOpacity"];
    [d removeObjectForKey:@"TestSegOpacity"];

    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 0.55) - 0.55) > 0.001) {
        fprintf(stderr, "FAIL %s: unset → 0.55\n", __func__); failures++;
    }
    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 0.02) - 0.10) > 0.001) {
        fprintf(stderr, "FAIL %s: theme 0.02 clamped to 0.10\n", __func__); failures++;
    }
    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 1.75) - 1.00) > 0.001) {
        fprintf(stderr, "FAIL %s: theme 1.75 clamped to 1.00\n", __func__); failures++;
    }
    [d setDouble:0.80 forKey:@"CanvasOpacity"];
    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 0.30) - 0.80) > 0.001) {
        fprintf(stderr, "FAIL %s: global 0.80 wins\n", __func__); failures++;
    }
    [d setDouble:0.15 forKey:@"TestSegOpacity"];
    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 0.30) - 0.15) > 0.001) {
        fprintf(stderr, "FAIL %s: segment 0.15 wins\n", __func__); failures++;
    }
    [d setDouble:0 forKey:@"TestSegOpacity"];
    if (fabs(FCResolveSegmentOpacity(@"TestSegOpacity", 0.30) - 0.80) > 0.001) {
        fprintf(stderr, "FAIL %s: segment=0 → global 0.80\n", __func__); failures++;
    }
    [d removeObjectForKey:@"CanvasOpacity"];
    [d removeObjectForKey:@"TestSegOpacity"];
}

void test_progress_bar_glyph_styles(void) {
    struct { NSString *id; NSString *filled; NSString *empty; } cases[] = {
        {@"blocks",  @"█", @"▒"}, {@"dots",    @"●", @"○"},
        {@"dashes",  @"━", @"╌"}, {@"arrows",  @"▶", @"▷"},
        {@"binary",  @"█", @"░"}, {@"braille", @"⣿", @"⣀"},
        {@"hearts",  @"♥", @"♡"}, {@"stars",   @"★", @"☆"},
        {@"ribbon",  @"▰", @"▱"}, {@"diamond", @"◆", @"◇"},
        {@"triangles", @"▲", @"△"}, {@"thindots", @"•", @"·"},  // iter-131
        {@"waves",     @"≋", @"∼"}, {@"chevrons", @"❯", @"›"},  // iter-197
        {@"pies",      @"◉", @"◌"}, {@"boxes",    @"▣", @"▢"},  // iter-228
    };
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        [d setObject:cases[i].id forKey:@"ProgressBarStyle"];
        NSString *bar = buildProgressBar(0.5, 4);
        if (![bar hasPrefix:cases[i].filled] || ![bar hasSuffix:cases[i].empty]) {
            fprintf(stderr, "FAIL %s: style '%s' got '%s'\n",
                    __func__, cases[i].id.UTF8String, bar.UTF8String);
            failures++;
        }
    }
    [d setObject:@"does-not-exist" forKey:@"ProgressBarStyle"];
    NSString *bar = buildProgressBar(0.5, 4);
    if (![bar hasPrefix:@"●"] || ![bar hasSuffix:@"○"]) {
        fprintf(stderr, "FAIL %s: unknown id should fall back to dots, got '%s'\n",
                __func__, bar.UTF8String);
        failures++;
    }
    [d removeObjectForKey:@"ProgressBarStyle"];
}

void test_theme_catalog_invariants(void) {
    if (kNumThemes != 30) {
        fprintf(stderr, "FAIL %s: expected 30 themes got %zu\n", __func__, kNumThemes);
        failures++;
    }
    for (size_t i = 0; i < kNumThemes; i++) {
        const ClockTheme *t = &kThemes[i];
        if (!t->id || t->id[0] == 0 || !t->display || t->display[0] == 0) {
            fprintf(stderr, "FAIL %s: theme %zu missing id or display\n", __func__, i);
            failures++; continue;
        }
        if (t->fg_r < 0 || t->fg_r > 1 || t->fg_g < 0 || t->fg_g > 1 || t->fg_b < 0 || t->fg_b > 1 ||
            t->bg_r < 0 || t->bg_r > 1 || t->bg_g < 0 || t->bg_g > 1 || t->bg_b < 0 || t->bg_b > 1 ||
            t->alpha < 0 || t->alpha > 1) {
            fprintf(stderr, "FAIL %s: theme '%s' out-of-range channel\n", __func__, t->id);
            failures++;
        }
        NSString *idNS = [NSString stringWithUTF8String:t->id];
        if (themeForId(idNS) != t) {
            fprintf(stderr, "FAIL %s: themeForId('%s') did not round-trip\n", __func__, t->id);
            failures++;
        }
    }
    if (themeForId(@"this-does-not-exist") != &kThemes[0]) {
        fprintf(stderr, "FAIL %s: unknown did not fall back to kThemes[0]\n", __func__);
        failures++;
    }
}

void test_letter_spacing_parser(void) {
    struct { NSString *id; CGFloat kern; } cases[] = {
        {@"condensed", -1.5},  // iter-137
        {@"compact", -1.0}, {@"tight", -0.5}, {@"normal", 0.0},
        {@"airy", 0.5}, {@"wide", 1.0},
        {@"extrawide", 1.5},   // iter-137
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (fabs(FCParseLetterSpacing(cases[i].id) - cases[i].kern) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.2f got %.2f\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].kern, (double)FCParseLetterSpacing(cases[i].id));
            failures++;
        }
    }
    if (fabs(FCParseLetterSpacing(nil)) > 0.001) { failures++; fprintf(stderr, "FAIL %s: nil → 0\n", __func__); }
    if (fabs(FCParseLetterSpacing(@"")) > 0.001) { failures++; fprintf(stderr, "FAIL %s: empty → 0\n", __func__); }
    if (fabs(FCParseLetterSpacing(@"ultra-extended")) > 0.001) { failures++; fprintf(stderr, "FAIL %s: unknown → 0\n", __func__); }
}

void test_line_spacing_parser(void) {
    struct { NSString *id; CGFloat leading; } cases[] = {
        {@"tight", 0.0}, {@"snug", 1.0}, {@"normal", 2.0},
        {@"loose", 4.0}, {@"airy", 7.0},
        {@"spacious", 10.0}, {@"cavernous", 14.0},   // iter-138
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (fabs(FCParseLineSpacing(cases[i].id) - cases[i].leading) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.2f got %.2f\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].leading, (double)FCParseLineSpacing(cases[i].id));
            failures++;
        }
    }
    if (fabs(FCParseLineSpacing(nil) - 2.0) > 0.001)  { failures++; fprintf(stderr, "FAIL %s: nil → 2.0\n", __func__); }
    if (fabs(FCParseLineSpacing(@"") - 2.0) > 0.001)  { failures++; fprintf(stderr, "FAIL %s: empty → 2.0\n", __func__); }
    if (fabs(FCParseLineSpacing(@"double") - 2.0) > 0.001) { failures++; fprintf(stderr, "FAIL %s: unknown → 2.0\n", __func__); }
}

void test_date_format_prefix(void) {
    struct { NSString *id; NSString *pattern; } cases[] = {
        {@"short", @"EEE MMM d  "}, {@"long", @"EEEE MMMM d  "},
        {@"iso", @"yyyy-MM-dd  "}, {@"numeric", @"M/d  "},
        {@"weeknum", @"'Wk' w  "}, {@"dayofyr", @"'Day' D  "},
        {@"usa", @"M/d/yyyy  "}, {@"european", @"d.M.yyyy  "},
        {@"compact_iso", @"MM-dd  "},
        {@"weekday_only", @"EEEE  "}, {@"monthday", @"MMM d  "},  // iter-227
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSString *got = FCDateFormatPrefix(cases[i].id);
        if (![got isEqualToString:cases[i].pattern]) {
            fprintf(stderr, "FAIL %s: '%s' expected '%s' got '%s'\n",
                    __func__, cases[i].id.UTF8String,
                    cases[i].pattern.UTF8String, got.UTF8String);
            failures++;
        }
    }
    if (![FCDateFormatPrefix(nil) isEqualToString:@"EEE MMM d  "]) { failures++; fprintf(stderr, "FAIL %s: nil\n", __func__); }
    if (![FCDateFormatPrefix(@"") isEqualToString:@"EEE MMM d  "]) { failures++; fprintf(stderr, "FAIL %s: empty\n", __func__); }
    if (![FCDateFormatPrefix(@"julian-1582") isEqualToString:@"EEE MMM d  "]) { failures++; fprintf(stderr, "FAIL %s: unknown\n", __func__); }
}

void test_corner_radius_points(void) {
    // iter-97's full 8-preset catalog. pill depends on shorter axis,
    // so test at both orientations (w>h and h>w) to lock that logic.
    // iter-119: promoted from iter-117's lean form now that
    // test_levers.m has cap headroom.
    struct { NSString *id; CGFloat w; CGFloat h; CGFloat expected; } cases[] = {
        {@"sharp",     100, 40,  0.0},
        {@"hairline",  100, 40,  1.0},
        {@"micro",     100, 40,  3.0},
        {@"rounded",   100, 40,  6.0},
        {@"cushion",   100, 40,  8.0},   // iter-224
        {@"soft",      100, 40, 10.0},
        {@"squircle",  100, 40, 14.0},
        {@"chunky",    100, 40, 18.0},   // iter-224
        {@"jumbo",     100, 40, 22.0},
        {@"pill",      100, 40, 20.0},  // min(w,h)/2 with w>h
        {@"pill",       40, 80, 20.0},  // min(w,h)/2 with h>w
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        CGFloat got = FCCornerRadiusPoints(cases[i].id, cases[i].w, cases[i].h);
        if (fabs(got - cases[i].expected) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' %.0fx%.0f expected %.1fpt got %.1fpt\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].w, (double)cases[i].h,
                    (double)cases[i].expected, (double)got);
            failures++;
        }
    }
    // nil / empty / unknown → rounded (6pt).
    if (fabs(FCCornerRadiusPoints(nil,        100, 40) - 6.0) > 0.001) {
        failures++; fprintf(stderr, "FAIL %s: nil → rounded\n", __func__);
    }
    if (fabs(FCCornerRadiusPoints(@"",        100, 40) - 6.0) > 0.001) {
        failures++; fprintf(stderr, "FAIL %s: empty → rounded\n", __func__);
    }
    if (fabs(FCCornerRadiusPoints(@"made-up", 100, 40) - 6.0) > 0.001) {
        failures++; fprintf(stderr, "FAIL %s: unknown → rounded\n", __func__);
    }
}

void test_density_pad_points(void) {
    struct { NSString *id; CGFloat pt; } cases[] = {
        {@"ultracompact", 4}, {@"tight", 8}, {@"compact", 12}, {@"default", 24},
        {@"comfortable", 36}, {@"roomy", 42}, {@"spacious", 48}, {@"cavernous", 64},  // iter-225 +tight +roomy
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (fabs(FCDensityPadPoints(cases[i].id) - cases[i].pt) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.1fpt got %.1fpt\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].pt, (double)FCDensityPadPoints(cases[i].id));
            failures++;
        }
    }
    if (fabs(FCDensityPadPoints(nil) - 24) > 0.001) { failures++; fprintf(stderr, "FAIL %s: nil\n", __func__); }
    if (fabs(FCDensityPadPoints(@"") - 24) > 0.001) { failures++; fprintf(stderr, "FAIL %s: empty\n", __func__); }
    if (fabs(FCDensityPadPoints(@"infinite") - 24) > 0.001) { failures++; fprintf(stderr, "FAIL %s: unknown\n", __func__); }
}

void test_segment_gap_points(void) {
    struct { NSString *id; CGFloat pt; } cases[] = {
        {@"flush", 0}, {@"tight", 2}, {@"snug", 3}, {@"normal", 4},
        {@"cozy", 6}, {@"airy", 8}, {@"open", 11},  // iter-226
        {@"spacious", 14}, {@"cavernous", 24},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (fabs(FCSegmentGapPoints(cases[i].id) - cases[i].pt) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.1fpt got %.1fpt\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].pt, (double)FCSegmentGapPoints(cases[i].id));
            failures++;
        }
    }
    if (fabs(FCSegmentGapPoints(nil) - 4) > 0.001) { failures++; fprintf(stderr, "FAIL %s: nil\n", __func__); }
    if (fabs(FCSegmentGapPoints(@"") - 4) > 0.001) { failures++; fprintf(stderr, "FAIL %s: empty\n", __func__); }
    if (fabs(FCSegmentGapPoints(@"infinite") - 4) > 0.001) { failures++; fprintf(stderr, "FAIL %s: unknown\n", __func__); }
}

void test_sky_glyph_phases(void) {
    NSString *dawn  = @"\U0001F305";
    NSString *day   = @"☀️";
    NSString *dusk  = @"\U0001F307";
    NSString *night = @"\U0001F319";
    NSString *expected[24] = {
        night, night, night, night, night,
        dawn, dawn,
        day, day, day, day, day, day, day, day, day, day,
        dusk, dusk,
        night, night, night, night, night,
    };
    for (NSInteger hour = 0; hour < 24; hour++) {
        NSString *got = FCSkyGlyphForHour(hour);
        if (![got isEqualToString:expected[hour]]) {
            fprintf(stderr, "FAIL %s: hour=%ld expected '%s' got '%s'\n",
                    __func__, (long)hour,
                    expected[hour].UTF8String, got.UTF8String);
            failures++;
        }
    }
    if (![FCSkyGlyphForHour(-1) isEqualToString:night]) { failures++; fprintf(stderr, "FAIL %s: -1\n", __func__); }
    if (![FCSkyGlyphForHour(24) isEqualToString:night]) { failures++; fprintf(stderr, "FAIL %s: 24\n", __func__); }
}

void test_current_time_format(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    struct { NSString *sepId; NSString *patternSep; } cases[] = {
        {@"colon", @":"}, {@"middot", @"'·'"}, {@"space", @"' '"},
        {@"slash", @"'/'"}, {@"dash", @"'-'"},
        {@"pipe", @"'|'"}, {@"plus", @"'+'"},   // iter-139
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        [d setObject:cases[i].sepId forKey:@"TimeSeparator"];
        NSString *e24 = [NSString stringWithFormat:@"HH%@mm%@ss",
                         cases[i].patternSep, cases[i].patternSep];
        NSString *g24 = FCCurrentTimeFormat(NO, YES);
        if (![g24 isEqualToString:e24]) {
            fprintf(stderr, "FAIL %s: 24h+sec '%s' expected '%s' got '%s'\n",
                    __func__, cases[i].sepId.UTF8String,
                    e24.UTF8String, g24.UTF8String);
            failures++;
        }
        NSString *e12 = [NSString stringWithFormat:@"h%@mm a", cases[i].patternSep];
        NSString *g12 = FCCurrentTimeFormat(YES, NO);
        if (![g12 isEqualToString:e12]) {
            fprintf(stderr, "FAIL %s: 12h-sec '%s' expected '%s' got '%s'\n",
                    __func__, cases[i].sepId.UTF8String,
                    e12.UTF8String, g12.UTF8String);
            failures++;
        }
    }
    [d setObject:@"unknown-sep" forKey:@"TimeSeparator"];
    if (![FCCurrentTimeFormat(NO, YES) isEqualToString:@"HH:mm:ss"]) {
        fprintf(stderr, "FAIL %s: unknown-id should collapse to colon\n", __func__);
        failures++;
    }
    [d removeObjectForKey:@"TimeSeparator"];
}

void test_quick_styles_invariants(void) {
    NSArray<NSArray *> *styles = buildQuickStyles();
    if (styles.count == 0) {
        fprintf(stderr, "FAIL %s: empty catalog\n", __func__); failures++;
        return;
    }
    NSDictionary *allowed = @{
        @"CornerStyle":    [NSSet setWithArray:@[@"sharp", @"hairline", @"micro", @"rounded",
                                                  @"cushion", @"soft", @"squircle",
                                                  @"chunky", @"jumbo", @"pill"]],  // iter-224
        @"ShadowStyle":    [NSSet setWithArray:@[@"none", @"subtle", @"lifted", @"glow",
                                                  @"crisp", @"plinth", @"halo",
                                                  @"vignette", @"floating"]],  // iter-217
        @"Density":        [NSSet setWithArray:@[@"ultracompact", @"tight", @"compact", @"default",
                                                  @"comfortable", @"roomy", @"spacious", @"cavernous"]],  // iter-225
        @"FontWeight":     [NSSet setWithArray:@[@"thin", @"regular", @"medium", @"semibold",
                                                  @"bold", @"heavy", @"black"]],
        @"LetterSpacing":  [NSSet setWithArray:@[@"condensed", @"compact", @"tight", @"normal", @"airy", @"wide", @"extrawide"]],
        @"LineSpacing":    [NSSet setWithArray:@[@"tight", @"snug", @"normal", @"loose", @"airy", @"spacious", @"cavernous"]],
        @"TimeSeparator":  [NSSet setWithArray:@[@"colon", @"middot", @"space", @"slash", @"dash", @"pipe", @"plus"]],
        // v4 iter-158: SessionSignalWindow becomes Quick-Style-composable.
        // Lets future bundles tune the auction-window feel per mood
        // (e.g. Hacker=off for minimalism, Trading Floor=60min for
        // macro-trader awareness).
        @"SessionSignalWindow": [NSSet setWithArray:@[@"off", @"5min", @"15min", @"30min", @"60min"]],
        // v4 iter-216: UrgencyHorizon (iter-215) becomes Quick-Style-composable.
        // Trading Floor=15min for tight closing-bell glow, Featherlight=240min
        // for slow ethereal build, Hacker=5min for terminal-precise alarm.
        @"UrgencyHorizon":      [NSSet setWithArray:@[@"5min", @"15min", @"30min", @"60min", @"120min", @"240min"]],
        // v4 iter-220: UrgencyFlash (iter-219) becomes Quick-Style-composable.
        // Hacker=off (terminal-quiet), Trading Floor=intense (closing-bell
        // attention-grab), Featherlight=subtle (matches thin aesthetic).
        @"UrgencyFlash":        [NSSet setWithArray:@[@"off", @"subtle", @"normal", @"intense"]],
    };
    for (NSArray *style in styles) {
        if (style.count != 2) { failures++; fprintf(stderr, "FAIL %s: malformed entry\n", __func__); continue; }
        NSString *name = style[0];
        NSDictionary *bundle = style[1];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            failures++; fprintf(stderr, "FAIL %s: empty display name\n", __func__); continue;
        }
        if (![bundle isKindOfClass:[NSDictionary class]] || bundle.count == 0) {
            failures++; fprintf(stderr, "FAIL %s: '%s' has empty bundle\n",
                    __func__, name.UTF8String); continue;
        }
        for (NSString *themeKey in @[@"LocalTheme", @"ActiveTheme", @"NextTheme"]) {
            NSString *themeId = bundle[themeKey];
            if (themeId == nil) continue;
            const ClockTheme *resolved = themeForId(themeId);
            NSString *resolvedId = [NSString stringWithUTF8String:resolved->id];
            if (![resolvedId isEqualToString:themeId]) {
                failures++;
                fprintf(stderr, "FAIL %s: '%s' → %s = '%s' unresolved\n",
                        __func__, name.UTF8String, themeKey.UTF8String,
                        themeId.UTF8String);
            }
        }
        for (NSString *k in allowed) {
            id v = bundle[k];
            if (v == nil) continue;
            NSSet *set = allowed[k];
            if (![set containsObject:v]) {
                failures++;
                fprintf(stderr, "FAIL %s: '%s' → %s='%s' not in allowed set\n",
                        __func__, name.UTF8String, k.UTF8String,
                        [v description].UTF8String);
            }
        }
    }
}

void test_shadow_spec_catalog(void) {
    // iter-120: lock iter-93's 7 ShadowStyle presets (iter-31's originals
    // + crisp / plinth / halo). The struct encodes color-source + 4 numeric
    // params; verify exact match for each id.
    struct {
        NSString *id;
        BOOL enabled;
        FCShadowColorSource colorSource;
        CGFloat opacity, offX, offY, radius;
    } cases[] = {
        {@"subtle", YES, FCShadowColorBlack,           0.35, 0, -2, 3},
        {@"lifted", YES, FCShadowColorBlack,           0.55, 0, -4, 6},
        {@"glow",   YES, FCShadowColorThemeForeground, 0.60, 0,  0, 6},
        {@"crisp",  YES, FCShadowColorBlack,           0.85, 1, -1, 0},
        {@"plinth", YES, FCShadowColorBlack,           0.70, 0, -8, 10},
        {@"halo",   YES, FCShadowColorThemeBackground, 0.50, 0,  0, 10},
        // iter-217 — soft-diffuse pair filling the cinematic / floating gap.
        {@"vignette", YES, FCShadowColorBlack,         0.40, 0, -3, 18},
        {@"floating", YES, FCShadowColorBlack,         0.30, 0, -12, 14},
        {@"none",   NO,  FCShadowColorBlack,           0,    0,  0, 0},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        FCShadowSpec s = FCShadowSpecForId(cases[i].id);
        BOOL ok = s.enabled == cases[i].enabled &&
                  s.colorSource == cases[i].colorSource &&
                  fabs(s.opacity - cases[i].opacity) < 0.001 &&
                  fabs(s.offsetX - cases[i].offX)    < 0.001 &&
                  fabs(s.offsetY - cases[i].offY)    < 0.001 &&
                  fabs(s.radius  - cases[i].radius)  < 0.001;
        if (!ok) {
            fprintf(stderr, "FAIL %s: '%s' enabled=%d src=%d op=%.2f off=(%.1f,%.1f) r=%.1f\n",
                    __func__, cases[i].id.UTF8String,
                    s.enabled, s.colorSource,
                    (double)s.opacity, (double)s.offsetX, (double)s.offsetY,
                    (double)s.radius);
            failures++;
        }
    }
    // Unknown / nil / empty → disabled (matches "none" default).
    if (FCShadowSpecForId(nil).enabled) {
        failures++; fprintf(stderr, "FAIL %s: nil should be disabled\n", __func__);
    }
    if (FCShadowSpecForId(@"").enabled) {
        failures++; fprintf(stderr, "FAIL %s: empty should be disabled\n", __func__);
    }
    if (FCShadowSpecForId(@"nebula").enabled) {
        failures++; fprintf(stderr, "FAIL %s: unknown should be disabled\n", __func__);
    }
}

void test_session_signal_window(void) {
    // iter-126: SessionSignalWindow pref — controls the minute count
    // that gates iter-123's PRE-MARKET and iter-125's AFTER-HOURS
    // state promotions.
    struct { NSString *id; NSInteger mins; } cases[] = {
        {@"off", 0}, {@"5min", 5}, {@"15min", 15}, {@"30min", 30}, {@"60min", 60},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSInteger got = FCSessionSignalWindowMinutes(cases[i].id);
        if (got != cases[i].mins) {
            fprintf(stderr, "FAIL %s: '%s' expected %ld got %ld\n",
                    __func__, cases[i].id.UTF8String,
                    (long)cases[i].mins, (long)got);
            failures++;
        }
    }
    // Unknown / nil / empty → 15 (the default matches iter-123/125 original).
    if (FCSessionSignalWindowMinutes(nil) != 15) {
        failures++; fprintf(stderr, "FAIL %s: nil → %ld (want 15)\n",
                           __func__, (long)FCSessionSignalWindowMinutes(nil));
    }
    if (FCSessionSignalWindowMinutes(@"") != 15) {
        failures++; fprintf(stderr, "FAIL %s: empty → %ld (want 15)\n",
                           __func__, (long)FCSessionSignalWindowMinutes(@""));
    }
    if (FCSessionSignalWindowMinutes(@"forever") != 15) {
        failures++; fprintf(stderr, "FAIL %s: unknown → %ld (want 15)\n",
                           __func__, (long)FCSessionSignalWindowMinutes(@"forever"));
    }
}

void test_urgency_color_tiers(void) {
    // iter-166: lock FCUrgencyColorForSecs's 3-tier branching (iter-73).
    // Thresholds: red <30 min, amber <60 min, normal ≥60 min. The
    // `normalColor` arg is returned for the ≥60min tier (theme-dependent
    // in callers), amber/red are the fixed palette.
    NSColor *sentinel = [NSColor colorWithRed:0.1 green:0.2 blue:0.3 alpha:1.0];
    NSColor *amber = FCUrgencyAmberColor();
    NSColor *red   = FCUrgencyRedColor();

    // ≥60 min → normal (sentinel passed through)
    if (![FCUrgencyColorForSecs(3600, sentinel) isEqual:sentinel]) {
        failures++;
        fprintf(stderr, "FAIL %s: 3600s expected sentinel (normal tier)\n", __func__);
    }
    if (![FCUrgencyColorForSecs(kFCUrgencyAmberThresholdSecs, sentinel) isEqual:sentinel]) {
        failures++;
        fprintf(stderr, "FAIL %s: exactly-threshold still normal\n", __func__);
    }
    // <60 min but ≥30 min → amber
    if (![FCUrgencyColorForSecs(kFCUrgencyAmberThresholdSecs - 1, sentinel) isEqual:amber]) {
        failures++;
        fprintf(stderr, "FAIL %s: just-below-amber should be amber\n", __func__);
    }
    if (![FCUrgencyColorForSecs(kFCUrgencyRedThresholdSecs, sentinel) isEqual:amber]) {
        failures++;
        fprintf(stderr, "FAIL %s: exactly-red-threshold should still be amber\n", __func__);
    }
    // <30 min → red
    if (![FCUrgencyColorForSecs(kFCUrgencyRedThresholdSecs - 1, sentinel) isEqual:red]) {
        failures++;
        fprintf(stderr, "FAIL %s: just-below-red should be red\n", __func__);
    }
    if (![FCUrgencyColorForSecs(0, sentinel) isEqual:red]) {
        failures++;
        fprintf(stderr, "FAIL %s: 0s should be red\n", __func__);
    }
    // Palette distinctness — amber and red must not be visually equal.
    if ([amber isEqual:red]) {
        failures++;
        fprintf(stderr, "FAIL %s: amber == red (palette indistinct)\n", __func__);
    }
}

// iter-212: lock the continuous-mode semantics of FCUrgencyAlertColor.
// Properties checked (not exact RGB — gradient is parameterized):
//   1. secs >= horizon → returns the caller's normalColor unchanged
//   2. secs <= imminent → returns a clearly-red color (hue near 0°)
//   3. monotonic: hue strictly decreases as secs decreases (within range)
//   4. flash modulator returns 1.0 above flash threshold; alternates
//      below it based on epoch parity
//   5. combined alert color picks up the flash multiplier in alpha
void test_urgency_continuous_and_flash(void) {
    NSColor *sentinel = [NSColor colorWithRed:0.1 green:0.2 blue:0.3 alpha:1.0];

    // (1) horizon → normalColor pass-through
    NSColor *atHorizon = FCUrgencyContinuousColor(kFCUrgencyHorizonSecs, sentinel);
    if (![atHorizon isEqual:sentinel]) {
        failures++;
        fprintf(stderr, "FAIL %s: at horizon should pass normalColor through\n", __func__);
    }

    // (2) below imminent → hue near red endpoint
    NSColor *atZero = FCUrgencyContinuousColor(0, sentinel);
    NSColor *rgbZero = [atZero colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    CGFloat hZero = 0, sZero = 0, bZero = 0, aZero = 0;
    [rgbZero getHue:&hZero saturation:&sZero brightness:&bZero alpha:&aZero];
    // hue near 0 (red); also accept 1.0 since hue wraps
    if (hZero > 0.05 && hZero < 0.95) {
        failures++;
        fprintf(stderr, "FAIL %s: at 0s expected hue near 0 (red), got %.3f\n", __func__, hZero);
    }

    // (3) monotonic: hue at later (further-away) time is greater than
    //     hue at earlier (closer) time. Sample three log-spaced points
    //     between imminent and horizon.
    long s1 = kFCUrgencyImminentSecs * 4;
    long s2 = kFCUrgencyImminentSecs * 16;
    long s3 = kFCUrgencyImminentSecs * 60;
    CGFloat h1 = 0, h2 = 0, h3 = 0, _s = 0, _b = 0, _a = 0;
    [[FCUrgencyContinuousColor(s1, sentinel) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]
        getHue:&h1 saturation:&_s brightness:&_b alpha:&_a];
    [[FCUrgencyContinuousColor(s2, sentinel) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]
        getHue:&h2 saturation:&_s brightness:&_b alpha:&_a];
    [[FCUrgencyContinuousColor(s3, sentinel) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]
        getHue:&h3 saturation:&_s brightness:&_b alpha:&_a];
    if (!(h1 < h2 && h2 < h3)) {
        failures++;
        fprintf(stderr, "FAIL %s: hue not monotonic: h(%lds)=%.3f h(%lds)=%.3f h(%lds)=%.3f\n",
                __func__, s1, h1, s2, h2, s3, h3);
    }

    // (4) flash modulator
    if (FCUrgencyFlashAlpha(kFCUrgencyFlashThresholdSecs, 0) != 1.0) {
        failures++;
        fprintf(stderr, "FAIL %s: at flash threshold (boundary) expected 1.0\n", __func__);
    }
    if (FCUrgencyFlashAlpha(0, 0) != kFCUrgencyFlashDimAlpha) {
        failures++;
        fprintf(stderr, "FAIL %s: at 0s, even epoch expected %.3f got %.3f\n",
                __func__, kFCUrgencyFlashDimAlpha, FCUrgencyFlashAlpha(0, 0));
    }
    if (FCUrgencyFlashAlpha(0, 1) != 1.0) {
        failures++;
        fprintf(stderr, "FAIL %s: at 0s, odd epoch expected 1.0 got %.3f\n",
                __func__, FCUrgencyFlashAlpha(0, 1));
    }

    // (5) combined alert: flash dim when imminent + even epoch.
    NSColor *alert = FCUrgencyAlertColor(0, sentinel, 0);
    if (fabs(alert.alphaComponent - kFCUrgencyFlashDimAlpha) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: combined alert at 0s/even epoch expected alpha %.3f got %.3f\n",
                __func__, kFCUrgencyFlashDimAlpha, alert.alphaComponent);
    }
}

void test_clipboard_header_format(void) {
    // iter-160: lock FCComposeClipboardSnapshot's output format — the
    // pure-function body of the Copy cluster's header-writing helper.
    // Empty body → empty string (callers short-circuit without writing
    // to the pasteboard).
    if (FCComposeClipboardSnapshot(@"LOCAL", @"", nil).length != 0) {
        failures++;
        fprintf(stderr, "FAIL %s: empty body should return empty string\n", __func__);
    }
    // Fixed-date composition: use a known NSDate so the UTC stamp is
    // deterministic. 2026-04-24 12:34:56 UTC.
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 4; c.day = 24;
    c.hour = 12; c.minute = 34; c.second = 56;
    c.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = c.timeZone;
    NSDate *d = [cal dateFromComponents:c];

    NSString *got = FCComposeClipboardSnapshot(@"LOCAL", @"14:37:21 EDT UTC-4", d);
    NSString *want = @"# Floating Clock · LOCAL · 2026-04-24 12:34:56 UTC\n14:37:21 EDT UTC-4";
    if (![got isEqualToString:want]) {
        failures++;
        fprintf(stderr, "FAIL %s: got\n'%s'\nwant\n'%s'\n",
                __func__, got.UTF8String, want.UTF8String);
    }
    // Nil label becomes empty — doesn't crash.
    NSString *gotNil = FCComposeClipboardSnapshot(nil, @"x", d);
    NSString *wantNil = @"# Floating Clock ·  · 2026-04-24 12:34:56 UTC\nx";
    if (![gotNil isEqualToString:wantNil]) {
        failures++;
        fprintf(stderr, "FAIL %s: nil-label got '%s' want '%s'\n",
                __func__, gotNil.UTF8String, wantNil.UTF8String);
    }
}

void test_state_is_trading(void) {
    // iter-168: lock FCStateIsTrading's 5-state mapping. OPEN/LUNCH
    // → YES (caller should draw progress bar + countdown).
    // CLOSED/PRE-MARKET/AFTER-HOURS → NO (caller should draw the
    // "opens in Xh" path). The whole point of the extraction is to
    // prevent drift across 3 inline callsites; this test locks the
    // canonical mapping so a silent flip would fail CI.
    struct { SessionState s; BOOL trading; } cases[] = {
        {kSessionOpen,       YES},
        {kSessionLunch,      YES},
        {kSessionClosed,     NO},
        {kSessionPreMarket,  NO},
        {kSessionAfterHours, NO},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        BOOL got = FCStateIsTrading(cases[i].s);
        if (got != cases[i].trading) {
            failures++;
            fprintf(stderr, "FAIL %s: state %d → %d (want %d)\n",
                    __func__, (int)cases[i].s, got, cases[i].trading);
        }
    }
}

void test_session_state_color(void) {
    // iter-154: completes the (glyph, label, color) triad's test
    // coverage alongside existing glyphForState + labelForState
    // fixtures. Every state must produce a color with channels in
    // [0, 1] + alpha = 1.0; distinct colors so users can tell states
    // apart visually.
    SessionState states[] = {kSessionOpen, kSessionLunch, kSessionClosed,
                             kSessionPreMarket, kSessionAfterHours};
    NSColor *seen[5];
    for (size_t i = 0; i < 5; i++) {
        NSColor *c = [colorForState(states[i], NULL)
                        colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (!c) {
            failures++;
            fprintf(stderr, "FAIL %s: state %d returned nil color\n",
                    __func__, (int)states[i]);
            continue;
        }
        CGFloat r, g, b, a;
        [c getRed:&r green:&g blue:&b alpha:&a];
        if (r < 0 || r > 1 || g < 0 || g > 1 || b < 0 || b > 1 ||
            fabs(a - 1.0) > 0.001) {
            failures++;
            fprintf(stderr, "FAIL %s: state %d color channels out of range (%.2f,%.2f,%.2f @ alpha %.2f)\n",
                    __func__, (int)states[i], r, g, b, a);
        }
        seen[i] = c;
    }
    // All five colors should be distinct — overlap would mean two
    // states are visually indistinguishable (e.g. gray CLOSED vs.
    // gray AFTER-HOURS would hide the iter-125 signal).
    for (size_t i = 0; i < 5; i++) {
        for (size_t j = i + 1; j < 5; j++) {
            if (seen[i] && seen[j] && [seen[i] isEqual:seen[j]]) {
                failures++;
                fprintf(stderr, "FAIL %s: states %d and %d share the same color\n",
                        __func__, (int)states[i], (int)states[j]);
            }
        }
    }
}

void test_session_state_label(void) {
    // iter-135: lock labelForState's 5-case word mapping (OPEN / LUNCH
    // / CLOSED / PRE-MARKET / AFTER-HOURS). Used by iter-134's legacy
    // single-market label fix; extracted here for testability.
    struct { SessionState s; NSString *word; } cases[] = {
        {kSessionOpen,       @"OPEN"},
        {kSessionLunch,      @"LUNCH"},
        {kSessionClosed,     @"CLOSED"},
        {kSessionPreMarket,  @"PRE-MARKET"},
        {kSessionAfterHours, @"AFTER-HOURS"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSString *got = labelForState(cases[i].s);
        if (![got isEqualToString:cases[i].word]) {
            fprintf(stderr, "FAIL %s: state %d → '%s' (want '%s')\n",
                    __func__, (int)cases[i].s,
                    got.UTF8String, cases[i].word.UTF8String);
            failures++;
        }
    }
    // Out-of-range (unlikely but covered) → CLOSED safe default.
    if (![labelForState((SessionState)99) isEqualToString:@"CLOSED"]) {
        failures++;
        fprintf(stderr, "FAIL %s: out-of-range should return CLOSED\n", __func__);
    }
}

void test_urgency_horizon_dispatcher(void) {
    // iter-215: UrgencyHorizon pref — controls the horizon (in seconds)
    // below which FCUrgencyContinuousColor's green→red gradient runs.
    // 6 presets, default fallback to 60 min so unset/empty/unknown
    // preserves iter-212 behavior.
    struct { NSString *id; NSInteger mins; } cases[] = {
        {@"5min",    5},
        {@"15min",  15},
        {@"30min",  30},
        {@"60min",  60},
        {@"120min", 120},
        {@"240min", 240},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSInteger got = FCUrgencyHorizonMinutes(cases[i].id);
        if (got != cases[i].mins) {
            fprintf(stderr, "FAIL %s: '%s' expected %ld got %ld\n",
                    __func__, cases[i].id.UTF8String,
                    (long)cases[i].mins, (long)got);
            failures++;
        }
    }
    // Unknown / nil / empty → 60 (matches iter-212 hardcoded default).
    if (FCUrgencyHorizonMinutes(nil) != 60) {
        failures++; fprintf(stderr, "FAIL %s: nil → %ld (want 60)\n",
                           __func__, (long)FCUrgencyHorizonMinutes(nil));
    }
    if (FCUrgencyHorizonMinutes(@"") != 60) {
        failures++; fprintf(stderr, "FAIL %s: empty → %ld (want 60)\n",
                           __func__, (long)FCUrgencyHorizonMinutes(@""));
    }
    if (FCUrgencyHorizonMinutes(@"forever") != 60) {
        failures++; fprintf(stderr, "FAIL %s: unknown → %ld (want 60)\n",
                           __func__, (long)FCUrgencyHorizonMinutes(@"forever"));
    }

    // FCUrgencyHorizonSecsCurrent reads NSUserDefaults and converts to
    // seconds. Save/restore the pref to keep tests independent of
    // local user state.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *saved = [d stringForKey:@"UrgencyHorizon"];

    [d removeObjectForKey:@"UrgencyHorizon"];
    long unset = FCUrgencyHorizonSecsCurrent();
    if (unset != kFCUrgencyHorizonSecs) {
        failures++;
        fprintf(stderr, "FAIL %s: unset → %ld (want %ld = SSoT default)\n",
                __func__, unset, kFCUrgencyHorizonSecs);
    }

    [d setObject:@"5min" forKey:@"UrgencyHorizon"];
    if (FCUrgencyHorizonSecsCurrent() != 300) {
        failures++;
        fprintf(stderr, "FAIL %s: '5min' → %ld (want 300)\n",
                __func__, FCUrgencyHorizonSecsCurrent());
    }

    [d setObject:@"240min" forKey:@"UrgencyHorizon"];
    if (FCUrgencyHorizonSecsCurrent() != 14400) {
        failures++;
        fprintf(stderr, "FAIL %s: '240min' → %ld (want 14400)\n",
                __func__, FCUrgencyHorizonSecsCurrent());
    }

    // Unknown id → falls through to 60 min default = 3600 s.
    [d setObject:@"forever" forKey:@"UrgencyHorizon"];
    if (FCUrgencyHorizonSecsCurrent() != 3600) {
        failures++;
        fprintf(stderr, "FAIL %s: unknown pref → %ld (want 3600)\n",
                __func__, FCUrgencyHorizonSecsCurrent());
    }

    // Restore.
    if (saved) [d setObject:saved forKey:@"UrgencyHorizon"];
    else       [d removeObjectForKey:@"UrgencyHorizon"];
}

void test_urgency_flash_intensity(void) {
    // iter-219: UrgencyFlash pref — controls the dim-half alpha of the
    // 1Hz pulse in FCUrgencyFlashAlpha. 4 presets, default fallback to
    // kFCUrgencyFlashDimAlpha so unset/empty/unknown preserves iter-212.
    struct { NSString *id; CGFloat alpha; } cases[] = {
        {@"off",     1.0},
        {@"subtle",  0.80},
        {@"normal",  0.45},
        {@"intense", 0.15},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        CGFloat got = FCUrgencyFlashDimAlphaForId(cases[i].id);
        if (fabs(got - cases[i].alpha) > 0.001) {
            fprintf(stderr, "FAIL %s: '%s' expected %.2f got %.2f\n",
                    __func__, cases[i].id.UTF8String,
                    (double)cases[i].alpha, (double)got);
            failures++;
        }
    }
    // Unknown / nil / empty → kFCUrgencyFlashDimAlpha (iter-212 default).
    if (fabs(FCUrgencyFlashDimAlphaForId(nil) - kFCUrgencyFlashDimAlpha) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: nil → %.2f (want %.2f = SSoT default)\n",
                __func__, (double)FCUrgencyFlashDimAlphaForId(nil),
                (double)kFCUrgencyFlashDimAlpha);
    }
    if (fabs(FCUrgencyFlashDimAlphaForId(@"") - kFCUrgencyFlashDimAlpha) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: empty → %.2f (want %.2f)\n",
                __func__, (double)FCUrgencyFlashDimAlphaForId(@""),
                (double)kFCUrgencyFlashDimAlpha);
    }
    if (fabs(FCUrgencyFlashDimAlphaForId(@"strobe") - kFCUrgencyFlashDimAlpha) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: unknown → %.2f (want %.2f)\n",
                __func__, (double)FCUrgencyFlashDimAlphaForId(@"strobe"),
                (double)kFCUrgencyFlashDimAlpha);
    }

    // FCUrgencyFlashDimAlphaCurrent + FCUrgencyFlashIsDisabled read
    // NSUserDefaults; save/restore to keep tests independent.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *saved = [d stringForKey:@"UrgencyFlash"];

    [d removeObjectForKey:@"UrgencyFlash"];
    if (fabs(FCUrgencyFlashDimAlphaCurrent() - kFCUrgencyFlashDimAlpha) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: unset current → %.2f (want %.2f)\n",
                __func__, (double)FCUrgencyFlashDimAlphaCurrent(),
                (double)kFCUrgencyFlashDimAlpha);
    }
    if (FCUrgencyFlashIsDisabled()) {
        failures++; fprintf(stderr, "FAIL %s: unset should not be disabled\n", __func__);
    }

    [d setObject:@"off" forKey:@"UrgencyFlash"];
    if (fabs(FCUrgencyFlashDimAlphaCurrent() - 1.0) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: 'off' current → %.2f (want 1.0)\n",
                __func__, (double)FCUrgencyFlashDimAlphaCurrent());
    }
    if (!FCUrgencyFlashIsDisabled()) {
        failures++; fprintf(stderr, "FAIL %s: 'off' should be disabled\n", __func__);
    }
    // Integration check: with pulse off, FCUrgencyFlashAlpha should
    // return 1.0 even at imminent secs on the dim half of the pulse.
    // (epoch=0 → even → would dim under default; with off, stays full.)
    if (fabs(FCUrgencyFlashAlpha(5, 0) - 1.0) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: pulse off but FCUrgencyFlashAlpha(5, 0) = %.2f (want 1.0)\n",
                __func__, (double)FCUrgencyFlashAlpha(5, 0));
    }

    [d setObject:@"intense" forKey:@"UrgencyFlash"];
    if (fabs(FCUrgencyFlashAlpha(5, 0) - 0.15) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: 'intense' dim-half → %.2f (want 0.15)\n",
                __func__, (double)FCUrgencyFlashAlpha(5, 0));
    }
    // Above flash threshold always 1.0 regardless of preset.
    if (fabs(FCUrgencyFlashAlpha(60, 0) - 1.0) > 0.001) {
        failures++;
        fprintf(stderr, "FAIL %s: above-threshold → %.2f (want 1.0)\n",
                __func__, (double)FCUrgencyFlashAlpha(60, 0));
    }

    // Restore.
    if (saved) [d setObject:saved forKey:@"UrgencyFlash"];
    else       [d removeObjectForKey:@"UrgencyFlash"];
}

void test_week_fraction(void) {
    // iter-229: FCWeekFraction maps NSDate → fraction-into-week
    // (Mon midnight = 0.0, just before next Mon midnight = ~1.0).
    // Uses NSCalendar's currentCalendar (system locale) — tests
    // fix the components explicitly so locale-week-start doesn't
    // surprise us, and verify the Mon=0..Sun=6 zero-indexed math.
    NSCalendar *cal = [NSCalendar currentCalendar];
    struct { NSInteger year, mon, day, h, m, s; double expectMin, expectMax; const char *label; } cases[] = {
        // 2026-04-20 is Monday. Mon midnight = 0.0.
        {2026, 4, 20, 0, 0, 0,    0.0,        0.001,    "Mon midnight"},
        // 2026-04-20 12:00 = mid-Monday = 12/168 = 0.0714
        {2026, 4, 20, 12, 0, 0,   0.0714 - 0.001, 0.0714 + 0.001, "Mon noon"},
        // 2026-04-24 17:18 = Friday late afternoon
        // weekHours = 4*24 + 17.3 = 113.3 → 113.3/168 = 0.6744
        {2026, 4, 24, 17, 18, 0,  0.674 - 0.001, 0.674 + 0.001, "Fri 17:18"},
        // 2026-04-26 23:59:59 = end of Sunday, just before Mon
        // weekHours = 6*24 + 23 + 59/60 + 59/3600 = 167.9997 → 0.99998
        {2026, 4, 26, 23, 59, 59, 0.999, 1.001, "Sun end"},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        NSDateComponents *comp = [[NSDateComponents alloc] init];
        comp.year = cases[i].year; comp.month = cases[i].mon; comp.day = cases[i].day;
        comp.hour = cases[i].h;    comp.minute = cases[i].m;  comp.second = cases[i].s;
        NSDate *d = [cal dateFromComponents:comp];
        double got = FCWeekFraction(d);
        if (got < cases[i].expectMin || got > cases[i].expectMax) {
            failures++;
            fprintf(stderr, "FAIL %s: %s expected [%.4f, %.4f] got %.4f\n",
                    __func__, cases[i].label,
                    cases[i].expectMin, cases[i].expectMax, got);
        }
    }
    // nil safety
    if (FCWeekFraction(nil) != 0.0) {
        failures++;
        fprintf(stderr, "FAIL %s: nil → %.4f (want 0.0)\n", __func__, FCWeekFraction(nil));
    }
    // iter-230: structured 7-day bar — 7 × cellsPerDay + 6 separators.
    NSDateComponents *fri = [[NSDateComponents alloc] init];
    fri.year = 2026; fri.month = 4; fri.day = 24; fri.hour = 17; fri.minute = 18;
    NSDate *friDate = [cal dateFromComponents:fri];
    struct { int cpd; NSUInteger expectLen; } barCases[] = { {2, 20}, {4, 34} };
    for (size_t i = 0; i < 2; i++) {
        NSString *b = FCBuildWeekProgressBar(friDate, barCases[i].cpd);
        if (b.length != barCases[i].expectLen) {
            failures++; fprintf(stderr, "FAIL %s: cpd=%d len=%lu want %lu\n",
                    __func__, barCases[i].cpd, (unsigned long)b.length,
                    (unsigned long)barCases[i].expectLen);
        }
    }
    NSUInteger sepCount = [[FCBuildWeekProgressBar(friDate, 2) componentsSeparatedByString:@"┊"] count] - 1;
    if (sepCount != 6) { failures++; fprintf(stderr, "FAIL %s: %lu seps (want 6)\n", __func__, (unsigned long)sepCount); }
    if (FCBuildWeekProgressBar(nil, 2).length != 20) { failures++; fprintf(stderr, "FAIL %s: nil bar length\n", __func__); }
}

void test_phase_color_for_hour(void) {
    // iter-241: lock iter-240 phase boundaries 5/7/17/19. Day = nil.
    struct { NSInteger h; BOOL nilOk; } cases[] = {
        {3, NO}, {5, NO}, {6, NO}, {7, YES}, {12, YES}, {16, YES}, {17, NO}, {18, NO}, {19, NO}, {23, NO},
    };
    for (size_t i = 0; i < 10; i++) {
        BOOL g = (FCPhaseColorForHour(cases[i].h) == nil);
        if (g != cases[i].nilOk) { failures++; fprintf(stderr, "FAIL %s: h=%ld nil=%d (want %d)\n", __func__, (long)cases[i].h, g, cases[i].nilOk); }
    }
}
