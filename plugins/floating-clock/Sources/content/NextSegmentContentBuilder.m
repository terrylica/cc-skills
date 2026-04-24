#import "NextSegmentContentBuilder.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../data/MarketSessionCalculator.h"

NSAttributedString *FCBuildNextSegmentContent(void) {
    NSDate *now = [NSDate date];
    CGFloat fontSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"NextFontSize"];
    if (fontSize < 6) fontSize = 11;
    NSFont *font = [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightMedium];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
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
    } NextEntry;

    NextEntry entries[kNumMarkets];
    int entryCount = 0;

    for (size_t i = 1; i < kNumMarkets; i++) {  // skip local
        const ClockMarket *m = &kMarkets[i];
        SessionState state;
        double progress;
        long secsToNext;
        computeSessionState(m, now, &state, &progress, &secsToNext);

        if (state == kSessionClosed) {
            entries[entryCount++] = (NextEntry){m, secsToNext, NO};
        } else if (state == kSessionLunch) {
            entries[entryCount++] = (NextEntry){m, secsToNext, YES};
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

    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"NEXT TO OPEN\n"
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

    int maxItems = entryCount < maxN ? entryCount : (int)maxN;
    for (int i = 0; i < maxItems; i++) {
        NextEntry e = entries[i];
        NSString *glyph = e.isLunchResume ? @"◑" : @"○";
        NSColor *glyphColor = e.isLunchResume
            ? [NSColor colorWithRed:0.80 green:0.55 blue:0.95 alpha:1.0]
            : [NSColor colorWithWhite:0.55 alpha:1.0];
        NSString *code = [NSString stringWithUTF8String:e.mkt->code];
        NSString *countdown;
        if (e.secs > 99 * 3600) {
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

        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:glyph
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: glyphColor}]];
        const char *flag = [d boolForKey:@"ShowFlags"] ? flagForIana(e.mkt->iana) : "";
        if (flag[0] != 0) {
            NSString *flagStr = [@" " stringByAppendingString:[NSString stringWithUTF8String:flag]];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:flagStr
                attributes:@{NSFontAttributeName: ([NSFont fontWithName:@"Apple Color Emoji" size:fontSize] ?: [NSFont systemFontOfSize:fontSize])}]];
        }
        NSString *codeLabel = [NSString stringWithFormat:@" %-4s ", [code UTF8String]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:codeLabel
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: codeColor}]];
        // v4 iter-45: symmetric urgency tiers with iter-44 (ACTIVE close
        // countdown). Markets imminently opening deserve the same visual
        // urgency as markets imminently closing. Only applies to bounded
        // countdowns (e.secs <= 99h); >99h opens use absolute-date form.
        NSColor *countdownColor = headerColor;
        if (e.secs <= 99 * 3600) {
            if (e.secs < 1800)      countdownColor = [NSColor colorWithRed:0.95 green:0.40 blue:0.40 alpha:1.0];
            else if (e.secs < 3600) countdownColor = [NSColor colorWithRed:0.95 green:0.75 blue:0.30 alpha:1.0];
        }
        // v4 iter-60: compact first line = "T-HH:MM:SS until open".
        NSString *firstLine = (e.secs <= 99 * 3600)
            ? [NSString stringWithFormat:@"%@ %@%@",
               formatCountdownFancy(e.secs),
               e.isLunchResume ? @"until lunch ends" : @"until open",
               suffix]
            : countdown;  // >99h: use the existing absolute-date form
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:firstLine
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: countdownColor}]];

        // v4 iter-60: richer second-line layout per market — surfaces the
        // market's own-TZ open time + session duration, matching what
        // competitor apps (Market 24h Clock, Market Clock Trading Hours,
        // TradingView session indicators) show. Only rendered for
        // bounded countdowns; >99h rows already carry market-TZ info.
        if (e.secs <= 99 * 3600) {
            NSDate *landsAt = [NSDate dateWithTimeIntervalSinceNow:e.secs];
            NSTimeZone *localTz = [NSTimeZone localTimeZone];
            NSCalendar *cal = [NSCalendar currentCalendar];
            cal.timeZone = localTz;
            NSDateComponents *nowC = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[NSDate date]];
            NSDateComponents *landC = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:landsAt];
            BOOL sameDay = (nowC.year == landC.year && nowC.month == landC.month && nowC.day == landC.day);
            NSDateFormatter *localFmt = [[NSDateFormatter alloc] init];
            localFmt.timeZone = localTz;
            localFmt.dateFormat = sameDay ? @"HH:mm" : @"HH:mm EEE";
            NSString *localAt = [localFmt stringFromDate:landsAt];

            // Market's own-TZ open time (e.g. "09:30 EDT")
            NSString *mktAt = @"";
            if (strlen(e.mkt->iana) > 0) {
                NSTimeZone *mktTz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:e.mkt->iana]];
                NSDateFormatter *mktFmt = [[NSDateFormatter alloc] init];
                mktFmt.dateFormat = @"HH:mm";
                if (mktTz) mktFmt.timeZone = mktTz;
                NSString *mktAbbrev = friendlyAbbrevForIana(e.mkt->iana, landsAt);
                mktAt = [NSString stringWithFormat:@"%@ %@",
                    [mktFmt stringFromDate:landsAt], mktAbbrev];
            }

            // Session duration (close - open, same-day). Lunch-resume
            // events share the session — skip dur line for them since
            // the second line would be misleading ("6h30m" isn't the
            // lunch window).
            NSString *durStr = @"";
            if (!e.isLunchResume) {
                int openMins  = e.mkt->open_h * 60 + e.mkt->open_m;
                int closeMins = e.mkt->close_h * 60 + e.mkt->close_m;
                int durMins   = closeMins - openMins;
                if (durMins > 0) {
                    int dh = durMins / 60;
                    int dm = durMins % 60;
                    durStr = (dm == 0)
                        ? [NSString stringWithFormat:@" · %dh session", dh]
                        : [NSString stringWithFormat:@" · %dh%02dm session", dh, dm];
                }
            }

            NSString *secondLine = [NSString stringWithFormat:@"\n       %@ local → %@%@",
                localAt, mktAt, durStr];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:secondLine
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: codeColor}]];
        }

        if (i < maxItems - 1) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n" attributes:@{NSFontAttributeName: font}]];
        }
    }

    return out;
}
