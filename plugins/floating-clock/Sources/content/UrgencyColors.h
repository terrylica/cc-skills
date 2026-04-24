// Shared urgency-tier color palette used by ACTIVE (time to close)
// and NEXT (time to open/resume) countdowns. Extracted v4 iter-73
// per user directive: magic-numberless + SSoT.
//
// LEGACY (iter-73): 3-tier step function.
//   secs >= kFCUrgencyAmberThresholdSecs   →  caller-provided normalColor
//   secs <  kFCUrgencyAmberThresholdSecs   →  FCUrgencyAmberColor()
//   secs <  kFCUrgencyRedThresholdSecs     →  FCUrgencyRedColor()
//
// CONTINUOUS (iter-212): imminence-aware HSB hue interpolation +
// optional flashing as the event approaches. Pattern sources:
//
//   * Weber-Fechner law — human intensity perception is
//     logarithmic. Mapping secs→urgency via `1 - log(s+1)/log(H+1)`
//     gives equal perceptual jumps at equal log-secs intervals
//     (60min→30min feels like the same step as 30min→15min).
//
//   * HSB hue rotation 120°→0° — heat-map / traffic-light
//     convention. Green = safe; red = alert. Saturation +
//     brightness held constant for vivid alarm colors. Conventional
//     in OS dashboards, weather apps, telemetry UIs (Grafana,
//     Datadog, Apple's Health Trends).
//
//   * 1Hz alpha pulse — cursor-blink convention. Reuses the
//     panel's existing 1Hz tick; alpha alternates between 1.0
//     and kFCUrgencyFlashDimAlpha on even/odd second of the epoch.
//     Caller passes `nowEpoch` so the function stays
//     deterministic + testable.
//
// All numeric constants live below as `extern const` — this
// header is the single source of truth for the urgency system,
// patchable in one place.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Legacy 3-tier step thresholds (kept for back-compat + the existing
// test fixture that locks the step behavior).
extern const long kFCUrgencyRedThresholdSecs;    // <30 min  — imminent
extern const long kFCUrgencyAmberThresholdSecs;  // <60 min  — approaching

// iter-212 continuous-mode SSoT constants. Tweak any of these here
// and both ACTIVE + NEXT update simultaneously.
extern const long kFCUrgencyHorizonSecs;             // ≥this: normalColor (theme), no urgency tint
extern const long kFCUrgencyImminentSecs;            // ≤this: fully saturated red — clamps the log curve
extern const long kFCUrgencyFlashThresholdSecs;      // <this: 1Hz alpha pulse kicks in
extern const CGFloat kFCUrgencyHueGreenDeg;          // 120° — color at horizon
extern const CGFloat kFCUrgencyHueRedDeg;            //   0° — color at imminent
extern const CGFloat kFCUrgencySaturation;           // HSB saturation for the gradient
extern const CGFloat kFCUrgencyBrightness;           // HSB brightness for the gradient
extern const CGFloat kFCUrgencyFlashDimAlpha;        // alpha on the dim half of the pulse

// Legacy palette + step lookup (iter-73). Still used by the legacy
// test fixture; production callers should prefer FCUrgencyAlertColor
// from iter-212 for smooth gradient + pulse behavior.
NSColor *FCUrgencyAmberColor(void);
NSColor *FCUrgencyRedColor(void);
NSColor *FCUrgencyColorForSecs(long secs, NSColor *normalColor);

// iter-212 continuous-mode color: HSB hue interpolated from
// kFCUrgencyHueGreenDeg (at horizon) to kFCUrgencyHueRedDeg (at
// imminent) on a Weber-Fechner log scale. Above horizon: returns
// `normalColor` unchanged (theme-respecting). Below imminent:
// clamps to fully saturated alert color. Pure function — no
// time/global state.
NSColor *FCUrgencyContinuousColor(long secs, NSColor *normalColor);

// iter-212 flash modulator. Returns 1.0 above kFCUrgencyFlashThresholdSecs;
// alternates 1.0 / kFCUrgencyFlashDimAlpha based on (nowEpoch & 1)
// below it — gives a 1Hz pulse synchronized to the panel's per-
// second tick. Pass `time(NULL)` from the caller; the function
// stays deterministic + testable for any input epoch.
CGFloat FCUrgencyFlashAlpha(long secs, long nowEpoch);

// iter-212 combined entry point: continuous color × flash alpha.
// Production callers (ACTIVE / NEXT countdown rendering) should
// use this — gives smooth color gradient AND imminence pulse in
// one call.
NSColor *FCUrgencyAlertColor(long secs, NSColor *normalColor, long nowEpoch);

// Shared background/empty color for progress-bar "unfilled" cells.
// Centralizes the one RGB that was duplicated in both builders.
NSColor *FCProgressEmptyColor(void);

// Shared horizontal-rule color. Used by SegmentHeaderRenderer's rules
// and by any caller that wants a consistent dim divider.
NSColor *FCDividerRuleColor(void);

NS_ASSUME_NONNULL_END
