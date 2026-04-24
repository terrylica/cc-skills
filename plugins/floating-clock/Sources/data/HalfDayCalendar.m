#import "HalfDayCalendar.h"
#include <string.h>

// Entry in a per-market half-day array. Date stored as ISO string for
// easy byte-compare via isEqualToString; close time as separate h/m
// ints to avoid mutable NSDateComponents alloc on every lookup.
typedef struct {
    NSString * _Nonnull iso;
    int close_h;
    int close_m;
} FCHalfDayEntry;

// v4 iter-188: NYSE 2026 half-day sessions. Source: NYSE published
// early-close calendar. Both dates close at 13:00 ET (1:00 pm).
// Day-after-Thanksgiving ("Black Friday") Nov 27 2026, and Christmas
// Eve Dec 24 2026 Thursday.
static const FCHalfDayEntry kNYSE2026HalfDays[] = {
    { @"2026-11-27", 13, 0 },  // Day after Thanksgiving (Black Friday)
    { @"2026-12-24", 13, 0 },  // Christmas Eve
};

// v4 iter-190: LSE 2026 half-day sessions. Source: LSE published
// calendar. Both dates close at 12:30 London time.
static const FCHalfDayEntry kLSE2026HalfDays[] = {
    { @"2026-12-24", 12, 30 },  // Christmas Eve
    { @"2026-12-31", 12, 30 },  // New Year's Eve
};

// v4 iter-190: TARGET2-aligned exchanges (XETRA Frankfurt + Euronext
// Paris/Amsterdam/Brussels/Lisbon/Dublin). Both share the same two
// half-day closures identically in 2026: Dec 24 + Dec 31, both 14:00
// local. One shared array, two registry entries below — mirrors
// iter-179's full-holiday TARGET2 dedup pattern.
static const FCHalfDayEntry kTARGET2_2026HalfDays[] = {
    { @"2026-12-24", 14, 0 },  // Christmas Eve
    { @"2026-12-31", 14, 0 },  // New Year's Eve
};

// v4 iter-191: HKEX 2026 half-day sessions. Source: HKEX published
// trading calendar. All three dates close at 12:00 HKT (noon) —
// lunch start in HKEX's regular schedule, so "close at lunch start"
// is functionally equivalent to "morning-only session". iter-189's
// hasLunch=NO override is load-bearing here: without it, the
// 12:00-13:00 window would incorrectly promote to LUNCH state instead
// of CLOSED.
static const FCHalfDayEntry kHKEX2026HalfDays[] = {
    { @"2026-02-16", 12, 0 },  // LNY Eve (農曆新年除夕)
    { @"2026-12-24", 12, 0 },  // Christmas Eve
    { @"2026-12-31", 12, 0 },  // New Year's Eve
};

// v4 iter-191: TSX 2026 half-day sessions. Source: TMX Group.
// Only Dec 24 2026 (Christmas Eve) is a half-day at TSX; closes
// 13:00 ET. Dec 31 is a full trading day on TSX (unlike LSE).
static const FCHalfDayEntry kTSX2026HalfDays[] = {
    { @"2026-12-24", 13, 0 },  // Christmas Eve
};

// v4 iter-192: JSE 2026 half-day session. Source: JSE published
// calendar. Single half-day: Christmas Eve closes at 12:00 SAST.
// JSE does NOT have a NYE half-day; Dec 31 trades full session.
static const FCHalfDayEntry kJSE2026HalfDays[] = {
    { @"2026-12-24", 12, 0 },  // Christmas Eve
};

// v4 iter-192: ASX 2026 half-day session. Source: ASX published
// calendar. Single half-day: Christmas Eve closes at 14:10 AEDT
// (the pre-close auction extends slightly further; modelled as
// 14:10 which is the regular trading halt).
static const FCHalfDayEntry kASX2026HalfDays[] = {
    { @"2026-12-24", 14, 10 },  // Christmas Eve
};

typedef struct {
    const char *market_id;
    const FCHalfDayEntry * _Nonnull entries;
    size_t count;
} FCHalfDayTable;

static const FCHalfDayTable kHalfDayTables[] = {
    { "nyse",     kNYSE2026HalfDays,     sizeof(kNYSE2026HalfDays)     / sizeof(kNYSE2026HalfDays[0])     },
    { "lse",      kLSE2026HalfDays,      sizeof(kLSE2026HalfDays)      / sizeof(kLSE2026HalfDays[0])      },
    { "xetra",    kTARGET2_2026HalfDays, sizeof(kTARGET2_2026HalfDays) / sizeof(kTARGET2_2026HalfDays[0]) },
    { "euronext", kTARGET2_2026HalfDays, sizeof(kTARGET2_2026HalfDays) / sizeof(kTARGET2_2026HalfDays[0]) },
    { "hkex",     kHKEX2026HalfDays,     sizeof(kHKEX2026HalfDays)     / sizeof(kHKEX2026HalfDays[0])     },
    { "tsx",      kTSX2026HalfDays,      sizeof(kTSX2026HalfDays)      / sizeof(kTSX2026HalfDays[0])      },
    { "jse",      kJSE2026HalfDays,      sizeof(kJSE2026HalfDays)      / sizeof(kJSE2026HalfDays[0])      },
    { "asx",      kASX2026HalfDays,      sizeof(kASX2026HalfDays)      / sizeof(kASX2026HalfDays[0])      },
};
static const size_t kNumHalfDayTables = sizeof(kHalfDayTables) / sizeof(kHalfDayTables[0]);

BOOL FCIsMarketHalfDay(const ClockMarket *mkt,
                       NSDate *date,
                       int *outCloseHour,
                       int *outCloseMinute) {
    if (!mkt || !date) return NO;

    const FCHalfDayTable *tbl = NULL;
    for (size_t i = 0; i < kNumHalfDayTables; i++) {
        if (strcmp(mkt->id, kHalfDayTables[i].market_id) == 0) {
            tbl = &kHalfDayTables[i];
            break;
        }
    }
    if (!tbl) return NO;

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
    NSString *iso = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                     (long)c.year, (long)c.month, (long)c.day];
    for (size_t i = 0; i < tbl->count; i++) {
        if ([iso isEqualToString:tbl->entries[i].iso]) {
            if (outCloseHour)   *outCloseHour   = tbl->entries[i].close_h;
            if (outCloseMinute) *outCloseMinute = tbl->entries[i].close_m;
            return YES;
        }
    }
    return NO;
}
