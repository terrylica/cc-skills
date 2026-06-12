#import "SolarSkyColorRamp.h"
#import <math.h>

#pragma mark - OKLab → sRGB (Björn Ottosson's reference matrices)

// OKLab (L, a, b) → linear sRGB. Standard published transform.
static void fcOKLabToLinearSRGB(double L, double a, double b,
                                double *outR, double *outG, double *outB) {
    double l_ = L + 0.3963377774 * a + 0.2158037573 * b;
    double m_ = L - 0.1055613458 * a - 0.0638541728 * b;
    double s_ = L - 0.0894841775 * a - 1.2914855480 * b;
    double l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    *outR = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    *outG = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    *outB = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
}

static double fcLinearToSRGB(double c) {
    if (c <= 0.0031308) return 12.92 * c;
    return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

static double fcClamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

#pragma mark - Anchor catalogs (OKLCH keyed to twilight-standard elevations)

typedef struct {
    double elev;   // solar elevation degrees
    double L;      // OKLab lightness 0..1
    double C;      // OKLCH chroma
    double hDeg;   // OKLCH hue degrees
} FCRampAnchor;

// VIVID — "as colorful as possible": high chroma everywhere, night is a
// rich violet-indigo. The day(245°)→horizon(400°≡40°) hue arc passes
// through magenta/pink: sunsets bloom instead of graying out.
static const FCRampAnchor kVivid[] = {
    { -90.0, 0.30, 0.15, 295.0 },   // deep-night floor
    { -18.0, 0.34, 0.17, 292.0 },   // astronomical boundary — deep violet-indigo
    { -12.0, 0.42, 0.20, 282.0 },   // nautical — electric indigo
    {  -6.0, 0.50, 0.20, 300.0 },   // civil — royal blue-magenta
    {  -4.0, 0.52, 0.20, 262.0 },   // blue hour — saturated cobalt
    {   0.0, 0.66, 0.19, 400.0 },   // horizon — fiery orange-pink (400≡40, arc via magenta)
    {   6.0, 0.76, 0.15, 440.0 },   // golden hour — warm amber-gold (440≡80)
    // Day-side continues UP the hue circle (preview-validated 2026-06-11:
    // descending 440→245 retraced magenta and made mid-morning purple).
    // 440→605 sweeps gold → green → cyan → azure: a true rainbow day arc,
    // and mornings/evenings stay distinguishable from the sunset magentas.
    {  20.0, 0.64, 0.16, 605.0 },   // day — vivid azure (605≡245, arc via green/cyan)
    {  50.0, 0.72, 0.13, 590.0 },   // high sun — bright cerulean (590≡230)
    {  90.0, 0.74, 0.12, 585.0 },   // zenith (585≡225)
};

// ATMOSPHERIC — faithful to measured twilight colorimetry (Lee 1994):
// near-black blue night, indigo twilight, golden-pink horizon, pale day.
static const FCRampAnchor kAtmospheric[] = {
    { -90.0, 0.13, 0.03, 265.0 },
    { -18.0, 0.15, 0.04, 265.0 },   // night
    { -12.0, 0.22, 0.08, 264.0 },   // astronomical→nautical deep blue
    {  -6.0, 0.32, 0.11, 262.0 },   // civil — dark indigo
    {  -4.0, 0.40, 0.13, 258.0 },   // blue hour
    {   0.0, 0.70, 0.13, 415.0 },   // horizon — golden-pink (415≡55, arc via pink)
    {   6.0, 0.82, 0.10, 445.0 },   // golden hour — soft gold (445≡85)
    {  20.0, 0.74, 0.10, 240.0 },   // sky blue
    {  50.0, 0.85, 0.07, 235.0 },   // pale daylight
    {  90.0, 0.87, 0.06, 233.0 },
};

#pragma mark - Ramp evaluation

// Hue values in the tables are MONOTONIC-ARC encoded: where a sweep should
// pass through specific intermediate hues, the anchor stores hue+360. The
// arc decision was made once, at catalog-design time, where it is
// reviewable — not re-derived per frame.
//
// Two interpolation geometries (preview-validated 2026-06-11):
//   polar (LCh)      — VIVID: chroma is preserved across hue sweeps, so the
//                      ramp stays saturated through every transition.
//   cartesian (Lab)  — ATMOSPHERIC: warm→blue crossfades pass through the
//                      neutral axis and naturally desaturate, like the real
//                      sky — never through an artificial purple.
static FCSolarCanvasColor fcEvalRamp(const FCRampAnchor *anchors, int count,
                                     double elev, BOOL cartesian) {
    if (elev < anchors[0].elev)         elev = anchors[0].elev;
    if (elev > anchors[count - 1].elev) elev = anchors[count - 1].elev;

    int i = 0;
    while (i < count - 2 && elev > anchors[i + 1].elev) i++;
    const FCRampAnchor *lo = &anchors[i], *hi = &anchors[i + 1];
    double t = (hi->elev > lo->elev) ? (elev - lo->elev) / (hi->elev - lo->elev) : 0.0;

    double L = lo->L + t * (hi->L - lo->L);
    double a, b;
    if (cartesian) {
        double hLo = lo->hDeg * M_PI / 180.0, hHi = hi->hDeg * M_PI / 180.0;
        a = (lo->C * cos(hLo)) + t * (hi->C * cos(hHi) - lo->C * cos(hLo));
        b = (lo->C * sin(hLo)) + t * (hi->C * sin(hHi) - lo->C * sin(hLo));
    } else {
        double C = lo->C + t * (hi->C - lo->C);
        double h = (lo->hDeg + t * (hi->hDeg - lo->hDeg)) * M_PI / 180.0;
        a = C * cos(h);
        b = C * sin(h);
    }

    double rl, gl, bl;
    fcOKLabToLinearSRGB(L, a, b, &rl, &gl, &bl);

    FCSolarCanvasColor out;
    out.r = fcClamp01(fcLinearToSRGB(fcClamp01(rl)));
    out.g = fcClamp01(fcLinearToSRGB(fcClamp01(gl)));
    out.b = fcClamp01(fcLinearToSRGB(fcClamp01(bl)));
    // WCAG-style relative luminance on the final sRGB — light canvases need
    // dark ink (the golden-hour and pale-day anchors cross this line).
    double lum = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
    out.preferDarkText = (lum > 0.45);
    return out;
}

FCSolarCanvasColor FCSolarCanvasColorForElevation(double elevationDeg,
                                                  NSString *styleId) {
    if ([styleId isEqualToString:@"solar-atmospheric"]) {
        return fcEvalRamp(kAtmospheric,
                          (int)(sizeof(kAtmospheric) / sizeof(kAtmospheric[0])),
                          elevationDeg, /*cartesian*/ YES);
    }
    // "solar-vivid" + nil/unknown → vivid (the user-selected default).
    return fcEvalRamp(kVivid,
                      (int)(sizeof(kVivid) / sizeof(kVivid[0])),
                      elevationDeg, /*cartesian*/ NO);
}
