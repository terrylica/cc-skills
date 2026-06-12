// Shared test utilities — DRY extraction 2026-06-12.
//
// Three fixtures (test_session, test_holidays, test_halfdays) carried
// verbatim copies of the date-construction helper, the SessionState
// name renderer, and the state-assertion macro. This header is the
// single source of truth for all three; the numeric assertion macros
// (secs/progress) live here too so future fixture splits inherit the
// full kit by including ONE header.
//
// `static inline` keeps each translation unit self-contained (no extra
// .m in TEST_SOURCES, no linker coordination).
#ifndef TEST_HELPERS_H
#define TEST_HELPERS_H

#import <Foundation/Foundation.h>
#import "../Sources/data/MarketSessionCalculator.h"

// Shared failure counter — defined in test_session.m.
extern int failures;

// Build an NSDate from civil components in the given IANA timezone.
static inline NSDate *dateAt(NSString *iana, int y, int m, int d, int h, int mm, int ss) {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:iana];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = y; c.month = m; c.day = d;
    c.hour = h; c.minute = mm; c.second = ss;
    return [cal dateFromComponents:c];
}

// Human-readable SessionState (single switch — adding an enum case here
// updates every fixture's failure messages at once).
static inline const char *sessionStateName(SessionState s) {
    switch (s) {
        case kSessionOpen:       return "OPEN";
        case kSessionLunch:      return "LUNCH";
        case kSessionClosed:     return "CLOSED";
        case kSessionPreMarket:  return "PRE-MARKET";
        case kSessionAfterHours: return "AFTER-HOURS";
    }
    return "?";
}

// Header annotates out-params as nonnull even though the implementation
// guards each write — throwaway locals satisfy the annotation.
#define ASSERT_SESSION_STATE(mkt, date, expected)                                \
    do {                                                                         \
        SessionState s; double _p; long _n;                                      \
        computeSessionState((mkt), (date), &s, &_p, &_n);                        \
        if (s != (expected)) {                                                   \
            fprintf(stderr, "FAIL %s: state expected %s got %s\n",               \
                    __func__, sessionStateName(expected), sessionStateName(s));  \
            failures++;                                                          \
        }                                                                        \
    } while (0)

#define ASSERT_SECS_NEAR(mkt, date, expected, tolerance)                         \
    do {                                                                         \
        SessionState _s; double _p; long actual;                                 \
        computeSessionState((mkt), (date), &_s, &_p, &actual);                   \
        long diff = actual > (expected) ? actual - (expected) : (expected) - actual; \
        if (diff > (tolerance)) {                                                \
            fprintf(stderr, "FAIL %s: secsToNext expected ~%ld got %ld (diff %ld)\n", \
                    __func__, (long)(expected), actual, diff);                   \
            failures++;                                                          \
        }                                                                        \
    } while (0)

#define ASSERT_PROGRESS_NEAR(mkt, date, expected, tolerance)                     \
    do {                                                                         \
        SessionState _s; double actual; long _n;                                 \
        computeSessionState((mkt), (date), &_s, &actual, &_n);                   \
        double diff = actual > (expected) ? actual - (expected) : (expected) - actual; \
        if (diff > (tolerance)) {                                                \
            fprintf(stderr, "FAIL %s: progress expected ~%.3f got %.3f (diff %.3f)\n", \
                    __func__, (double)(expected), actual, diff);                 \
        failures++;                                                              \
        }                                                                        \
    } while (0)

#endif // TEST_HELPERS_H
