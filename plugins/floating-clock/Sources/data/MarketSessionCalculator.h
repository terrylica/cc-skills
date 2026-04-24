// Session-state engine for an exchange. Given a market (from MarketCatalog)
// and a moment in time, computes:
//   - SessionState (OPEN / LUNCH / CLOSED)
//   - progress 0.0–1.0 through the regular session (for progress bars)
//   - seconds to next transition (for countdown UI)
//
// Also houses the visual-rendering helpers that are tightly coupled to
// SessionState: glyph for state (●/◑/○), color for state, countdown
// formatting, and progress-bar string composition.
#import <Cocoa/Cocoa.h>
#import "MarketCatalog.h"
#import "ThemeCatalog.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
    kSessionOpen = 0,     // regular session (incl. pre-open auctions)
    kSessionLunch = 1,    // Asian-exchange midday break
    kSessionClosed = 2,   // overnight, weekend
} SessionState;

void computeSessionState(const ClockMarket *mkt, NSDate *now,
                         SessionState *outState,
                         double *outProgress01,
                         long *outSecsToNext);

// Human-readable countdown: "5s" / "47m" / "2h17m" / ">99h" placeholder.
NSString *formatCountdown(long secs);

// Fixed-length bar string. The glyph pair is selected by the
// NSUserDefaults key "ProgressBarStyle":
//   "blocks" (default) — █ / ▒
//   "dots"             — ● / ○
//   "dashes"           — ━ / ╌
//   "arrows"           — ▶ / ▷
//   "binary"           — █ / ░
//   "braille"          — ⣿ / ⣀
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
