// v4 iter-244: test-harness split. test_levers.m hit the 1000-LoC
// guard again (4th split — see iter-118 / iter-176 / iter-193 history).
// Extracted LOCAL-segment feature tests (week-progress bar +
// astronomy helpers) into this dedicated file. Future LOCAL-feature
// tests should land here too.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_week_fraction(void);            // iter-229 (moved from test_levers.m iter-244)
void test_phase_color_for_hour(void);     // iter-241 (moved from test_levers.m iter-244)
void test_moon_phase(void);               // iter-244

NS_ASSUME_NONNULL_END
