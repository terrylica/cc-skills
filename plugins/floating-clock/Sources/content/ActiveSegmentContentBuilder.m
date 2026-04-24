#import "ActiveSegmentContentBuilder.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../data/MarketSessionCalculator.h"

NSAttributedString *FCBuildActiveSegmentContent(void) {
    NSDate *now = [NSDate date];
    CGFloat fontSize = [[NSUserDefaults standardUserDefaults] doubleForKey:@"ActiveFontSize"];
    if (fontSize < 6) fontSize = 11;
    NSFont *font = [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightMedium];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    const ClockTheme *theme = themeForId([d stringForKey:@"ActiveTheme"]);
    NSColor *headerColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dimColor    = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.5];

    NSInteger barCells = [d integerForKey:@"ActiveBarCells"];
    if (barCells <= 0) barCells = 7;

    // First pass: active markets grouped by IANA (same timezone shares a header).
    NSMutableArray<NSMutableArray *> *groups = [NSMutableArray array];
    NSMutableArray<NSString *> *groupIanas = [NSMutableArray array];

    for (size_t i = 1; i < kNumMarkets; i++) {  // skip index 0 (local)
        const ClockMarket *m = &kMarkets[i];
        SessionState state;
        double progress;
        long secsToNext;
        computeSessionState(m, now, &state, &progress, &secsToNext);
        if (state == kSessionOpen || state == kSessionLunch) {
            NSString *iana = [NSString stringWithUTF8String:m->iana];
            NSInteger idx = [groupIanas indexOfObject:iana];
            if (idx == NSNotFound) {
                [groupIanas addObject:iana];
                NSMutableArray *newGroup = [NSMutableArray array];
                [newGroup addObject:@(i)];
                [newGroup addObject:@(state)];
                [newGroup addObject:@(progress)];
                [newGroup addObject:@(secsToNext)];
                [groups addObject:newGroup];
            } else {
                NSMutableArray *g = groups[idx];
                [g addObject:@(i)];
                [g addObject:@(state)];
                [g addObject:@(progress)];
                [g addObject:@(secsToNext)];
            }
        }
    }

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    if (groups.count == 0) {
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"— NO OPEN MARKETS —"
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: dimColor}]];
        return out;
    }

    for (NSUInteger g = 0; g < groups.count; g++) {
        NSMutableArray *group = groups[g];
        NSString *iana = groupIanas[g];
        NSUInteger marketsInGroup = group.count / 4;

        // Header: "TOK Fri Apr 24 11:15:07 JST" — city + local day/date + time with seconds.
        // Abbreviation via NSTimeZone (not formatter `z`) to keep regional
        // names like BST/CEST instead of falling back to GMT+N.
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:iana];
        NSDateFormatter *hf = [[NSDateFormatter alloc] init];
        hf.dateFormat = @"EEE MMM d HH:mm:ss";
        if (tz) hf.timeZone = tz;
        NSString *tzLabel = fullTzLabelForIana(iana.UTF8String, now);
        NSString *headerTime = [NSString stringWithFormat:@"%@ %@",
            [hf stringFromDate:now], tzLabel];
        const ClockMarket *firstM = &kMarkets[[(NSNumber *)group[0] intValue]];
        const char *cityCode = cityCodeForIana(firstM->iana);
        const char *flag = [d boolForKey:@"ShowFlags"] ? flagForIana(firstM->iana) : "";

        // Emoji glyphs don't render inside monospacedSystemFont — use the
        // default system font (Apple Color Emoji fallback) for the flag
        // prefix only, then the mono font for the rest of the header.
        if (flag[0] != 0) {
            NSString *flagStr = [[NSString stringWithUTF8String:flag] stringByAppendingString:@" "];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:flagStr
                attributes:@{NSFontAttributeName: ([NSFont fontWithName:@"Apple Color Emoji" size:fontSize] ?: [NSFont systemFontOfSize:fontSize])}]];
        }
        NSString *headerLine = [NSString stringWithFormat:@"%s %@\n", cityCode, headerTime];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:headerLine
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

        for (NSUInteger i = 0; i < marketsInGroup; i++) {
            NSUInteger mktIdx = [(NSNumber *)group[i*4] unsignedIntValue];
            const ClockMarket *m = &kMarkets[mktIdx];
            SessionState state = (SessionState)[(NSNumber *)group[i*4+1] intValue];
            double progress = [(NSNumber *)group[i*4+2] doubleValue];
            long secsToNext = [(NSNumber *)group[i*4+3] longValue];

            NSString *glyph = glyphForState(state);
            NSColor *glyphColor = colorForState(state, NULL);
            NSString *code = [NSString stringWithUTF8String:m->code];
            NSString *bar = buildProgressBar(progress, (int)barCells);
            NSString *cd = formatCountdown(secsToNext);
            NSString *suffix = (state == kSessionLunch) ? @" LUNCH" : @"";

            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"  "
                attributes:@{NSFontAttributeName: font}]];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:glyph
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: glyphColor}]];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@" %-4s ", [code UTF8String]]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

            // Color split: fill [0..fullCells), empty [fullCells..total).
            // Using fcProgressBarFullCells keeps the math in one place and
            // works across every ProgressBarStyle glyph pair.
            NSColor *fillColor = glyphColor;
            NSColor *emptyColor = [NSColor colorWithWhite:0.55 alpha:1.0];
            NSInteger splitIdx = fcProgressBarFullCells(progress, (int)barCells);
            if (splitIdx > (NSInteger)bar.length) splitIdx = bar.length;
            NSMutableAttributedString *barAttr = [[NSMutableAttributedString alloc]
                initWithString:bar attributes:@{NSFontAttributeName: font}];
            [barAttr addAttribute:NSForegroundColorAttributeName value:fillColor
                            range:NSMakeRange(0, splitIdx)];
            [barAttr addAttribute:NSForegroundColorAttributeName value:emptyColor
                            range:NSMakeRange(splitIdx, bar.length - splitIdx)];
            [out appendAttributedString:barAttr];

            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@" %@%@\n", cd, suffix]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];
        }

        if (g < groups.count - 1) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n"
                attributes:@{NSFontAttributeName: font}]];
        }
    }

    return out;
}
