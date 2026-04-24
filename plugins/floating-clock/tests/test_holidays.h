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
void test_holiday_calendar_hkex(void);
void test_holiday_calendar_target2(void);
void test_holiday_calendar_asx(void);
void test_holiday_calendar_tsx(void);
void test_holiday_calendar_six(void);
void test_holiday_calendar_sse(void);
void test_holiday_calendar_krx(void);
void test_nyse_holiday_state_closed(void);
void test_holiday_chains_through_weekend(void);

NS_ASSUME_NONNULL_END
