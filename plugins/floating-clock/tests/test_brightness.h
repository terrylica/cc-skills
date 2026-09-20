// Brightness-rail arithmetic tests (2026-09-19).
//
// Covers DisplayBrightnessHelpers only — the Foundation-only half of the
// brightness feature. The engine (FCXDRBrightness) and the two AppKit views
// are excluded from the test link because they need Metal and a live display;
// keeping the arithmetic in its own Foundation-only module is what makes any
// of this testable at all.
//
// The regression that matters most here is test_max_safe_factor_is_monotonic.
// The response curve is CLEAN-ROOM — deliberately not BrightIntosh's, because
// that project is GPL-3.0 and this repo is MIT, and because its hardcoded
// referenceEDR of 2.66 for Mac15,11 does not match this machine's measured
// 2.0513. A curve that silently degenerates to a constant would still "work"
// on a casual look while over-driving the panel, so its shape is pinned.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_clamp_brightness(void);
void test_clamp_level_percent(void);
void test_apply_level_delta(void);
void test_brightness_step_percent(void);
void test_max_safe_factor_is_monotonic(void);
void test_applied_factor_for_level(void);
void test_gamma_baseline_neutrality_guard(void);
void test_decompose_level(void);

NS_ASSUME_NONNULL_END
