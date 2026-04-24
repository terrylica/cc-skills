// v4 iter-120: `FCShadowSpecForId` — ShadowStyle pref → numeric spec.
//
// ShadowStyle is more complex than the other catalog dispatchers
// (iter-115 SegmentGap, iter-116 DensityPad, iter-117 CornerRadius)
// because it writes multiple CALayer properties AND some styles
// (`glow`, `halo`) use theme-derived colors rather than plain black.
//
// Design: the helper returns a pure-data spec struct with (a) a color-
// source enum indicating whether the caller should look up the theme
// foreground / theme background / or just use black, and (b) the
// numeric parameters (opacity / offset / radius). Layout.m owns the
// CALayer write + color substitution.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum {
    FCShadowColorBlack = 0,
    FCShadowColorThemeForeground,
    FCShadowColorThemeBackground,
} FCShadowColorSource;

typedef struct {
    BOOL enabled;              // NO for "none" — caller zeros shadowOpacity
    FCShadowColorSource colorSource;
    CGFloat opacity;
    CGFloat offsetX, offsetY;
    CGFloat radius;
} FCShadowSpec;

// Returns the spec for the supplied id. Unknown / nil / empty ids
// return {enabled = NO} (matches the registered "none" default).
FCShadowSpec FCShadowSpecForId(NSString * _Nullable shadowId);

NS_ASSUME_NONNULL_END
