// v4 iter-126: dispatcher for the symmetric auction-window length that
// gates PRE-MARKET (iter-123) and AFTER-HOURS (iter-125) state promotions
// in computeSessionState.
//
// iter-123/125 hardcoded 15 minutes. Market norms vary — US equities have
// 4h extended sessions, LSE has 5-min auction bookends, TSE has 5/10-min
// opening/closing auctions. Rather than model each exchange individually
// (bundled per-market data that drifts), expose a single uniform window
// the user picks.
//
// Presets map to minutes:
//   "off"   → 0   disables both promotions (pure OPEN/CLOSED/LUNCH)
//   "5min"  → 5   matches LSE/TSE auction-call length
//   "15min" → 15  default — matches iter-123/125 original behavior
//   "30min" → 30  covers typical pre-open activity
//   "60min" → 60  covers morning-ramp for day-traders
//
// Unknown / nil / empty → 15 (default fallback).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSInteger FCSessionSignalWindowMinutes(NSString * _Nullable styleId);

NS_ASSUME_NONNULL_END
