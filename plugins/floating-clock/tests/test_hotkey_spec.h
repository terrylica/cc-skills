// HotKeySpec parser/formatter tests (2026-10-10). Covers the Foundation half of
// the whole-clock hide toggle; the Carbon registration in ClockVisibilityToggle
// is AppKit-bound and excluded from the test link. What matters most: the
// shipped default parses to the intended chord, and every malformed spec is
// REJECTED (a bad defaults value must mean "no hotkey", never a wrong one).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int failures;  // defined in test_session.m

void test_hotkey_spec_default_chord(void);
void test_hotkey_spec_aliases_and_case(void);
void test_hotkey_spec_rejects_malformed(void);
void test_hotkey_spec_display(void);

NS_ASSUME_NONNULL_END
