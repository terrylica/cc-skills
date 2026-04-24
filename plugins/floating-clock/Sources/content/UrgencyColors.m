#import "UrgencyColors.h"
#import "UrgencyHorizon.h"  // iter-215: runtime user-pref horizon
#include <math.h>

// Legacy iter-73 thresholds. Production callers (iter-212+) use the
// continuous-mode constants below; these stay for back-compat with
// FCUrgencyColorForSecs and the test fixture that locks step semantics.
const long kFCUrgencyRedThresholdSecs   = 30 * 60;   // 1800 s — last half-hour
const long kFCUrgencyAmberThresholdSecs = 60 * 60;   // 3600 s — last hour

// iter-212 continuous-mode SSoT. Tweak any of these and both ACTIVE +
// NEXT update simultaneously. See header for the design rationale
// (Weber-Fechner log scale + HSB hue rotation + 1Hz alpha pulse).
const long kFCUrgencyHorizonSecs        = 60 * 60;     // 3600 s — gradient starts
const long kFCUrgencyImminentSecs       = 60;          //   60 s — gradient saturates at red
const long kFCUrgencyFlashThresholdSecs = 30;          //   30 s — pulse kicks in
const CGFloat kFCUrgencyHueGreenDeg     = 120.0;       // green endpoint
const CGFloat kFCUrgencyHueRedDeg       = 0.0;         // red endpoint
const CGFloat kFCUrgencySaturation      = 0.85;
const CGFloat kFCUrgencyBrightness      = 0.95;
const CGFloat kFCUrgencyFlashDimAlpha   = 0.45;

NSColor *FCUrgencyAmberColor(void) {
    return [NSColor colorWithRed:0.95 green:0.75 blue:0.30 alpha:1.0];
}

NSColor *FCUrgencyRedColor(void) {
    return [NSColor colorWithRed:0.95 green:0.40 blue:0.40 alpha:1.0];
}

NSColor *FCUrgencyColorForSecs(long secs, NSColor *normalColor) {
    if (secs < kFCUrgencyRedThresholdSecs)   return FCUrgencyRedColor();
    if (secs < kFCUrgencyAmberThresholdSecs) return FCUrgencyAmberColor();
    return normalColor;
}

NSColor *FCUrgencyContinuousColor(long secs, NSColor *normalColor) {
    // iter-215: horizon is now user-configurable via the
    // UrgencyHorizon pref. Day-traders pick 5min for a tight
    // closing-bell glow; macro-watchers pick 240min for slow overnight
    // build. Falls back to kFCUrgencyHorizonSecs (60 min, iter-212)
    // when unset, so existing installs keep their current behavior.
    long horizonSecs = FCUrgencyHorizonSecsCurrent();

    // Above horizon: caller's theme color, untouched. The transition
    // at the horizon boundary is one-time, not visually jarring.
    if (secs >= horizonSecs) return normalColor;

    // At/below imminent threshold: fully saturated red, no logarithm.
    // Clamps the curve so the visual doesn't get muddy near zero.
    if (secs <= kFCUrgencyImminentSecs) {
        return [NSColor colorWithHue:(kFCUrgencyHueRedDeg / 360.0)
                          saturation:kFCUrgencySaturation
                          brightness:kFCUrgencyBrightness
                               alpha:1.0];
    }

    // Weber-Fechner log scaling. t in [0, 1].
    //   secs == horizonSecs              → t = 0  (green endpoint)
    //   secs == kFCUrgencyImminentSecs   → t = 1  (red endpoint)
    // Equal log-secs intervals produce equal perceptual jumps.
    double horizon  = (double)horizonSecs;
    double imminent = (double)kFCUrgencyImminentSecs;
    double s        = (double)secs;
    double t = (log(horizon + 1.0) - log(s + 1.0))
             / (log(horizon + 1.0) - log(imminent + 1.0));
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;

    // Linear hue interpolation — heat-map / traffic-light convention.
    CGFloat hueDeg = kFCUrgencyHueGreenDeg
                   + (kFCUrgencyHueRedDeg - kFCUrgencyHueGreenDeg) * (CGFloat)t;
    return [NSColor colorWithHue:(hueDeg / 360.0)
                      saturation:kFCUrgencySaturation
                      brightness:kFCUrgencyBrightness
                           alpha:1.0];
}

CGFloat FCUrgencyFlashAlpha(long secs, long nowEpoch) {
    // 1Hz pulse: alternate full / dim each second. Reuses the
    // panel's existing per-second tick — no flicker timer needed.
    // Cursor-blink convention: dim is ~half intensity.
    if (secs >= kFCUrgencyFlashThresholdSecs) return 1.0;
    return (nowEpoch & 1L) ? 1.0 : kFCUrgencyFlashDimAlpha;
}

NSColor *FCUrgencyAlertColor(long secs, NSColor *normalColor, long nowEpoch) {
    NSColor *base = FCUrgencyContinuousColor(secs, normalColor);
    CGFloat flash = FCUrgencyFlashAlpha(secs, nowEpoch);
    if (flash >= 0.999) return base;
    // Multiply: preserves any base-alpha (theme transparency) while
    // applying the pulse modulation on top.
    CGFloat baseAlpha = base.alphaComponent;
    return [base colorWithAlphaComponent:(baseAlpha * flash)];
}

NSColor *FCProgressEmptyColor(void) {
    return [NSColor colorWithWhite:0.40 alpha:0.55];
}

NSColor *FCDividerRuleColor(void) {
    return [NSColor colorWithWhite:0.40 alpha:0.55];
}
