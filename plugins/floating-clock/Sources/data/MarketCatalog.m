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

const char *cityCodeForIana(const char *iana) {
    if (!iana || !*iana) return "LOC";
    if (strcmp(iana, "America/New_York") == 0) return "NYC";
    if (strcmp(iana, "America/Toronto") == 0)  return "TOR";
    if (strcmp(iana, "Europe/London") == 0)    return "LON";
    if (strcmp(iana, "Europe/Paris") == 0)     return "PAR";
    if (strcmp(iana, "Europe/Berlin") == 0)    return "FRA";
    if (strcmp(iana, "Europe/Zurich") == 0)    return "ZRH";
    if (strcmp(iana, "Asia/Tokyo") == 0)       return "TOK";
    if (strcmp(iana, "Asia/Hong_Kong") == 0)   return "HKG";
    if (strcmp(iana, "Asia/Shanghai") == 0)    return "SHA";
    if (strcmp(iana, "Asia/Seoul") == 0)       return "SEO";
    if (strcmp(iana, "Asia/Kolkata") == 0)     return "MUM";
    if (strcmp(iana, "Australia/Sydney") == 0) return "SYD";
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
