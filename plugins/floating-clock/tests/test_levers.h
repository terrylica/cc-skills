// v4 iter-118: test harness split.
//
// test_session.m had grown to 994/1000 LoC — the file-size guard
// blocked the next test addition. Split here: the ~14 pref-lever /
// dispatcher unit tests moved to test_levers.m, while session-state,
// TZ-helper, flag/city, landing-time, and profile-coverage tests
// stay in test_session.m.
//
// Shared state is the `failures` counter — declared extern here,
// defined (non-static) in test_session.m. Both .m files increment
// the same storage so test_session's final tally reflects all
// failures across both files.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

// Lever-dispatcher + data-module invariant tests.
void test_font_weight_parser(void);
void test_segment_weight_fallback(void);
void test_segment_opacity_fallback(void);
void test_progress_bar_glyph_styles(void);
void test_theme_catalog_invariants(void);
void test_letter_spacing_parser(void);
void test_line_spacing_parser(void);
void test_date_format_prefix(void);
void test_corner_radius_points(void);
void test_density_pad_points(void);
void test_segment_gap_points(void);
void test_sky_glyph_phases(void);
void test_current_time_format(void);
void test_quick_styles_invariants(void);
void test_shadow_spec_catalog(void);
void test_session_signal_window(void);
void test_session_state_label(void);
void test_session_state_color(void);
void test_clipboard_header_format(void);
void test_urgency_color_tiers(void);

NS_ASSUME_NONNULL_END
