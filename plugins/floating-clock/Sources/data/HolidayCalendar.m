#import "HolidayCalendar.h"
#include <string.h>

// NYSE 2026 full-closure days. Source: NYSE public holiday calendar.
// Does NOT include half-days (deferred — those render as open until
// early-close handling lands).
static NSString * const kNYSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-01-19",  // Martin Luther King Jr. Day
    @"2026-02-16",  // Presidents' Day
    @"2026-04-03",  // Good Friday
    @"2026-05-25",  // Memorial Day
    @"2026-06-19",  // Juneteenth
    @"2026-07-03",  // Independence Day (observed; Jul 4 falls Saturday)
    @"2026-09-07",  // Labor Day
    @"2026-11-26",  // Thanksgiving
    @"2026-12-25",  // Christmas
};

// v4 iter-175: LSE 2026 bank holidays. Source:
// https://www.londonstockexchange.com/equities-trading/business-days
// Full-day closures only; half-days (Christmas Eve, New Year's Eve)
// deferred to early-close handling.
static NSString * const kLSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-05-04",  // Early May bank holiday
    @"2026-05-25",  // Spring bank holiday
    @"2026-08-31",  // Summer bank holiday
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // Boxing Day (observed; Dec 26 is Saturday)
};

// v4 iter-176: TSE 2026 non-trading days. Source: JPX (Japan Exchange
// Group) official calendar. Excludes weekend-coincident holidays
// (Jan 3 Sat Bank Holiday, May 3 Sun Constitution Memorial Day) — the
// isWeekend branch in computeSessionState already handles those.
// May 6 is a furikae-kyujitsu (substitute holiday) because May 3 fell
// on Sunday. Half-days (大発会 / 大納会 shortened sessions) deferred.
static NSString * const kTSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day (元日)
    @"2026-01-02",  // Bank holiday (銀行休業日)
    @"2026-01-12",  // Coming of Age Day (成人の日 — 2nd Mon of Jan)
    @"2026-02-11",  // National Foundation Day (建国記念の日)
    @"2026-02-23",  // Emperor's Birthday (天皇誕生日)
    @"2026-03-20",  // Vernal Equinox Day (春分の日)
    @"2026-04-29",  // Showa Day (昭和の日)
    @"2026-05-04",  // Greenery Day (みどりの日)
    @"2026-05-05",  // Children's Day (こどもの日)
    @"2026-05-06",  // Substitute holiday for May 3 (振替休日)
    @"2026-07-20",  // Marine Day (海の日 — 3rd Mon of Jul)
    @"2026-08-11",  // Mountain Day (山の日)
    @"2026-09-21",  // Respect for the Aged Day (敬老の日 — 3rd Mon of Sep)
    @"2026-09-23",  // Autumnal Equinox Day (秋分の日)
    @"2026-10-12",  // Sports Day (スポーツの日 — 2nd Mon of Oct)
    @"2026-11-03",  // Culture Day (文化の日)
    @"2026-11-23",  // Labor Thanksgiving Day (勤労感謝の日)
    @"2026-12-31",  // Year-end non-trading day (大納会 was Dec 30)
};

// v4 iter-178: HKEX 2026 non-trading days. Source: HKEX published
// calendar. First calendar to feature lunar-calendar holidays
// (Lunar New Year 3-day cluster, Buddha's Birthday, Dragon Boat,
// Mid-Autumn, Chung Yeung) whose Gregorian dates shift year-by-year
// — this fixture-locks the 2026 mapping. Good Friday + Easter Monday
// coincide with Ching Ming Festival 2026-04-05 Sun → observed Mon
// (combined into one day off). Half-day trading sessions (e.g. LNY
// Eve 2026-02-16 Mon) render as full sessions — half-day handling
// deferred.
static NSString * const kHKEX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-02-17",  // Lunar New Year Day 1 (農曆新年初一)
    @"2026-02-18",  // Lunar New Year Day 2 (初二)
    @"2026-02-19",  // Lunar New Year Day 3 (初三)
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday / Ching Ming observed (coincident)
    @"2026-05-01",  // Labour Day
    @"2026-05-25",  // Buddha's Birthday observed (lunar Apr 8 = Sun May 24)
    @"2026-06-19",  // Dragon Boat Festival (端午節)
    @"2026-07-01",  // HKSAR Establishment Day
    @"2026-09-25",  // Mid-Autumn Festival (中秋節)
    @"2026-10-01",  // National Day (國慶日)
    @"2026-10-19",  // Chung Yeung Festival (重陽節)
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // 1st weekday after Christmas (Boxing Day observed; Dec 26 Sat)
};

// v4 iter-179: TARGET2-aligned exchanges (XETRA Frankfurt + Euronext
// Paris/Amsterdam/Brussels/Lisbon/Dublin). Both use the same 5-date
// TARGET2 settlement-calendar closures in 2026. One shared array,
// two registry entries below — no data duplication. Dec 26 Boxing
// Day falls Saturday 2026 so weekend handling covers it (skip here).
// Half-day sessions (Dec 24 Christmas Eve + Dec 31 NYE shortened
// trading) render as full days, consistent with other markets.
static NSString * const kTARGET2_2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-05-01",  // Labour Day
    @"2026-12-25",  // Christmas Day
};

// v4 iter-180: ASX 2026 non-trading days. Source: ASX published
// calendar. Distinctive: **Easter Tuesday** — ASX is one of the few
// major exchanges that closes the Tuesday after Easter Mon (4-day
// Easter long weekend for Australia). ANZAC Day Apr 25 2026 falls on
// Saturday — ASX does not observe a Monday substitute when ANZAC is
// on weekend (weekend branch handles the closure). King's Birthday is
// the 2nd Monday of June for NSW / VIC / ACT (where ASX operates).
static NSString * const kASX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-01-26",  // Australia Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-04-07",  // Easter Tuesday (ASX-distinctive)
    @"2026-06-08",  // King's Birthday (2nd Mon of Jun)
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // Boxing Day observed (Dec 26 Sat)
};

// v4 iter-181: TSX 2026 non-trading days. Source: TMX Group published
// calendar. Notable differences from NYSE: (1) TSX observes Good
// Friday but NOT Easter Monday (trades Easter Mon); (2) Family Day
// (Ontario, 3rd Mon of Feb) aligns with US Presidents' Day same date
// in 2026 but semantically different; (3) Canadian Thanksgiving is
// 2nd Mon of Oct (Oct 12 2026), not 4th Thu of Nov; (4) Civic Holiday
// (1st Mon of Aug = Aug 3) has no US parallel; (5) Victoria Day (Mon
// on/before May 24 = May 18 2026) has no US parallel.
static NSString * const kTSX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-02-16",  // Family Day (3rd Mon of Feb, Ontario)
    @"2026-04-03",  // Good Friday
    @"2026-05-18",  // Victoria Day (Mon on/before May 24)
    @"2026-07-01",  // Canada Day
    @"2026-08-03",  // Civic Holiday (1st Mon of Aug)
    @"2026-09-07",  // Labour Day (1st Mon of Sep — coincides with US)
    @"2026-10-12",  // Canadian Thanksgiving (2nd Mon of Oct)
    @"2026-12-25",  // Christmas Day
    @"2026-12-28",  // Boxing Day observed (Dec 26 Sat)
};

// v4 iter-182: SIX Swiss Exchange 2026 non-trading days. Source: SIX
// published calendar. Distinctive: (1) Berchtold's Day Jan 2 — Swiss-
// specific second New Year; (2) Ascension Day (40 days after Easter
// Sunday = May 14 2026) + Whit Monday / Pfingstmontag (50 days after
// Easter = May 25 2026) — Christian holidays most non-European
// markets don't observe; (3) **Dec 24 + Dec 31 are FULL closures**
// at SIX, not half-day sessions like NYSE/LSE — one of the few
// exchanges where these are hard closures; (4) Aug 1 Swiss National
// Day falls Saturday 2026 (weekend handles). No substitute; SIX does
// not shift weekend-coincident holidays to weekdays.
static NSString * const kSIX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-01-02",  // Berchtold's Day (Berchtoldstag)
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Easter Monday
    @"2026-05-01",  // Labour Day
    @"2026-05-14",  // Ascension Day (Auffahrt)
    @"2026-05-25",  // Whit Monday (Pfingstmontag)
    @"2026-12-24",  // Christmas Eve (FULL closure at SIX)
    @"2026-12-25",  // Christmas Day
    @"2026-12-31",  // New Year's Eve (FULL closure at SIX)
};

// v4 iter-183: SSE (Shanghai Stock Exchange) 2026 non-trading days.
// Source: State Council-announced 2026 holiday schedule. Most complex
// calendar to date — features two 7-day "Golden Week" clusters that
// merge adjacent weekends with multi-day statutory holidays. Spring
// Festival Golden Week spans Feb 17-23 (Feb 21-22 weekend + Feb 17-20
// + Feb 23 Mon make-up). National Day Golden Week spans Oct 1-7
// (Oct 3-4 weekend + Oct 1-2 + Oct 5-7). Dragon Boat + Mid-Autumn are
// single-day closures (when not adjacent to a weekend).
//
// Not modelled: China's unique "make-up trading Saturdays"
// (补班) — working Saturdays are sometimes designated to compensate
// for extended Golden Week closures. These days SSE trades despite
// being Saturday; the current weekend branch in computeSessionState
// will incorrectly show SSE as CLOSED. Documented as a caveat.
static NSString * const kSSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    // Spring Festival Golden Week (Feb 17-23, 7 days incl. weekend)
    @"2026-02-17",  // Spring Festival Day 1 (春节)
    @"2026-02-18",  // Spring Festival Day 2
    @"2026-02-19",  // Spring Festival Day 3
    @"2026-02-20",  // Spring Festival Day 4
    @"2026-02-23",  // Spring Festival Day 5 (Mon, make-up for weekend)
    @"2026-04-06",  // Qingming / Tomb-Sweeping observed (Apr 5 Sun)
    // Labour Day cluster (Apr 30 working, May 1-5 non-trading)
    @"2026-05-01",  // Labour Day
    @"2026-05-04",  // Labour Day observed (post-weekend Mon)
    @"2026-05-05",  // Labour Day observed
    @"2026-06-19",  // Dragon Boat Festival (端午节, same day as HKEX)
    @"2026-09-25",  // Mid-Autumn Festival (中秋节, same day as HKEX)
    // National Day Golden Week (Oct 1-7, 7 days incl. weekend)
    @"2026-10-01",  // National Day Day 1 (国庆)
    @"2026-10-02",  // National Day Day 2
    @"2026-10-05",  // National Day Day 3
    @"2026-10-06",  // National Day Day 4
    @"2026-10-07",  // National Day Day 5
};

// v4 iter-184: KRX (Korea Exchange) 2026 non-trading days. Source:
// KRX published calendar + Korean substitute-holiday law (if a public
// holiday falls on Sat/Sun, next working day becomes a substitute
// for specified holidays: Seollal, Chuseok, Children's Day, National
// Foundation Day, Independence Movement Day, Liberation Day, Hangeul
// Day). KRX also closes Dec 31 as a year-end ceremony day (폐장일).
// Notable lunar-date overlaps: Chuseok Day 2 (Sep 25) shares
// Gregorian with HKEX Mid-Autumn and SSE Mid-Autumn.
static NSString * const kKRX2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    // Seollal Lunar New Year 3-day cluster (KRX closes eve + 2 days).
    @"2026-02-16",  // Seollal Eve (설날 전날)
    @"2026-02-17",  // Seollal Day 1 (설날)
    @"2026-02-18",  // Seollal Day 2 (설날 다음 날)
    @"2026-03-02",  // Independence Movement Day substitute (Mar 1 Sun)
    @"2026-05-05",  // Children's Day (어린이날)
    @"2026-05-25",  // Buddha's Birthday observed (lunar 4/8 = Sun May 24)
    @"2026-08-17",  // Liberation Day substitute (Aug 15 Sat)
    // Chuseok 3-day cluster (lunar 8/14, 8/15, 8/16 = Sep 24/25/26 2026).
    @"2026-09-24",  // Chuseok Day 1 (추석 전날)
    @"2026-09-25",  // Chuseok Day 2 (추석, same day as HKEX/SSE Mid-Autumn)
    @"2026-09-28",  // Chuseok substitute (Sep 26 Sat — Chuseok Day 3 fell weekend)
    @"2026-10-05",  // National Foundation Day substitute (Oct 3 Sat)
    @"2026-10-09",  // Hangeul Day (한글날)
    @"2026-12-25",  // Christmas Day
    @"2026-12-31",  // Year-end closure (폐장일)
};

// v4 iter-185: NSE (National Stock Exchange of India) 2026 trading
// holidays. Source: NSE published trading calendar (best-effort for
// 2026). India's calendar is the most diverse — mixes Gregorian civic
// dates with Hindu / Muslim / Sikh / Jain / Christian lunar-calc
// holidays. Dates marked "(approximate)" derive from astronomical
// computation and may shift by 1 day if NSE's official publication
// differs — fixture-lock these and refresh when NSE posts 2026
// calendar. NSE does NOT operate a substitute-holiday rule — when
// Independence Day (Aug 15) falls on weekend, no Mon substitute.
static NSString * const kNSE2026Holidays[] = {
    @"2026-01-26",  // Republic Day (Gregorian-fixed)
    @"2026-03-03",  // Holi / Dhuleti (approximate — lunar Phalgun)
    @"2026-04-02",  // Ram Navami (approximate — lunar Chaitra shukla 9)
    @"2026-04-03",  // Good Friday
    @"2026-04-10",  // Mahavir Jayanti (approximate)
    @"2026-05-01",  // Maharashtra Day (state-fixed)
    @"2026-06-26",  // Bakri Id / Eid ul-Adha (approximate — Islamic)
    @"2026-08-26",  // Ganesh Chaturthi (approximate — lunar Bhadrapada)
    @"2026-10-02",  // Gandhi Jayanti (Gregorian-fixed)
    @"2026-10-20",  // Dussehra / Vijaya Dashami (approximate)
    @"2026-11-09",  // Diwali / Laxmi Pujan (approximate)
    @"2026-11-10",  // Govardhan Puja / Diwali Balipratipada (approximate)
    @"2026-11-25",  // Guru Nanak Jayanti (approximate — lunar Kartik)
    @"2026-12-25",  // Christmas Day
};

// v4 iter-186: JSE (Johannesburg Stock Exchange) 2026 non-trading
// days. Source: JSE published calendar + South African Public
// Holidays Act (substitute rule: if on Sunday, next Monday becomes
// a public holiday; Saturday has no substitute). 2026 weekend-
// shifted: Aug 10 Mon (Women's Day Aug 9 Sun). Human Rights Day
// Mar 21 and Day of Goodwill Dec 26 fall Saturday — no substitute,
// weekend branch handles. Notable: South Africa calls Easter Monday
// "Family Day" (same date, different name).
static NSString * const kJSE2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-04-03",  // Good Friday
    @"2026-04-06",  // Family Day (Easter Monday in SA)
    @"2026-04-27",  // Freedom Day
    @"2026-05-01",  // Workers' Day
    @"2026-06-16",  // Youth Day
    @"2026-08-10",  // National Women's Day substitute (Aug 9 Sun)
    @"2026-09-24",  // Heritage Day
    @"2026-12-16",  // Day of Reconciliation
    @"2026-12-25",  // Christmas Day
};

// v4 iter-186: B3 (Brasil Bolsa Balcão) 2026 non-trading days.
// Source: B3 published calendar. Distinctive: Carnival Monday +
// Tuesday (Feb 16-17 2026) — Brazilian equity markets close for
// the 2-day Carnival peak. Corpus Christi (60 days after Easter
// Sunday = Jun 4 2026) — Christian moveable feast. National Black
// Awareness Day (Nov 20) was legislated federal in 2024. Ash Wed
// half-day session (Feb 18) not modelled — half-day caveat.
// Proclamation Day (Nov 15 2026 Sun) has no substitute.
static NSString * const kB3_2026Holidays[] = {
    @"2026-01-01",  // New Year's Day
    @"2026-02-16",  // Carnival Monday (Segunda-feira de Carnaval)
    @"2026-02-17",  // Carnival Tuesday (Terça-feira de Carnaval)
    @"2026-04-03",  // Good Friday
    @"2026-04-21",  // Tiradentes Day
    @"2026-05-01",  // Labour Day
    @"2026-06-04",  // Corpus Christi (Easter + 60d)
    @"2026-09-07",  // Independence Day (Dia da Independência)
    @"2026-10-12",  // Our Lady of Aparecida / Children's Day
    @"2026-11-02",  // All Souls' Day (Finados)
    @"2026-11-20",  // National Black Awareness Day (Consciência Negra)
    @"2026-12-25",  // Christmas Day
};

// v4 iter-175: per-market registry. Adding an exchange's holiday data
// = append one entry here + one static array above. No function-body
// changes. The lookup fans out by market_id match.
typedef struct {
    const char *market_id;
    NSString * const * _Nonnull dates;
    size_t count;
} FCHolidayTable;

static const FCHolidayTable kHolidayTables[] = {
    { "nyse",     kNYSE2026Holidays,    sizeof(kNYSE2026Holidays)    / sizeof(kNYSE2026Holidays[0])    },
    { "lse",      kLSE2026Holidays,     sizeof(kLSE2026Holidays)     / sizeof(kLSE2026Holidays[0])     },
    { "tse",      kTSE2026Holidays,     sizeof(kTSE2026Holidays)     / sizeof(kTSE2026Holidays[0])     },
    { "hkex",     kHKEX2026Holidays,    sizeof(kHKEX2026Holidays)    / sizeof(kHKEX2026Holidays[0])    },
    // v4 iter-179: both XETRA + Euronext reference kTARGET2_2026Holidays.
    { "xetra",    kTARGET2_2026Holidays, sizeof(kTARGET2_2026Holidays) / sizeof(kTARGET2_2026Holidays[0]) },
    { "euronext", kTARGET2_2026Holidays, sizeof(kTARGET2_2026Holidays) / sizeof(kTARGET2_2026Holidays[0]) },
    { "asx",      kASX2026Holidays,      sizeof(kASX2026Holidays)      / sizeof(kASX2026Holidays[0])      },
    { "tsx",      kTSX2026Holidays,      sizeof(kTSX2026Holidays)      / sizeof(kTSX2026Holidays[0])      },
    { "six",      kSIX2026Holidays,      sizeof(kSIX2026Holidays)      / sizeof(kSIX2026Holidays[0])      },
    { "sse",      kSSE2026Holidays,      sizeof(kSSE2026Holidays)      / sizeof(kSSE2026Holidays[0])      },
    { "krx",      kKRX2026Holidays,      sizeof(kKRX2026Holidays)      / sizeof(kKRX2026Holidays[0])      },
    { "nse",      kNSE2026Holidays,      sizeof(kNSE2026Holidays)      / sizeof(kNSE2026Holidays[0])      },
    { "jse",      kJSE2026Holidays,      sizeof(kJSE2026Holidays)      / sizeof(kJSE2026Holidays[0])      },
    { "b3",       kB3_2026Holidays,      sizeof(kB3_2026Holidays)      / sizeof(kB3_2026Holidays[0])      },
};
static const size_t kNumHolidayTables = sizeof(kHolidayTables) / sizeof(kHolidayTables[0]);

BOOL FCIsMarketHoliday(const ClockMarket *mkt, NSDate *date) {
    if (!mkt || !date) return NO;

    const FCHolidayTable *tbl = NULL;
    for (size_t i = 0; i < kNumHolidayTables; i++) {
        if (strcmp(mkt->id, kHolidayTables[i].market_id) == 0) {
            tbl = &kHolidayTables[i];
            break;
        }
    }
    if (!tbl) return NO;  // no data for this market yet

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
    NSString *iso = [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                     (long)c.year, (long)c.month, (long)c.day];
    for (size_t i = 0; i < tbl->count; i++) {
        if ([iso isEqualToString:tbl->dates[i]]) return YES;
    }
    return NO;
}
