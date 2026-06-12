// Solar-elevation → canvas color ramp — user directive 2026-06-11.
//
// "Colorful, not transparent": the compact clock's background derives its
// color from the CONTINUOUS solar elevation angle at the user's location
// (CoreLocation → FCSolarElevationDegrees), NOT from clock-hour buckets or
// hand-scheduled times. The schedule is authoritative ephemeris math; the
// palette is keyframed at the INTERNATIONAL twilight standards and blended
// in OKLab so the gradient stays perceptually smooth (no muddy midpoints).
//
// Research basis (2026-06-11 web survey):
//   · Keyframe elevations follow the standard twilight taxonomy:
//     -18° astronomical · -12° nautical · -6° civil · -4° blue hour ·
//     0° horizon · +6° golden hour · +20° day · +50° high sun.
//   · Anchor chromaticities informed by measured twilight colorimetry
//     (Lee 1994, Applied Optics 33:4629; Albers' twilight simulations).
//   · Interpolation in OKLCH with shortest-arc hue (Ottosson's OKLab) —
//     the community-converged answer to gray dead zones in RGB lerps.
//
// Two styles (catalog locked by tests/test_levers.m):
//   solar-vivid        DEFAULT — maximal chroma at every hour; night is a
//                      rich violet-indigo, never near-black. The sunset
//                      day→horizon hue arc deliberately sweeps through
//                      magenta/pink (shortest-arc 245°→400°).
//   solar-atmospheric  faithful to the real sky — subdued night blues,
//                      drama reserved for twilight, pale daylight.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    double r, g, b;        // sRGB 0..1, gamut-clamped
    BOOL   preferDarkText; // YES when the color is light enough that white
                           // text would wash out (relative luminance test)
} FCSolarCanvasColor;

// Continuous color for a solar elevation in degrees (clamped to ±90).
// styleId: "solar-vivid" | "solar-atmospheric"; nil/unknown → vivid.
FCSolarCanvasColor FCSolarCanvasColorForElevation(double elevationDeg,
                                                  NSString *_Nullable styleId);

NS_ASSUME_NONNULL_END
