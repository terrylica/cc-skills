// v4 iter-188: half-day session MVP (data-only, parallel to iter-173's
// HolidayCalendar). Hardcoded 2026 early-close days + their session-
// end times per market. Scope for this iter is narrow: data module +
// pure-function lookup only. Wiring into computeSessionState (so the
// session boundary actually uses the early close-time instead of the
// regular close) lands in a follow-up iter.
//
// Registry pattern: same shape as HolidayCalendar — per-market array,
// registry struct, fan-out by market id. Each entry is a (date, hour,
// minute) triple where hour+minute is the market-local early-close
// time (e.g. NYSE Black Friday 13:00 ET → {"2026-11-27", 13, 0}).
//
// Initial coverage: NYSE only (Day-after-Thanksgiving Black Friday +
// Christmas Eve, both 13:00 ET). Extension to LSE (12:30 Xmas Eve +
// NYE), XETRA/Euronext (14:00 Dec 24 + 14:00 Dec 31), TSE (大発会 /
// 大納会), HKEX (LNY Eve), B3 (Ash Wed), etc. is straightforward once
// the wiring iter lands.
//
// Dates matched as ISO strings (yyyy-MM-dd) in the market's IANA TZ so
// a US half-day matches regardless of user's local zone, identical
// matching semantics to FCIsMarketHoliday.
#import <Foundation/Foundation.h>
#import "MarketCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// Returns YES if the given date falls on a half-day session for the
// given market. When YES, outCloseHour + outCloseMinute are written
// with the early-close time (market-local hours/minutes, 24-hour).
// When NO or either pointer is nullable+unset, out-params are not
// touched. outCloseHour/outCloseMinute may be NULL — callers just
// probing "is today half-day?" don't need to know the time.
BOOL FCIsMarketHalfDay(const ClockMarket * _Nullable mkt,
                       NSDate * _Nullable date,
                       int * _Nullable outCloseHour,
                       int * _Nullable outCloseMinute);

NS_ASSUME_NONNULL_END
