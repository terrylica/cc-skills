// v4 iter-176: test harness split #2.
//
// test_session.m hit the 1000-LoC file-size-guard threshold again
// (first split was iter-118 → test_levers.m for pref-lever tests).
// This round extracts holiday-calendar fixtures to their own file —
// they're a thematic cluster that will grow further as we add more
// exchange calendars (TSE this iter, JSE/ASX/KRX/NSE next, etc.).
// Shared `failures` counter lives in test_session.m (declared extern
// via test_levers.h).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Holiday-calendar + state-integration tests.
void test_holiday_calendar_nyse(void);
void test_holiday_calendar_lse(void);
void test_holiday_calendar_tse(void);
void test_nyse_holiday_state_closed(void);

NS_ASSUME_NONNULL_END
