// v4 iter-193: test harness split #3.
//
// test_holidays.m was approaching 1000-LoC (982 after iter-192; iter-192
// was tightened specifically to stay under guard). Extract the 5 half-
// day fixtures to their own file so iter-193+ half-day campaign iters
// can grow without churning the file-size-guard.
//
// Half-day coverage to date (iter-188 → iter-192):
//   test_halfday_calendar_nyse              iter-188 — NYSE data MVP
//   test_nyse_halfday_state_closed          iter-189 — wiring integration
//   test_halfday_calendar_lse_and_target2   iter-190 — LSE + XETRA/Euronext
//   test_halfday_calendar_hkex_and_tsx      iter-191 — HKEX hasLunch=NO + TSX
//   test_halfday_calendar_jse_and_asx       iter-192 — JSE + ASX
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void test_halfday_calendar_nyse(void);
void test_halfday_calendar_lse_and_target2(void);
void test_halfday_calendar_hkex_and_tsx(void);
void test_halfday_calendar_jse_and_asx(void);
void test_nyse_halfday_state_closed(void);

NS_ASSUME_NONNULL_END
