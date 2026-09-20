// Brightness-rail arithmetic fixtures. See test_brightness.h for scope.
#import "test_brightness.h"
#import "../Sources/core/DisplayBrightnessHelpers.h"
#import <math.h>

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

#define CHECK_CLOSE(got, want, tol, label)                                     \
    CHECK(fabs((got) - (want)) <= (tol),                                       \
          "%@: got %.4f want %.4f", label, (double)(got), (double)(want))

void test_clamp_brightness(void) {
    CHECK_CLOSE(FCClampBrightness(0.0),  0.0, 1e-9, @"0.0 passes through");
    CHECK_CLOSE(FCClampBrightness(1.0),  1.0, 1e-9, @"1.0 passes through");
    CHECK_CLOSE(FCClampBrightness(0.42), 0.42, 1e-9, @"mid passes through");
    CHECK_CLOSE(FCClampBrightness(-0.5), 0.0, 1e-9, @"negative clamps to 0");
    CHECK_CLOSE(FCClampBrightness(1.5),  1.0, 1e-9, @"above 1 clamps to 1");
    // NaN must become 0, not propagate. A NaN reaching the display SPI or
    // CGSetDisplayTransferByTable is an un-debuggable black screen.
    CHECK_CLOSE(FCClampBrightness(NAN),  0.0, 1e-9, @"NaN becomes 0");
}

void test_clamp_level_percent(void) {
    CHECK(FCClampLevelPercent(50, 140)   == 50,  "mid level passes through");
    CHECK(FCClampLevelPercent(-10, 140)  == 0,   "negative clamps to 0");
    CHECK(FCClampLevelPercent(200, 140)  == 140, "above max clamps to max");
    CHECK(FCClampLevelPercent(140, 140)  == 140, "max is inclusive");
    // A maxLevel below 100 must be raised: the ordinary slider range is always
    // available even on a panel that can grant no boost at all.
    CHECK(FCClampLevelPercent(100, 50)   == 100, "maxLevel<100 is raised to 100");
    CHECK(FCClampLevelPercent(130, 100)  == 100, "no boost -> capped at 100");
}

void test_apply_level_delta(void) {
    CHECK(FCApplyLevelDelta(50, 10, 140)   == 60,  "step up");
    CHECK(FCApplyLevelDelta(50, -10, 140)  == 40,  "step down");
    CHECK(FCApplyLevelDelta(135, 10, 140)  == 140, "saturates at the top rail");
    CHECK(FCApplyLevelDelta(3, -10, 140)   == 0,   "saturates at the bottom rail");
    CHECK(FCApplyLevelDelta(100, 5, 100)   == 100, "cannot exceed a 100 ceiling");
}

void test_brightness_step_percent(void) {
    CHECK(FCBrightnessStepPercent(0)   == 5,  "unset (0) defaults to 5");
    CHECK(FCBrightnessStepPercent(-3)  == 5,  "garbage negative defaults to 5");
    CHECK(FCBrightnessStepPercent(1)   == 1,  "1 is honoured");
    CHECK(FCBrightnessStepPercent(10)  == 10, "10 is honoured");
    CHECK(FCBrightnessStepPercent(99)  == 25, "above 25 clamps to 25");
}

// THE LOAD-BEARING TEST. The curve must rise with headroom and never fall
// below 1.0, and it must be genuinely headroom-dependent rather than a
// constant that happens to look right at one operating point.
void test_max_safe_factor_is_monotonic(void) {
    // No grant at all -> exactly 1.0, so the caller writes no gamma. This is
    // what makes the feature degrade silently on every non-XDR Mac.
    CHECK_CLOSE(FCMaxSafeFactorForHeadroom(1.0),  1.0, 1e-9, @"headroom 1.0 -> no boost");
    CHECK_CLOSE(FCMaxSafeFactorForHeadroom(0.5),  1.0, 1e-9, @"sub-unity headroom -> no boost");
    CHECK_CLOSE(FCMaxSafeFactorForHeadroom(NAN),  1.0, 1e-9, @"NaN headroom -> no boost");

    // Measured operating points on the target panel (Mac15,11), both taken
    // with the EDR grant SETTLED. 2.6667 is headroom at slider maximum —
    // exactly 1600/600, the panel's peak-to-SDR-white ratio. 6.1539 is where
    // it settles at a mid slider position. (An earlier draft used 2.0513 here,
    // a value sampled mid-ramp; see the correction in FCXDRBrightness.h.)
    double atRef  = FCMaxSafeFactorForHeadroom(2.6667);
    double atIdle = FCMaxSafeFactorForHeadroom(6.1539);
    CHECK(atRef > 1.0,  "some boost is available at the measured reference headroom");
    CHECK(atIdle > atRef, "more headroom yields a larger ceiling (monotonic increasing)");

    // Strict monotonicity across a sweep, and no discontinuity at 1.0.
    double prev = FCMaxSafeFactorForHeadroom(1.0);
    for (double h = 1.05; h <= 20.0; h += 0.25) {
        double f = FCMaxSafeFactorForHeadroom(h);
        CHECK(f >= prev - 1e-9, "curve never decreases as headroom grows (h=%.2f)", h);
        CHECK(f >= 1.0,         "curve never drops below 1.0 (h=%.2f)", h);
        CHECK(f <= kFCAbsoluteFactorCap + 1e-9,
              "curve never exceeds the absolute cap (h=%.2f, f=%.4f)", h, f);
        prev = f;
    }
    // The cap must actually bind somewhere in a plausible range, otherwise it
    // is decorative and a dimmed panel (which reports very high headroom)
    // would compute an absurd factor.
    CHECK_CLOSE(FCMaxSafeFactorForHeadroom(100.0), kFCAbsoluteFactorCap, 1e-9,
                @"absolute cap binds at extreme headroom");
}

void test_applied_factor_for_level(void) {
    // At or below 100 the macOS slider owns the range: no gamma is written.
    CHECK_CLOSE(FCAppliedFactorForLevel(0,   6.15), 1.0, 1e-9, @"level 0 -> factor 1.0");
    CHECK_CLOSE(FCAppliedFactorForLevel(50,  6.15), 1.0, 1e-9, @"level 50 -> factor 1.0");
    CHECK_CLOSE(FCAppliedFactorForLevel(100, 6.15), 1.0, 1e-9, @"level 100 -> factor 1.0");

    // Above 100, the request is honoured when headroom can support it.
    CHECK_CLOSE(FCAppliedFactorForLevel(120, 6.15), 1.20, 1e-9, @"level 120 -> factor 1.20");

    // ...and clamped when it cannot. Asking for more than the panel can give
    // must yield the panel's maximum, never a clipped ramp.
    double ceiling = FCMaxSafeFactorForHeadroom(1.5);
    CHECK_CLOSE(FCAppliedFactorForLevel(140, 1.5), ceiling, 1e-9,
                @"over-request clamps to the headroom ceiling");
    // With no headroom at all, even a level of 140 must write nothing.
    CHECK_CLOSE(FCAppliedFactorForLevel(140, 1.0), 1.0, 1e-9,
                @"no headroom -> factor 1.0 even at max level");
}

// The anti-compounding invariant. Re-capturing an already-boosted ramp as the
// new baseline squares the factor on every capture — measured at 1.2952 ->
// 1.6776 across a single sleep/wake cycle in an earlier draft, unbounded.
void test_gamma_baseline_neutrality_guard(void) {
    CHECK(FCGammaBaselineIsNeutral(1.0)   == YES, "an identity ramp is a valid baseline");
    CHECK(FCGammaBaselineIsNeutral(1.005) == YES, "tiny float drift is tolerated");
    CHECK(FCGammaBaselineIsNeutral(0.85)  == YES, "a dimmed ramp is still a valid baseline");
    CHECK(FCGammaBaselineIsNeutral(1.37)  == NO,  "an ALREADY-BOOSTED ramp is refused");
    CHECK(FCGammaBaselineIsNeutral(1.60)  == NO,  "a capped-boost ramp is refused");
    CHECK(FCGammaBaselineIsNeutral(NAN)   == NO,  "NaN is refused");
}

void test_decompose_level(void) {
    double slider = -1.0, factor = -1.0;

    FCDecomposeLevel(0, 6.15, &slider, &factor);
    CHECK_CLOSE(slider, 0.0, 1e-9, @"level 0 -> slider 0.0");
    CHECK_CLOSE(factor, 1.0, 1e-9, @"level 0 -> factor 1.0");

    FCDecomposeLevel(75, 6.15, &slider, &factor);
    CHECK_CLOSE(slider, 0.75, 1e-9, @"level 75 -> slider 0.75");
    CHECK_CLOSE(factor, 1.0,  1e-9, @"level 75 -> no gamma");

    // Above 100 the slider PINS at maximum and the extra comes from gamma:
    // "beyond maximum" only means anything once the maximum is actually in use.
    FCDecomposeLevel(130, 6.15, &slider, &factor);
    CHECK_CLOSE(slider, 1.0,  1e-9, @"level 130 -> slider pinned at 1.0");
    CHECK_CLOSE(factor, 1.30, 1e-9, @"level 130 -> factor 1.30");

    FCDecomposeLevel(100, 6.15, &slider, &factor);
    CHECK_CLOSE(slider, 1.0, 1e-9, @"level 100 -> slider 1.0");
    CHECK_CLOSE(factor, 1.0, 1e-9, @"level 100 is the hand-over point, still no gamma");

    // NULL out-parameters must be accepted — callers often want only one half.
    FCDecomposeLevel(120, 6.15, NULL, NULL);
}
