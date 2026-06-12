// WCAG relative luminance — DRY extraction 2026-06-12.
//
// The 0.2126/0.7152/0.0722 coefficient triple was duplicated between the
// solar canvas ramp (text-contrast decision) and the hairline-border color
// picker. This is the single source of truth for the coefficients; the
// DECISION THRESHOLDS deliberately stay at each call site (text contrast
// at 0.45 vs border tone at 0.5 are different judgments — coupling them
// here would be false sharing).
//
// Input: sRGB-ish components in 0..1. Callers pass what they have (linear
// at the ramp, gamma-encoded at the border picker) — for THRESHOLDING
// against a tuned constant that's fine; this is not a colorimetry library.
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

double FCRelativeLuminance(double r, double g, double b);

#ifdef __cplusplus
}
#endif
