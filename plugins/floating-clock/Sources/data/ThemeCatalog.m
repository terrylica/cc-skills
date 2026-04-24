#import "ThemeCatalog.h"
#include <string.h>

const ClockTheme kThemes[] = {
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
