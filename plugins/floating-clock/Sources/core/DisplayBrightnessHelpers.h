// Pure brightness arithmetic — the testable half of the brightness rail.
//
// Deliberately Foundation-ONLY (no AppKit, no CoreGraphics, no NSScreen, no
// CGDirectDisplayID), exactly like OverlayWidthConsensus and the pure parts of
// NetworkTelemetry, so it stays in the headless test link rather than being
// excluded from it. Everything that needs a display handle, a Metal device or
// a private framework lives next door in FCXDRBrightness.
//
// The one formula here worth reading twice is FCMaxSafeFactorForHeadroom.
// It is CLEAN-ROOM: derived from measurements taken on this machine, not
// transcribed from BrightIntosh (GPL-3.0), which the MIT licence of this repo
// would not permit. See FCXDRBrightness.h for the full clean-room notice.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// The rail's ceiling, in percent. 100 == the top of the macOS brightness
// slider; anything above is EDR territory. 140 is our own choice, set just
// above the ~137 % that measured comfortable on an M3 Max Liquid Retina XDR
// panel, and the APPLIED factor is independently clamped to live headroom
// (see FCAppliedFactorForLevel), so asking for more than the panel can give
// is safe rather than clipped.
extern const NSInteger kFCMaxBoostLevelPercent;

// Fraction of the available headroom we are willing to consume. Chosen, not
// inherited: at the measured settled headroom of a slider-pinned XDR panel
// (~2.05x) this yields ~1.37x, which is the value that was A/B-demonstrated
// and confirmed visible. Raising it brightens further but pushes the top of
// the ramp toward clipping, where a greyscale wedge's brightest steps merge.
extern const double kFCHeadroomUtilization;

// Absolute ceiling on the gamma factor regardless of how much headroom a
// panel reports. Headroom climbs as the SDR white point falls, so without
// this a dimmed panel would compute an absurd factor.
extern const double kFCAbsoluteFactorCap;

// A freshly captured baseline gamma ramp must have its top entry at or below
// this to be trusted. Above it we are looking at an ALREADY-BOOSTED ramp, and
// storing that as the new baseline would square the factor on every capture —
// an unbounded blow-out measured at 1.2952 -> 1.6776 (= 1.2952^2) on a single
// sleep/wake cycle. Guarding the capture is what makes that bug unreachable.
extern const double kFCGammaNeutralTolerance;

// Clamp a raw 0..1 display brightness. NaN maps to 0.0 rather than
// propagating: a NaN reaching CGSetDisplayTransferByTable or the brightness
// SPI is a silent, un-debuggable black screen.
double FCClampBrightness(double value);

// Clamp a rail level (percent) into 0...maxLevel. A maxLevel below 100 is
// raised to 100 — the normal slider range is always available even when no
// boost is.
NSInteger FCClampLevelPercent(NSInteger level, NSInteger maxLevel);

// Apply a step to a level, saturating at both rails. Separated from the
// clamp so a caller can express "nudge by the user's configured step" without
// restating the bounds.
NSInteger FCApplyLevelDelta(NSInteger level, NSInteger delta, NSInteger maxLevel);

// The user's configured step size, sanitised. Unset/garbage -> 5, capped at
// 25. Mirrors +[FCAudioZoneView stepPercent] so the two rails behave alike.
NSInteger FCBrightnessStepPercent(NSInteger rawDefaultsValue);

// Largest gamma factor it is safe to ask for at this much EDR headroom.
//
// Monotonically INCREASING in headroom and never below 1.0. headroom <= 1.0
// means the compositor is granting nothing (a non-XDR panel, or EDR not yet
// engaged), so the answer is exactly 1.0 — no boost, no gamma write at all.
double FCMaxSafeFactorForHeadroom(double headroom);

// The factor to actually apply for a requested rail level at the headroom
// currently granted. Levels at or below 100 are the macOS slider's job and
// return 1.0. Above 100 the request is clamped by FCMaxSafeFactorForHeadroom,
// so a user who drags past what the panel can deliver gets the panel's
// maximum rather than a clipped ramp.
double FCAppliedFactorForLevel(NSInteger level, double headroom);

// YES when a captured gamma ramp's top entry looks like an untouched
// baseline. The anti-compounding invariant: never store a ramp as a baseline
// unless this says yes.
BOOL FCGammaBaselineIsNeutral(double topEntry);

// Split a rail level into its two mechanisms. `outSlider` receives the 0..1
// value for the macOS brightness SPI (pinned to 1.0 once the level exceeds
// 100, because the boost stacks on top of a maxed slider); `outFactor`
// receives the gamma factor. Either pointer may be NULL.
void FCDecomposeLevel(NSInteger level, double headroom,
                      double *_Nullable outSlider, double *_Nullable outFactor);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
