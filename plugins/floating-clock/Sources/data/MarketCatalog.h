// Market/exchange catalog. 13 entries: index 0 is "local" (sentinel),
// indices 1..12 are the 12 major exchanges with IANA timezones and
// regular-session open/close + optional lunch window.
//
// marketForId() does a linear scan; returns &kMarkets[0] (local) as
// fallback. cityCodeForIana() maps IANA zones to 3-letter display codes
// used in ACTIVE segment headers.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    const char *id;                   // NSUserDefaults value, e.g. "nyse"
    const char *display;              // Menu label, e.g. "NYSE/NASDAQ (New York)"
    const char *code;                 // Short code for status line, e.g. "NYSE"
    const char *iana;                 // IANA timezone, e.g. "America/New_York"
    int open_h, open_m;               // Regular session open in local time
    int close_h, close_m;             // Regular session close
    int lunch_start_h, lunch_start_m; // -1, -1 if no lunch break
    int lunch_end_h, lunch_end_m;     // -1, -1 if no lunch break
} ClockMarket;

extern const ClockMarket kMarkets[];
extern const size_t kNumMarkets;

const ClockMarket *marketForId(NSString * _Nullable idStr);
const char *cityCodeForIana(const char * _Nullable iana);

NS_ASSUME_NONNULL_END
