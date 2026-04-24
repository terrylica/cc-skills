// v4 iter-173: holiday-awareness MVP. Hardcoded 2026 NYSE closed-days
// list + lookup helper. Scope is deliberately narrow for this iter:
// data module + pure-function lookup only. Wiring into
// computeSessionState lands separately.
//
// Data source: NYSE 2026 holiday calendar (nyse.com/markets/hours-
// calendars). Full-closure days only; half-day / early-close handling
// deferred. Extension to more markets (TSE Shogatsu, LSE bank holidays,
// JSE public holidays, etc.) is straightforward — add a parallel
// array keyed by market id — when holiday awareness is wired into
// session-state promotion.
//
// Format: ISO-date strings (yyyy-MM-dd, zero-padded). Matching uses
// NSDateComponents in the market's IANA so a US holiday matches
// regardless of the user's local zone.
#import <Foundation/Foundation.h>
#import "MarketCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// Returns YES if the given date is a full-closure holiday for the
// given market. Currently only NYSE has hardcoded data — other markets
// always return NO until their data is added.
BOOL FCIsMarketHoliday(const ClockMarket * _Nullable mkt, NSDate * _Nullable date);

NS_ASSUME_NONNULL_END
