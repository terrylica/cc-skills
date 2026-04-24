#import "NextSegmentContentBuilder.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../data/MarketSessionCalculator.h"
#import "../rendering/FontResolver.h"
#import "SegmentHeaderRenderer.h"
#import "UrgencyColors.h"
#import "LandingTimeFormatter.h"

NSAttributedString *FCBuildNextSegmentContent(void) {
    NSDate *now = [NSDate date];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    CGFloat fontSize = [d doubleForKey:@"NextFontSize"];
    if (fontSize < 6) fontSize = 11;
    NSFontWeight fw = FCResolveSegmentWeight(@"NextWeight");
    NSFont *font = FCResolveMonoFont(fontSize, fw);
    const ClockTheme *theme = themeForId([d stringForKey:@"NextTheme"]);
    NSColor *headerColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dimColor    = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.5];
    NSColor *codeColor   = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.75];

    NSInteger maxN = [d integerForKey:@"NextItemCount"];
    if (maxN <= 0) maxN = 3;

    typedef struct {
        const ClockMarket *mkt;
        long secs;
        BOOL isLunchResume;
        SessionState state;  // v4 iter-141: preserve so render-loop picks the right glyph/color
    } NextEntry;

    NextEntry entries[kNumMarkets];
    int entryCount = 0;

    for (size_t i = 1; i < kNumMarkets; i++) {  // skip local
        const ClockMarket *m = &kMarkets[i];
        SessionState state;
        double progress;
        long secsToNext;
        computeSessionState(m, now, &state, &progress, &secsToNext);

        // v4 iter-123: PRE-MARKET goes in NEXT alongside CLOSED —
        // they both await the opening bell, just PRE-MARKET is ≤15 min
        // away and gets the amber state glyph.
        // v4 iter-125: AFTER-HOURS also lives in NEXT — the countdown still
        // points at tomorrow's open; the ◒ glyph is what tells the reader
        // "this market just closed" versus overnight CLOSED.
        if (state == kSessionClosed || state == kSessionPreMarket || state == kSessionAfterHours) {
            entries[entryCount++] = (NextEntry){m, secsToNext, NO, state};
        } else if (state == kSessionLunch) {
            entries[entryCount++] = (NextEntry){m, secsToNext, YES, state};
        }
        // Skip kSessionOpen — already in ACTIVE
    }

    // Insertion sort by secs ascending (small array).
    for (int i = 1; i < entryCount; i++) {
        NextEntry key = entries[i];
        int j = i - 1;
        while (j >= 0 && entries[j].secs > key.secs) {
            entries[j+1] = entries[j];
            j--;
        }
        entries[j+1] = key;
    }

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    if (entryCount == 0) {
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"— NO UPCOMING OPENS —"
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: dimColor}]];
        return out;
    }

    // v4 iter-63: tabulated demarcation — header + a horizontal rule
    // at top and between entries so each market is clearly delimited
    // as a unit. Horizontal rule uses light-weight U+2500 '─' at length
    // 44, which fits comfortably in the NEXT segment at 11pt.
    // v4 iter-73: shared section-header helper (SegmentHeaderRenderer).
    // v4 iter-201: title suppressed — [NEXT] bottom-left canonical
    // label (iter-199) is the section identifier. Legend + hrule stay
    // because they describe the column format.
    // v4 iter-208: legend reordered to match the new row layout —
    // countdown moved to the END of each row (was leading), so the
    // legend mirrors the new chronological sequence: your time →
    // market time → session → countdown.
    FCAppendSectionHeader(out, font,
        @"",
        @"your time → market time · session · countdown",
        headerColor, dimColor, FCDividerRuleColor());

    int maxItems = entryCount < maxN ? entryCount : (int)maxN;
    for (int i = 0; i < maxItems; i++) {
        NextEntry e = entries[i];
        // v4 iter-141: render the actual state's glyph/color instead of
        // hardcoding ○ gray for non-lunch. PRE-MARKET (◐ amber) and
        // AFTER-HOURS (◒ rose) were invisible in NEXT before this fix —
        // iter-123/125 introduced the states and iter-125 added them to
        // the filter, but the render loop was hardcoded to ○.
        NSString *glyph = glyphForState(e.state);
        NSColor *glyphColor = colorForState(e.state, NULL);
        NSString *code = [NSString stringWithUTF8String:e.mkt->code];
        NSString *countdown;
        if (e.secs > kFCMaxBoundedCountdownSecs) {
            NSDate *opensAt = [NSDate dateWithTimeIntervalSinceNow:e.secs];
            NSDateFormatter *openFmt = [[NSDateFormatter alloc] init];
            openFmt.dateFormat = @"EEE HH:mm";
            NSTimeZone *mktTz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:e.mkt->iana]];
            if (mktTz) openFmt.timeZone = mktTz;
            NSString *label = fullTzLabelForIana(e.mkt->iana, opensAt);
            countdown = [NSString stringWithFormat:@"opens %@ %@",
                [openFmt stringFromDate:opensAt], label];
        } else {
            // v4 iter-41: append the absolute landing time in the user's
            // local zone so traders can see "when does this land in my
            // day" without mental arithmetic. Market's own-TZ opening is
            // already implicit (each market has fixed local open hours);
            // what's uniquely useful here is "HH:mm MY time".
            // v4 iter-49: include weekday abbrev when landing is not
            // today in local tz. Prevents ambiguity on bounded opens
            // that cross midnight — e.g. Sat 23:00 local → "opens in
            // 80h · 06:30 local" used to look like it meant "today
            // 06:30". Now reads "06:30 local Tue" for clarity.
            NSString *verb = e.isLunchResume ? @"resumes in" : @"opens in";
            NSDate *now = [NSDate date];
            NSDate *landsAt = [NSDate dateWithTimeIntervalSinceNow:e.secs];
            NSTimeZone *localTz = [NSTimeZone localTimeZone];
            NSCalendar *cal = [NSCalendar currentCalendar];
            cal.timeZone = localTz;
            NSDateComponents *nowC = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
            NSDateComponents *landC = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:landsAt];
            BOOL sameDay = (nowC.year == landC.year && nowC.month == landC.month && nowC.day == landC.day);
            NSDateFormatter *localFmt = [[NSDateFormatter alloc] init];
            localFmt.timeZone = localTz;
            localFmt.dateFormat = sameDay ? @"HH:mm" : @"HH:mm 'local' EEE";
            NSString *localAt = [localFmt stringFromDate:landsAt];
            // v4 iter-59: fanciful rocket-launch style countdown.
            // "T-HH:MM:SS" conveys "counting down to an event" and ticks
            // with second precision — critical visible granularity as
            // T-0 approaches. Lunch-resume entries use the same format
            // since the user cares about seconds equally for "resumes in".
            NSString *cd = formatCountdownFancy(e.secs);
            countdown = sameDay
                ? [NSString stringWithFormat:@"%@ %@ · %@ local", verb, cd, localAt]
                : [NSString stringWithFormat:@"%@ %@ · %@", verb, cd, localAt];
        }
        NSString *suffix = e.isLunchResume ? @" LUNCH" : @"";

        // v4 iter-208: user directive — remove leading glyph bullet
        // (flag emoji already acts as the row bullet), remove the
        // 2-space indent that was there to align with the glyph, and
        // emit flag + code on the first line WITHOUT a countdown.
        // Countdown is appended at the END of the second line (below)
        // so the chronological sequence reads your-time → market-time
        // → session → countdown.
        (void)glyph; (void)glyphColor;  // iter-208: no longer rendered inline
        const char *flag = [d boolForKey:@"ShowFlags"] ? flagForIana(e.mkt->iana) : "";
        if (flag[0] != 0) {
            NSString *flagStr = [NSString stringWithUTF8String:flag];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:flagStr
                attributes:@{NSFontAttributeName: ([NSFont fontWithName:@"Apple Color Emoji" size:fontSize] ?: [NSFont systemFontOfSize:fontSize])}]];
        }
        NSString *codeLabel = [NSString stringWithFormat:@" %-4s", [code UTF8String]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:codeLabel
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: codeColor}]];
        // v4 iter-45: symmetric urgency tiers with iter-44 (ACTIVE close).
        // v4 iter-73: routed through shared FCUrgencyColorForSecs.
        // v4 iter-208: countdown color still computed here but the
        // glyph used to own the opacity here — now countdown color
        // carries the urgency signal on its own.
        NSColor *countdownColor = (e.secs <= kFCMaxBoundedCountdownSecs)
            ? FCUrgencyColorForSecs(e.secs, headerColor)
            : headerColor;
        NSString *countdownStr = (e.secs <= kFCMaxBoundedCountdownSecs)
            ? [NSString stringWithFormat:@"%@%@", formatCountdownFancy(e.secs), suffix]
            : countdown;

        // v4 iter-60: richer second-line layout per market — surfaces the
        // market's own-TZ open time + session duration, matching what
        // competitor apps (Market 24h Clock, Market Clock Trading Hours,
        // TradingView session indicators) show. Only rendered for
        // bounded countdowns; >99h rows already carry market-TZ info.
        if (e.secs <= kFCMaxBoundedCountdownSecs) {
            NSDate *landsAt = [NSDate dateWithTimeIntervalSinceNow:e.secs];
            // v4 iter-74: delegate dual-zone formatting to the shared
            // LandingTimeFormatter. Encapsulates the iter-49 cross-day
            // rule and the iter-68 weekday-differs rule in one place.
            NSString *localAt = @"";
            NSString *mktAt = @"";
            FCFormatLandingTime([NSDate date], landsAt, e.mkt->iana, &localAt, &mktAt);

            // Session duration (close - open, same-day). Lunch-resume
            // events share the session — skip dur line for them since
            // the second line would be misleading ("6h30m" isn't the
            // lunch window).
            // v4 iter-66: duration now just "6h30m" (no " session"
            // suffix — the column legend says 'session').
            NSString *durStr = @"";
            if (!e.isLunchResume) {
                int openMins  = e.mkt->open_h * 60 + e.mkt->open_m;
                int closeMins = e.mkt->close_h * 60 + e.mkt->close_m;
                int durMins   = closeMins - openMins;
                if (durMins > 0) {
                    int dh = durMins / 60;
                    int dm = durMins % 60;
                    durStr = (dm == 0)
                        ? [NSString stringWithFormat:@" · %dh", dh]
                        : [NSString stringWithFormat:@" · %dh%02dm", dh, dm];
                }
            }

            // v4 iter-69 → v4 iter-208: iter-208 removed the leading
            // glyph from line 1, so the indent re-aligns under the
            // flag+code column (flag ~2 cells + space + 4-char code +
            // space ≈ 8 cells). Keep └─ anchored via 4-space indent
            // now that the first line starts at col 0 (no 2-space
            // indent). Append the countdown at the END — user
            // directive "chronological sequence: your time → market
            // time → session → countdown".
            NSString *secondLinePrefix = [NSString stringWithFormat:@"\n    └─ %@ → %@%@  ",
                localAt, mktAt, durStr];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:secondLinePrefix
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: codeColor}]];
            // Countdown at line-end, in its urgency color — the row's
            // visual focal point moves from row-leading (old) to row-
            // trailing (new), matching a left-to-right chronological
            // scan your-time → market-time → session → countdown.
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:countdownStr
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: countdownColor}]];
        } else {
            // >99h case: append countdown (absolute-date form) still
            // at the end of the row. There's no second line in this
            // branch, so it follows right after flag + code.
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:[@"  " stringByAppendingString:countdownStr]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: countdownColor}]];
        }

        // v4 iter-63: horizontal rule between entries — clear tabular
        // demarcation. v4 iter-73: shared constant + helper (note
        // inline \n prefix here because the secondLine above ends
        // without newline — pre-rule separator).
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@"\n" stringByAppendingString:kFCSegmentHRule]
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: FCDividerRuleColor()}]];
        if (i < maxItems - 1) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n" attributes:@{NSFontAttributeName: font}]];
        }
    }

    // v4 iter-62: terminate the attributed string with a trailing \n.
    // Without this, NSTextField's cell rendering elides the last line
    // when no newline follows — a quirk that manifested as the third
    // NEXT row missing its second line (iter-60/61 debug). ACTIVE
    // segment doesn't exhibit this because every data line already
    // ends with \n. The measurer's "ends-in-newline" branch also adds
    // a line-height, which in turn gives the frame enough room.
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"\n" attributes:@{NSFontAttributeName: font}]];

    FCApplyLetterSpacing(out);  // v4 iter-94
    FCApplyLineSpacing(out);    // v4 iter-95
    return out;
}
