// Session-state engine for an exchange. Given a market (from MarketCatalog)
// and a moment in time, computes:
//   - SessionState (OPEN / LUNCH / CLOSED / PRE-MARKET / AFTER-HOURS)
//   - progress 0.0–1.0 through the regular session (for progress bars)
//   - seconds to next transition (for countdown UI)
//
// Also houses the visual-rendering helpers that are tightly coupled to
// SessionState: glyph for state (●/◑/○/◐), color for state, countdown
// formatting, and progress-bar string composition.
#import <Cocoa/Cocoa.h>
#import "MarketCatalog.h"
#import "ThemeCatalog.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
    kSessionOpen = 0,       // regular session
    kSessionLunch = 1,      // Asian-exchange midday break
    kSessionClosed = 2,     // overnight, weekend
    kSessionPreMarket = 3,  // iter-123: final 15 min before today's open (not weekend)
    kSessionAfterHours = 4, // iter-125: first 15 min after today's close (not weekend)
} SessionState;

// v4 iter-77: shared time-unit constants. Previously '86400' and
// '99 * 3600' were inlined across Runtime.m, NextSegmentContentBuilder.m,
// and MarketSessionCalculator.m. Now named externs — single source of
// truth for day boundary + the bounded-countdown threshold.
extern const long kFCSecondsPerDay;           // 24 * 3600 = 86400
extern const long kFCMaxBoundedCountdownSecs; // 99 * 3600 — below this, countdowns render as T-HH:MM:SS or T-Nd Hh MMm; above, absolute-date form

void computeSessionState(const ClockMarket *mkt, NSDate *now,
                         SessionState *outState,
                         double *outProgress01,
                         long *outSecsToNext);

// Human-readable countdown: "5s" / "47m" / "2h17m" / ">99h" placeholder.
NSString *formatCountdown(long secs);

// Rocket-launch style countdown: "T-HH:MM:SS" zero-padded, always
// three-segment for visual consistency. Used by NEXT TO OPEN (iter-59)
// because the T- prefix is the universally recognized "counting down
// to an event" convention (NASA, SpaceX launch streams, etc.) and
// second-level granularity is critical as T-0 approaches.
//
// Examples: "T-02:34:17", "T-00:01:45", "T-00:00:07".
// For secs > 99h (over ~4 days), rendering falls back to formatCountdown
// since HH would be multi-digit and lose fixed-width alignment.
NSString *formatCountdownFancy(long secs);

// Fixed-length bar string. The glyph pair is selected by the
// NSUserDefaults key "ProgressBarStyle" (12 presets, iter-131):
//   "blocks"    — █ / ▒     "hearts"    — ♥ / ♡
//   "dots"      — ● / ○     "stars"     — ★ / ☆
//   "thindots"  — • / ·     "ribbon"    — ▰ / ▱
//   "dashes"    — ━ / ╌     "diamond"   — ◆ / ◇
//   "arrows"    — ▶ / ▷     "triangles" — ▲ / △
//   "binary"    — █ / ░     "braille"   — ⣿ / ⣀
// Default / unknown / nil → "dots".
NSString *buildProgressBar(double progress01, int totalCells);

// Return the number of "filled" cells for the given progress. Callers
// split color between [0..N) and [N..totalCells) — matches the split
// point regardless of which glyph pair the style picks.
int fcProgressBarFullCells(double progress01, int totalCells);

// Single-char state glyphs: ● / ◑ / ○.
NSString *glyphForState(SessionState s);

// Color bound to each SessionState. Theme parameter reserved for future
// per-theme override; currently ignored (fixed palette).
NSColor *colorForState(SessionState s, const ClockTheme * _Nullable theme);

NS_ASSUME_NONNULL_END
