// Color theme catalog. Each ClockTheme bundles foreground + background RGB
// and the background alpha. Catalog is a compile-time C array —
// themeForId() does a linear scan; first entry is the fallback.
//
// Swatch rendering stays close to the catalog so menu construction can
// decorate theme-picker items without importing AppKit from C callers.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    const char *id;              // NSUserDefaults value, e.g. "terminal"
    const char *display;         // Menu label, e.g. "Terminal"
    double fg_r, fg_g, fg_b;     // 0.0–1.0
    double bg_r, bg_g, bg_b;     // 0.0–1.0
    double alpha;                // 0.0–1.0
} ClockTheme;

extern const ClockTheme kThemes[];
extern const size_t kNumThemes;

const ClockTheme *themeForId(NSString * _Nullable idStr);

// 14×14 NSImage swatch: rounded bg rect with inner fg square.
NSImage *swatchForTheme(const ClockTheme *t);

NS_ASSUME_NONNULL_END
