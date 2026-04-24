#import "ThemeCatalog.h"
#include <string.h>

const ClockTheme kThemes[] = {
    // Original 10.
    {"terminal",      "Terminal",       1.00, 1.00, 1.00,  0.00, 0.00, 0.00, 0.32},
    {"amber_crt",     "Amber CRT",      1.00, 0.75, 0.00,  0.00, 0.00, 0.00, 0.38},
    {"green_phosphor","Green Phosphor", 0.18, 0.98, 0.36,  0.00, 0.00, 0.00, 0.35},
    {"solarized_dark","Solarized Dark", 0.71, 0.54, 0.00,  0.00, 0.17, 0.21, 0.40},
    {"dracula",       "Dracula",        0.74, 0.58, 0.98,  0.16, 0.16, 0.21, 0.45},
    {"nord",          "Nord",           0.53, 0.75, 0.82,  0.18, 0.20, 0.25, 0.45},
    {"gruvbox",       "Gruvbox",        0.98, 0.74, 0.18,  0.16, 0.16, 0.16, 0.42},
    {"rose_pine",     "Rose Pine",      0.92, 0.74, 0.73,  0.10, 0.09, 0.15, 0.42},
    {"high_contrast", "High Contrast",  1.00, 1.00, 1.00,  0.00, 0.00, 0.00, 1.00},
    {"soft_glass",    "Soft Glass",     0.96, 0.96, 0.97,  0.00, 0.00, 0.00, 0.18},
    // v4 iter-32: +10 editor / curated palettes (20 themes total).
    {"synthwave",     "Synthwave",      1.00, 0.00, 0.63,  0.10, 0.00, 0.20, 0.55},
    {"monokai",       "Monokai",        0.97, 0.97, 0.95,  0.15, 0.16, 0.13, 0.50},
    {"gotham",        "Gotham",         0.83, 0.77, 0.63,  0.05, 0.06, 0.08, 0.55},
    {"ayu_mirage",    "Ayu Mirage",     1.00, 0.80, 0.40,  0.12, 0.14, 0.19, 0.50},
    {"catppuccin",    "Catppuccin",     0.80, 0.84, 0.96,  0.12, 0.12, 0.18, 0.50},
    {"tokyo_night",   "Tokyo Night",    0.75, 0.79, 0.96,  0.10, 0.11, 0.15, 0.55},
    {"kanagawa",      "Kanagawa",       0.86, 0.84, 0.73,  0.12, 0.12, 0.16, 0.50},
    {"paper_white",   "Paper White",    0.18, 0.20, 0.25,  0.93, 0.94, 0.95, 0.85},
    {"sepia",         "Sepia",          0.40, 0.26, 0.13,  0.96, 0.93, 0.85, 0.85},
    {"midnight_blue", "Midnight Blue",  0.40, 0.85, 1.00,  0.00, 0.12, 0.25, 0.60},
    // v4 iter-92: +5 mood palettes (25 themes total).
    {"oceanic_deep",  "Oceanic Deep",   0.55, 0.85, 0.95,  0.05, 0.12, 0.25, 0.55},
    {"cherry_blossom","Cherry Blossom", 0.98, 0.70, 0.80,  0.15, 0.08, 0.12, 0.50},
    {"espresso",      "Espresso",       0.95, 0.85, 0.72,  0.15, 0.08, 0.05, 0.55},
    {"lavender_dream","Lavender Dream", 0.82, 0.75, 0.96,  0.08, 0.06, 0.15, 0.50},
    {"mint_dark",     "Mint Dark",      0.50, 0.98, 0.75,  0.04, 0.15, 0.10, 0.50},
    // v4 iter-132: +2 mood palettes (27 themes total). forest = deep evergreen
    // canopy (mossy green on pine-needle near-black). volcanic = molten crimson
    // (warm red on charred obsidian) — a fiercer counterpart to amber_crt.
    {"forest",        "Forest",         0.55, 0.90, 0.60,  0.03, 0.10, 0.05, 0.52},
    {"volcanic",      "Volcanic",       0.98, 0.35, 0.15,  0.10, 0.02, 0.02, 0.55},
    // v4 iter-169: pairs with iter-161's B3 (São Paulo) addition.
    // Brazilian-flag-inspired: warm yellow on deep-green jungle.
    {"carnival",      "Carnival",       0.98, 0.90, 0.20,  0.05, 0.35, 0.15, 0.55},
    // v4 iter-195: aurora borealis — cyan-green foreground on deep
    // indigo-black background. Cool winter-night mood, distinct
    // from the warm amber/red/carnival themes and from the more
    // desaturated nord / tokyo_night. 29th theme.
    {"aurora",        "Aurora",         0.35, 0.92, 0.82,  0.03, 0.05, 0.12, 0.45},
};
const size_t kNumThemes = sizeof(kThemes) / sizeof(kThemes[0]);

const ClockTheme *themeForId(NSString *idStr) {
    if (!idStr) return &kThemes[0];
    const char *cstr = idStr.UTF8String;
    for (size_t i = 0; i < kNumThemes; i++) {
        if (strcmp(kThemes[i].id, cstr) == 0) return &kThemes[i];
    }
    return &kThemes[0];
}

NSImage *swatchForTheme(const ClockTheme *t) {
    NSSize sz = NSMakeSize(14, 14);
    NSImage *img = [[NSImage alloc] initWithSize:sz];
    [img lockFocus];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 12, 12)
                                                       xRadius:3 yRadius:3];
    [[NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:1.0] setFill];
    [p fill];
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3, 3, 8, 8)
                                                           xRadius:2 yRadius:2];
    [[NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0] setFill];
    [inner fill];
    [img unlockFocus];
    img.template = NO;
    return img;
}
