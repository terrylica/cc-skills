#import "MarketSessionCalculator.h"
#import "../core/SessionSignalWindow.h"
#include <string.h>

const long kFCSecondsPerDay           = 24L * 3600L;
const long kFCMaxBoundedCountdownSecs = 99L * 3600L;

void computeSessionState(const ClockMarket *mkt, NSDate *now,
                         SessionState *outState, double *outProgress01,
                         long *outSecsToNext) {
    if (strlen(mkt->iana) == 0) {
        if (outState) *outState = kSessionClosed;
        if (outProgress01) *outProgress01 = 0.0;
        if (outSecsToNext) *outSecsToNext = 0;
        return;
    }

    NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
    if (!tz) tz = [NSTimeZone localTimeZone];

    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = tz;

    NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                         | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                         | NSCalendarUnitWeekday;
    NSDateComponents *comps = [cal components:units fromDate:now];

    BOOL isWeekend = (comps.weekday == 1 || comps.weekday == 7);

    NSInteger nowMins = comps.hour * 60 + comps.minute;
    NSInteger openMins = mkt->open_h * 60 + mkt->open_m;
    NSInteger closeMins = mkt->close_h * 60 + mkt->close_m;
    BOOL hasLunch = (mkt->lunch_start_h >= 0);
    NSInteger lunchStartMins = hasLunch ? (mkt->lunch_start_h * 60 + mkt->lunch_start_m) : -1;
    NSInteger lunchEndMins   = hasLunch ? (mkt->lunch_end_h   * 60 + mkt->lunch_end_m)   : -1;

    SessionState state;
    if (isWeekend) {
        state = kSessionClosed;
    } else if (nowMins < openMins || nowMins >= closeMins) {
        state = kSessionClosed;
    } else if (hasLunch && nowMins >= lunchStartMins && nowMins < lunchEndMins) {
        state = kSessionLunch;
    } else {
        state = kSessionOpen;
    }

    double progress = 0.0;
    if (state == kSessionOpen || state == kSessionLunch) {
        double elapsed = (double)(nowMins - openMins);
        double total = (double)(closeMins - openMins);
        if (total > 0) progress = MIN(1.0, MAX(0.0, elapsed / total));
    } else if (nowMins >= closeMins) {
        progress = 1.0;
    }

    // Throughout this block `nextBoundaryMins` is DELTA-minutes from now
    // to the next state transition (not absolute minute-of-day). The
    // secsToNext conversion below assumes delta form.
    NSInteger nextBoundaryMins;
    if (state == kSessionClosed) {
        if (!isWeekend && nowMins < openMins) {
            // v4 iter-48 fix: was `openMins` (absolute-min-of-day) which
            // produced a nonsensical secsToNext — e.g. NYSE showed "9h29m"
            // when actually opening in 2h37m. Correct delta is openMins - nowMins.
            nextBoundaryMins = openMins - nowMins;
        } else {
            int addDays = 1;
            NSInteger nextWeekday = ((comps.weekday) % 7) + 1;
            while (nextWeekday == 1 || nextWeekday == 7) {
                addDays++;
                nextWeekday = (nextWeekday % 7) + 1;
            }
            nextBoundaryMins = (24 * 60 - nowMins) + (addDays - 1) * 24 * 60 + openMins;
        }
    } else if (state == kSessionLunch) {
        nextBoundaryMins = lunchEndMins - nowMins;
    } else {
        nextBoundaryMins = closeMins - nowMins;
    }
    long secsToNext = nextBoundaryMins * 60L - comps.second;
    if (secsToNext < 0) secsToNext = 0;

    // v4 iter-123: promote CLOSED → PRE-MARKET when today's open is
    // ≤W min away (applies to every exchange — simpler than a per-
    // market hasPreMarket flag, and the auction-window heuristic
    // holds broadly). Weekend / cross-day-gap closed states stay
    // plain CLOSED because the promotion requires the same calendar
    // day's open ahead of now.
    //
    // v4 iter-126: W is user-controlled via the `SessionSignalWindow`
    // NSUserDefaults key (presets 0/5/15/30/60 min). W=0 disables both
    // PRE-MARKET and AFTER-HOURS promotions — pure OPEN/CLOSED/LUNCH
    // semantics for users who find the short signals noisy.
    NSString *sigId = [[NSUserDefaults standardUserDefaults] stringForKey:@"SessionSignalWindow"];
    NSInteger sigMins = FCSessionSignalWindowMinutes(sigId);

    if (sigMins > 0 && state == kSessionClosed && !isWeekend && nowMins < openMins && secsToNext <= sigMins * 60) {
        state = kSessionPreMarket;
    }

    // v4 iter-125: mirror of iter-123 for the post-close window. CLOSED is
    // promoted to AFTER-HOURS during the first W min following the regular
    // close (weekdays only). The countdown keeps pointing at tomorrow's
    // open; the distinct glyph is what signals "just closed" in the NEXT
    // segment. Uniform window shared with PRE-MARKET via
    // `SessionSignalWindow` (iter-126).
    if (sigMins > 0 && state == kSessionClosed && !isWeekend && nowMins >= closeMins && (nowMins - closeMins) <= sigMins) {
        state = kSessionAfterHours;
    }

    if (outState) *outState = state;
    if (outProgress01) *outProgress01 = progress;
    if (outSecsToNext) *outSecsToNext = secsToNext;
}

NSString *formatCountdown(long secs) {
    if (secs < 60) return [NSString stringWithFormat:@"%lds", secs];
    long mins = secs / 60;
    if (mins < 60) return [NSString stringWithFormat:@"%ldm", mins];
    long hours = mins / 60;
    long rmins = mins % 60;
    if (hours < 100) return [NSString stringWithFormat:@"%ldh%02ldm", hours, rmins];
    return [NSString stringWithFormat:@"%ldh", hours];
}

NSString *formatCountdownFancy(long secs) {
    if (secs < 0) secs = 0;
    // v4 iter-75: progressive human-readable format. Sub-day preserves
    // the ticker-like HH:MM:SS feel (seconds visibly tick as T-0
    // approaches). At ≥24h, switch to 'Nd Hh Mm' which is how humans
    // actually read long durations — '2d 11h 27m' is instantly
    // comprehensible where 'T-59:27:14' requires mental division.
    // Drops seconds at day-scale since they're visually insignificant.
    //
    // Pattern sourced from NSDateComponentsFormatter's .abbreviated
    // style + progressive-countdown UX pattern (Atlassian Design,
    // TimeMath, etc.). Implemented inline rather than via
    // NSDateComponentsFormatter because we want fixed 'T-' prefix and
    // zero-padded hours/minutes for column alignment.
    if (secs >= kFCSecondsPerDay) {
        long days  = secs / kFCSecondsPerDay;
        long rem   = secs % kFCSecondsPerDay;
        long hours = rem / 3600;
        long mins  = (rem % 3600) / 60;
        return [NSString stringWithFormat:@"T-%ldd %ldh %02ldm", days, hours, mins];
    }
    long hours = secs / 3600;
    long rem   = secs % 3600;
    long mins  = rem / 60;
    long rsecs = rem % 60;
    return [NSString stringWithFormat:@"T-%02ld:%02ld:%02ld", hours, mins, rsecs];
}

// Glyph-set dispatch. Read NSUserDefaults "ProgressBarStyle" and return
// the (filled, empty) pair. Default = "blocks" (current 1/8-width heavy
// block + medium shade). Adding a new style = one extra if-branch here.
static void fcGlyphsForStyle(NSString *styleId, NSString **filled, NSString **empty) {
    if ([styleId isEqualToString:@"blocks"])  { *filled = @"█"; *empty = @"▒"; return; }
    if ([styleId isEqualToString:@"dashes"])  { *filled = @"━"; *empty = @"╌"; return; }
    if ([styleId isEqualToString:@"arrows"])  { *filled = @"▶"; *empty = @"▷"; return; }
    if ([styleId isEqualToString:@"binary"])  { *filled = @"█"; *empty = @"░"; return; }
    if ([styleId isEqualToString:@"braille"]) { *filled = @"⣿"; *empty = @"⣀"; return; }
    // v4 iter-91: expand glyph catalog 6 → 10.
    if ([styleId isEqualToString:@"hearts"])  { *filled = @"♥"; *empty = @"♡"; return; }
    if ([styleId isEqualToString:@"stars"])   { *filled = @"★"; *empty = @"☆"; return; }
    if ([styleId isEqualToString:@"ribbon"])  { *filled = @"▰"; *empty = @"▱"; return; }
    if ([styleId isEqualToString:@"diamond"]) { *filled = @"◆"; *empty = @"◇"; return; }
    // v4 iter-131: expand glyph catalog 10 → 12.
    if ([styleId isEqualToString:@"triangles"]) { *filled = @"▲"; *empty = @"△"; return; }
    if ([styleId isEqualToString:@"thindots"])  { *filled = @"•"; *empty = @"·"; return; }
    // Default "dots" (v4 iter-35 user directive).
    *filled = @"●"; *empty = @"○";
}

NSString *buildProgressBar(double progress01, int totalCells) {
    if (progress01 < 0) progress01 = 0;
    if (progress01 > 1) progress01 = 1;
    int fullCells = (int)(progress01 * totalCells + 0.5);
    if (fullCells > totalCells) fullCells = totalCells;

    NSString *styleId = [[NSUserDefaults standardUserDefaults] stringForKey:@"ProgressBarStyle"];
    NSString *filled = nil;
    NSString *empty = nil;
    fcGlyphsForStyle(styleId, &filled, &empty);

    NSMutableString *bar = [NSMutableString string];
    for (int i = 0; i < fullCells; i++) [bar appendString:filled];
    for (int i = fullCells; i < totalCells; i++) [bar appendString:empty];
    return bar;
}

int fcProgressBarFullCells(double progress01, int totalCells) {
    if (progress01 < 0) progress01 = 0;
    if (progress01 > 1) progress01 = 1;
    int fullCells = (int)(progress01 * totalCells + 0.5);
    if (fullCells > totalCells) fullCells = totalCells;
    return fullCells;
}

NSString *glyphForState(SessionState s) {
    switch (s) {
        case kSessionOpen:       return @"●";
        case kSessionLunch:      return @"◑";
        case kSessionClosed:     return @"○";
        case kSessionPreMarket:  return @"◐";  // v4 iter-123 (left half dark)
        case kSessionAfterHours: return @"◒";  // v4 iter-125 (bottom half dark — symmetric to PRE-MARKET)
    }
    return @"○";
}

// v4 iter-135: extracted from Runtime.m's inline switch (iter-134).
// Kept next to glyphForState so the full (glyph, label, color) triad
// lives in one file and adding a future SessionState value is a
// compiler-enforced 3-switch edit.
NSString *labelForState(SessionState s) {
    switch (s) {
        case kSessionOpen:       return @"OPEN";
        case kSessionLunch:      return @"LUNCH";
        case kSessionClosed:     return @"CLOSED";
        case kSessionPreMarket:  return @"PRE-MARKET";
        case kSessionAfterHours: return @"AFTER-HOURS";
    }
    return @"CLOSED";
}

NSColor *colorForState(SessionState s, const ClockTheme *theme) {
    (void)theme;  // reserved for future per-theme override
    switch (s) {
        case kSessionOpen:       return [NSColor colorWithRed:0.20 green:0.95 blue:0.40 alpha:1.0];
        case kSessionLunch:      return [NSColor colorWithRed:0.80 green:0.55 blue:0.95 alpha:1.0];
        case kSessionClosed:     return [NSColor colorWithWhite:0.55 alpha:1.0];
        case kSessionPreMarket:  return [NSColor colorWithRed:1.00 green:0.70 blue:0.15 alpha:1.0];  // amber — iter-123 (dawn)
        case kSessionAfterHours: return [NSColor colorWithRed:0.95 green:0.45 blue:0.55 alpha:1.0];  // rose/sunset — iter-125 (dusk)
    }
    return [NSColor whiteColor];
}
