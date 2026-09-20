#import "DisplayBrightnessHelpers.h"
#import <math.h>

const NSInteger kFCMaxBoostLevelPercent = 140;
const double    kFCHeadroomUtilization  = 0.35;
const double    kFCAbsoluteFactorCap    = 1.60;
const double    kFCGammaNeutralTolerance = 1.01;

double FCClampBrightness(double value) {
    if (isnan(value)) return 0.0;   // never let a NaN reach the display SPI
    if (value < 0.0)  return 0.0;
    if (value > 1.0)  return 1.0;
    return value;
}

NSInteger FCClampLevelPercent(NSInteger level, NSInteger maxLevel) {
    if (maxLevel < 100) maxLevel = 100;   // the slider range is always available
    if (level < 0)        return 0;
    if (level > maxLevel) return maxLevel;
    return level;
}

NSInteger FCApplyLevelDelta(NSInteger level, NSInteger delta, NSInteger maxLevel) {
    return FCClampLevelPercent(level + delta, maxLevel);
}

NSInteger FCBrightnessStepPercent(NSInteger rawDefaultsValue) {
    NSInteger s = rawDefaultsValue;
    if (s < 1)  s = 5;    // unset (0) or garbage → default
    if (s > 25) s = 25;
    return s;
}

double FCMaxSafeFactorForHeadroom(double headroom) {
    // No grant (non-XDR panel, or EDR not engaged yet) → no boost. Returning
    // exactly 1.0 here is what makes the whole feature degrade silently and
    // safely on hardware that cannot do it: the caller writes no gamma at all.
    if (isnan(headroom) || headroom <= 1.0) return 1.0;

    // Consume a fixed fraction of what the compositor granted. Linear in the
    // headroom ABOVE 1.0, because headroom of exactly 1.0 means "nothing
    // extra" and must map to a factor of exactly 1.0 with no discontinuity.
    double f = 1.0 + kFCHeadroomUtilization * (headroom - 1.0);
    if (f > kFCAbsoluteFactorCap) f = kFCAbsoluteFactorCap;
    if (f < 1.0) f = 1.0;
    return f;
}

double FCAppliedFactorForLevel(NSInteger level, double headroom) {
    if (level <= 100) return 1.0;   // the macOS slider owns this range
    double requested = (double)level / 100.0;
    double ceiling   = FCMaxSafeFactorForHeadroom(headroom);
    return (requested > ceiling) ? ceiling : requested;
}

BOOL FCGammaBaselineIsNeutral(double topEntry) {
    if (isnan(topEntry)) return NO;
    return topEntry <= kFCGammaNeutralTolerance;
}

void FCDecomposeLevel(NSInteger level, double headroom,
                      double *outSlider, double *outFactor) {
    if (level < 0) level = 0;
    // Above 100 the slider is pinned at its maximum and the extra comes from
    // gamma — "beyond maximum" only means anything once the maximum is in use.
    double slider = (level >= 100) ? 1.0 : ((double)level / 100.0);
    if (outSlider) *outSlider = FCClampBrightness(slider);
    if (outFactor) *outFactor = FCAppliedFactorForLevel(level, headroom);
}
