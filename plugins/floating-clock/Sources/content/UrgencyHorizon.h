// v4 iter-215: dispatcher for the imminence-gradient horizon used by
// FCUrgencyContinuousColor (iter-212). Below the horizon the gradient
// runs green→red on a Weber-Fechner log scale; above it the caller's
// theme color passes through untouched.
//
// iter-212 hardcoded the horizon at 60 minutes (kFCUrgencyHorizonSecs).
// Day-traders watching the closing bell want a much shorter horizon
// (e.g. 5 min — only the final stretch glows red); macro-watchers
// monitoring overnight gaps want a longer one (e.g. 240 min — the
// gradient builds slowly across an evening). Rather than pick one
// global default, expose presets the user picks from a menu.
//
// Pattern matches iter-126's SessionSignalWindow lever — preset id
// (NSString) → minutes (NSInteger), tested via fixture, default
// fallback returns 60 min so unset/empty/unknown matches iter-212's
// pre-existing behavior.
//
// Presets map to minutes:
//   "5min"   →   5   day-trader closing-bell focus
//   "15min"  →  15   short auction-window scope
//   "30min"  →  30   half-hour ramp
//   "60min"  →  60   default — matches iter-212 original
//   "120min" → 120   pre-market warm-up window
//   "240min" → 240   macro-watcher overnight scope
//
// Unknown / nil / empty → 60 (default fallback, preserves iter-212
// behavior for installs that never set the pref).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSInteger FCUrgencyHorizonMinutes(NSString * _Nullable presetId);

// Convenience: read pref from NSUserDefaults @"UrgencyHorizon", convert
// to seconds. Used by FCUrgencyContinuousColor at runtime so a single
// `defaults write` (or menu pick) re-tunes both ACTIVE + NEXT
// instantly. Falls back to kFCUrgencyHorizonSecs when the pref is
// unset/empty/unknown — preserves iter-212 default behavior.
long FCUrgencyHorizonSecsCurrent(void);

NS_ASSUME_NONNULL_END
