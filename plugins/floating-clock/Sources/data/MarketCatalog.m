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

const char *flagForIana(const char *iana) {
    if (!iana || !*iana) return "";
    if (strcmp(iana, "America/New_York") == 0) return "\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8";  // 🇺🇸
    if (strcmp(iana, "America/Toronto") == 0)  return "\xF0\x9F\x87\xA8\xF0\x9F\x87\xA6";  // 🇨🇦
    if (strcmp(iana, "Europe/London") == 0)    return "\xF0\x9F\x87\xAC\xF0\x9F\x87\xA7";  // 🇬🇧
    if (strcmp(iana, "Europe/Paris") == 0)     return "\xF0\x9F\x87\xAB\xF0\x9F\x87\xB7";  // 🇫🇷
    if (strcmp(iana, "Europe/Berlin") == 0)    return "\xF0\x9F\x87\xA9\xF0\x9F\x87\xAA";  // 🇩🇪
    if (strcmp(iana, "Europe/Zurich") == 0)    return "\xF0\x9F\x87\xA8\xF0\x9F\x87\xAD";  // 🇨🇭
    if (strcmp(iana, "Asia/Tokyo") == 0)       return "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5";  // 🇯🇵
    if (strcmp(iana, "Asia/Hong_Kong") == 0)   return "\xF0\x9F\x87\xAD\xF0\x9F\x87\xB0";  // 🇭🇰
    if (strcmp(iana, "Asia/Shanghai") == 0)    return "\xF0\x9F\x87\xA8\xF0\x9F\x87\xB3";  // 🇨🇳
    if (strcmp(iana, "Asia/Seoul") == 0)       return "\xF0\x9F\x87\xB0\xF0\x9F\x87\xB7";  // 🇰🇷
    if (strcmp(iana, "Asia/Kolkata") == 0)     return "\xF0\x9F\x87\xAE\xF0\x9F\x87\xB3";  // 🇮🇳
    if (strcmp(iana, "Australia/Sydney") == 0) return "\xF0\x9F\x87\xA6\xF0\x9F\x87\xBA";  // 🇦🇺
    return "";
}

// Hand-curated DST-aware abbreviations for the 12 exchanges we support.
// macOS's NSTimeZone abbreviationForDate: returns "GMT+1/+2" instead of
// "BST/CEST" for many European zones on recent OS releases — so hardcode
// the regional forms traders actually recognize.
NSString *friendlyAbbrevForIana(const char *iana, NSDate *date) {
    if (!iana || !*iana || !date) {
        NSTimeZone *loc = [NSTimeZone localTimeZone];
        return [loc abbreviationForDate:date ?: [NSDate date]] ?: @"";
    }
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:iana]];
    BOOL dst = tz ? [tz isDaylightSavingTimeForDate:date] : NO;

    if (strcmp(iana, "America/New_York") == 0) return dst ? @"EDT" : @"EST";
    if (strcmp(iana, "America/Toronto") == 0)  return dst ? @"EDT" : @"EST";
    if (strcmp(iana, "Europe/London") == 0)    return dst ? @"BST" : @"GMT";
    if (strcmp(iana, "Europe/Paris") == 0)     return dst ? @"CEST" : @"CET";
    if (strcmp(iana, "Europe/Berlin") == 0)    return dst ? @"CEST" : @"CET";
    if (strcmp(iana, "Europe/Zurich") == 0)    return dst ? @"CEST" : @"CET";
    if (strcmp(iana, "Asia/Tokyo") == 0)       return @"JST";
    if (strcmp(iana, "Asia/Hong_Kong") == 0)   return @"HKT";
    if (strcmp(iana, "Asia/Shanghai") == 0)    return @"CST";
    if (strcmp(iana, "Asia/Seoul") == 0)       return @"KST";
    if (strcmp(iana, "Asia/Kolkata") == 0)     return @"IST";
    if (strcmp(iana, "Australia/Sydney") == 0) return dst ? @"AEDT" : @"AEST";

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
