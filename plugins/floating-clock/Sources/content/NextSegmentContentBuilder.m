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
            NSString *verb = e.isLunchResume ? @"resumes in" : @"opens in";
            countdown = [NSString stringWithFormat:@"%@ %@", verb, formatCountdown(e.secs)];
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
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@%@", countdown, suffix]
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];
        if (i < maxItems - 1) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n" attributes:@{NSFontAttributeName: font}]];
        }
    }

    return out;
}
