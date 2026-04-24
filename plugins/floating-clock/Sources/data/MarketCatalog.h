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

// UTF-8 country-flag emoji for the exchange whose IANA zone is supplied.
// Returns empty string for IANA zones without a mapping (never crashes).
const char *flagForIana(const char * _Nullable iana);

// Friendly timezone abbreviation (e.g. BST, CEST, JST, EDT) for a given
// IANA zone and date — bypasses NSTimeZone's GMT+N fallback behavior on
// macOS and returns real regional forms. DST-aware for zones that observe
// it. Falls back to NSTimeZone's abbreviation when the zone is unknown.
NSString *friendlyAbbrevForIana(const char * _Nullable iana, NSDate *date);

// "UTC±H" or "UTC±H:MM" for the given IANA zone at the given date.
// Authoritative source: IANA tzdata shipped with macOS (updated via
// `softwareupdate` when tzdata revisions land). System clock itself is
// NTP-synced by macOS, so the date we pass in is already canonical.
// Returns empty string when the zone is unresolvable.
NSString *utcOffsetForIana(const char * _Nullable iana, NSDate *date);

// Compact label "ABBREV UTC±H" (or "UTC±H" when abbreviation is a bare
// numeric fallback). Use this as the one-stop renderer in display sites
// that previously showed only the abbreviation.
NSString *fullTzLabelForIana(const char * _Nullable iana, NSDate *date);

// Same as fullTzLabelForIana but for a specific NSTimeZone object (used
// by the local-time path where we have the zone directly, not an IANA
// c-string).
NSString *fullTzLabelForZone(NSTimeZone * _Nullable tz, NSDate *date);

NS_ASSUME_NONNULL_END
