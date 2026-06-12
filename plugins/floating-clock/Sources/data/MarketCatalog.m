#import "MarketCatalog.h"
#include <string.h>
#include <ctype.h>

const ClockMarket kMarkets[] = {
    {"local",    "Local Time",                    "LOCAL", "",                      0,   0, 0,   0, -1, -1, -1, -1},
    {"nyse",     "NYSE/NASDAQ (New York)",        "NYSE",  "America/New_York",      9,  30, 16,  0, -1, -1, -1, -1},
    {"tsx",      "TSX (Toronto)",                 "TSX",   "America/Toronto",       9,  30, 16,  0, -1, -1, -1, -1},
    {"lse",      "LSE (London)",                  "LSE",   "Europe/London",         8,   0, 16, 30, -1, -1, -1, -1},
    {"euronext", "Euronext (Paris)",              "EUX",   "Europe/Paris",          9,   0, 17, 30, -1, -1, -1, -1},
    {"xetra",    "XETRA (Frankfurt)",             "XETR",  "Europe/Berlin",         9,   0, 17, 30, -1, -1, -1, -1},
    {"six",      "SIX (Zurich)",                  "SIX",   "Europe/Zurich",         9,   0, 17, 20, -1, -1, -1, -1},
    {"tse",      "TSE (Tokyo)",                   "TSE",   "Asia/Tokyo",            9,   0, 15, 30, 11, 30, 12, 30},
    {"hkex",     "HKEX (Hong Kong)",              "HKEX",  "Asia/Hong_Kong",        9,  30, 16,  0, 12,  0, 13,  0},
    {"sse",      "SSE (Shanghai)",                "SSE",   "Asia/Shanghai",         9,  30, 14, 57, 11, 30, 13,  0},
    {"krx",      "KRX (Seoul)",                   "KRX",   "Asia/Seoul",            9,   0, 15, 30, -1, -1, -1, -1},
    {"nse",      "NSE (Mumbai)",                  "NSE",   "Asia/Kolkata",          9,  15, 15, 30, -1, -1, -1, -1},
    {"asx",      "ASX (Sydney)",                  "ASX",   "Australia/Sydney",     10,   0, 16,  0, -1, -1, -1, -1},
    // v4 iter-155: fills the Africa regional gap.
    {"jse",      "JSE (Johannesburg)",            "JSE",   "Africa/Johannesburg",   9,   0, 17,  0, -1, -1, -1, -1},
    // v4 iter-161: fills the South America regional gap. B3 trades
    // 10:00-17:00 BRT year-round (Brazil abolished DST in 2019).
    {"b3",       "B3 (São Paulo)",                "B3",    "America/Sao_Paulo",    10,   0, 17,  0, -1, -1, -1, -1},
};
const size_t kNumMarkets = sizeof(kMarkets) / sizeof(kMarkets[0]);

const ClockMarket *marketForId(NSString *idStr) {
    if (!idStr) return &kMarkets[0];
    const char *c = idStr.UTF8String;
    for (size_t i = 0; i < kNumMarkets; i++) {
        if (strcmp(kMarkets[i].id, c) == 0) return &kMarkets[i];
    }
    return &kMarkets[0];
}

// ── IANA zone metadata table (DRY 2026-06-12) ──────────────────────────
// flagForIana / friendlyAbbrevForIana / cityCodeForIana each carried their
// own 14-branch strcmp chain over the SAME zones. One table row per zone is
// now the single source of truth — adding an exchange's zone is one line
// here instead of three edits. DST-aware abbreviations stay hand-curated
// because macOS returns "GMT+1/+2" instead of the regional forms traders
// recognize (see friendlyAbbrevForIana note below); abbrevDst == NULL means
// the zone observes no DST (or, like Brazil post-2019, abolished it).
typedef struct {
    const char *iana;
    const char *flag;       // UTF-8 flag emoji
    const char *abbrevStd;  // standard-time abbreviation
    const char *abbrevDst;  // daylight abbreviation, or NULL when no DST
    const char *cityCode;   // 3-letter trader code
} FCIanaZoneEntry;

static const FCIanaZoneEntry kIanaZones[] = {
    {"America/New_York",    "\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8", "EST",  "EDT",  "NYC"},
    {"America/Toronto",     "\xF0\x9F\x87\xA8\xF0\x9F\x87\xA6", "EST",  "EDT",  "TOR"},
    {"Europe/London",       "\xF0\x9F\x87\xAC\xF0\x9F\x87\xA7", "GMT",  "BST",  "LON"},
    {"Europe/Paris",        "\xF0\x9F\x87\xAB\xF0\x9F\x87\xB7", "CET",  "CEST", "PAR"},
    {"Europe/Berlin",       "\xF0\x9F\x87\xA9\xF0\x9F\x87\xAA", "CET",  "CEST", "FRA"},
    {"Europe/Zurich",       "\xF0\x9F\x87\xA8\xF0\x9F\x87\xAD", "CET",  "CEST", "ZRH"},
    {"Asia/Tokyo",          "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5", "JST",  NULL,   "TOK"},
    {"Asia/Hong_Kong",      "\xF0\x9F\x87\xAD\xF0\x9F\x87\xB0", "HKT",  NULL,   "HKG"},
    {"Asia/Shanghai",       "\xF0\x9F\x87\xA8\xF0\x9F\x87\xB3", "CST",  NULL,   "SHA"},
    {"Asia/Seoul",          "\xF0\x9F\x87\xB0\xF0\x9F\x87\xB7", "KST",  NULL,   "SEO"},
    {"Asia/Kolkata",        "\xF0\x9F\x87\xAE\xF0\x9F\x87\xB3", "IST",  NULL,   "MUM"},
    {"Australia/Sydney",    "\xF0\x9F\x87\xA6\xF0\x9F\x87\xBA", "AEST", "AEDT", "SYD"},
    {"Africa/Johannesburg", "\xF0\x9F\x87\xBF\xF0\x9F\x87\xA6", "SAST", NULL,   "JHB"},  // iter-155: no DST
    {"America/Sao_Paulo",   "\xF0\x9F\x87\xA7\xF0\x9F\x87\xB7", "BRT",  NULL,   "SAO"},  // iter-161: DST abolished 2019
};
static const size_t kNumIanaZones = sizeof(kIanaZones) / sizeof(kIanaZones[0]);

static const FCIanaZoneEntry *fcFindIanaZone(const char *iana) {
    if (!iana || !*iana) return NULL;
    for (size_t i = 0; i < kNumIanaZones; i++) {
        if (strcmp(kIanaZones[i].iana, iana) == 0) return &kIanaZones[i];
    }
    return NULL;
}

const char *flagForIana(const char *iana) {
    const FCIanaZoneEntry *e = fcFindIanaZone(iana);
    return e ? e->flag : "";
}

// Hand-curated DST-aware abbreviations for the exchanges we support.
// macOS's NSTimeZone abbreviationForDate: returns "GMT+1/+2" instead of
// "BST/CEST" for many European zones on recent OS releases — so the table
// hardcodes the regional forms traders actually recognize.
NSString *friendlyAbbrevForIana(const char *iana, NSDate *date) {
    if (!iana || !*iana || !date) {
        NSTimeZone *loc = [NSTimeZone localTimeZone];
        return [loc abbreviationForDate:date ?: [NSDate date]] ?: @"";
    }
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:iana]];
    const FCIanaZoneEntry *e = fcFindIanaZone(iana);
    if (e) {
        BOOL dst = tz ? [tz isDaylightSavingTimeForDate:date] : NO;
        return [NSString stringWithUTF8String:(dst && e->abbrevDst) ? e->abbrevDst
                                                                    : e->abbrevStd];
    }
    return tz ? ([tz abbreviationForDate:date] ?: @"") : @"";
}

NSString *utcOffsetForIana(const char *iana, NSDate *date) {
    if (!date) return @"";
    NSTimeZone *tz = nil;
    if (iana && *iana) {
        tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:iana]];
    }
    if (!tz) tz = [NSTimeZone localTimeZone];
    NSInteger secs = [tz secondsFromGMTForDate:date];
    char sign = (secs < 0) ? '-' : '+';
    NSInteger a = labs((long)secs);
    NSInteger h = a / 3600;
    NSInteger m = (a % 3600) / 60;
    if (m == 0) return [NSString stringWithFormat:@"UTC%c%ld", sign, (long)h];
    return [NSString stringWithFormat:@"UTC%c%ld:%02ld", sign, (long)h, (long)m];
}

NSString *fullTzLabelForIana(const char *iana, NSDate *date) {
    if (!date) return @"";
    NSString *abbrev = friendlyAbbrevForIana(iana, date);
    NSString *offset = utcOffsetForIana(iana, date);
    // Avoid redundancy when the abbreviation is itself a numeric fallback
    // like "+09" (macOS returns these for some zones without CLDR data).
    if (abbrev.length == 0 || [abbrev hasPrefix:@"+"] || [abbrev hasPrefix:@"-"]
        || [abbrev hasPrefix:@"GMT"]) {
        return offset;
    }
    return [NSString stringWithFormat:@"%@ %@", abbrev, offset];
}

NSString *fullTzLabelForZone(NSTimeZone *tz, NSDate *date) {
    if (!tz || !date) return @"";
    const char *ianaCStr = tz.name.UTF8String;
    return fullTzLabelForIana(ianaCStr, date);
}

const char *cityCodeForIana(const char *iana) {
    if (!iana || !*iana) return "LOC";
    const FCIanaZoneEntry *e = fcFindIanaZone(iana);
    if (e) return e->cityCode;
    // Fallback: first 3 chars of the city portion of IANA, uppercased.
    static char fallback[4];
    const char *slash = strrchr(iana, '/');
    if (slash && strlen(slash + 1) >= 3) {
        fallback[0] = (char)toupper((unsigned char)slash[1]);
        fallback[1] = (char)toupper((unsigned char)slash[2]);
        fallback[2] = (char)toupper((unsigned char)slash[3]);
        fallback[3] = 0;
        return fallback;
    }
    return "???";
}
