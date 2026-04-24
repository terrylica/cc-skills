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
#import "../Sources/preferences/FloatingClockQuickStyles.h"

void test_font_weight_parser(void) {
    // Known ids map to their NSFontWeight constants.
    struct { NSString *id; NSFontWeight w; } cases[] = {
        {@"regular",  NSFontWeightRegular},
        {@"medium",   NSFontWeightMedium},
        {@"semibold", NSFontWeightSemibold},
        {@"bold",     NSFontWeightBold},
        {@"heavy",    NSFontWeightHeavy},
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
    if (kNumThemes != 25) {
        fprintf(stderr, "FAIL %s: expected 25 themes got %zu\n", __func__, kNumThemes);
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
        {@"compact", -1.0}, {@"tight", -0.5}, {@"normal", 0.0},
        {@"airy", 0.5}, {@"wide", 1.0},
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
        {@"soft",      100, 40, 10.0},
        {@"squircle",  100, 40, 14.0},
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
        {@"ultracompact", 4}, {@"compact", 12}, {@"default", 24},
        {@"comfortable", 36}, {@"spacious", 48}, {@"cavernous", 64},
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
        {@"airy", 8}, {@"spacious", 14}, {@"cavernous", 24},
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
                                                  @"soft", @"squircle", @"jumbo", @"pill"]],
        @"ShadowStyle":    [NSSet setWithArray:@[@"none", @"subtle", @"lifted", @"glow",
                                                  @"crisp", @"plinth", @"halo"]],
        @"Density":        [NSSet setWithArray:@[@"ultracompact", @"compact", @"default",
                                                  @"comfortable", @"spacious", @"cavernous"]],
        @"FontWeight":     [NSSet setWithArray:@[@"regular", @"medium", @"semibold",
                                                  @"bold", @"heavy"]],
        @"LetterSpacing":  [NSSet setWithArray:@[@"compact", @"tight", @"normal", @"airy", @"wide"]],
        @"LineSpacing":    [NSSet setWithArray:@[@"tight", @"snug", @"normal", @"loose", @"airy"]],
        @"TimeSeparator":  [NSSet setWithArray:@[@"colon", @"middot", @"space", @"slash", @"dash"]],
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
