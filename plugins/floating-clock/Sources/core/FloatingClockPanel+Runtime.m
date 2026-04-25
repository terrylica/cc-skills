#import "FloatingClockPanel+Runtime.h"
#import "FloatingClockPanel+Layout.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../data/MarketSessionCalculator.h"
#import "../content/ActiveSegmentContentBuilder.h"
#import "../content/NextSegmentContentBuilder.h"
#import "../content/WeekProgressBar.h"      // iter-229: weekly progress on LOCAL
#import "../content/UrgencyColors.h"        // iter-233: FCProgressEmptyColor for week bar
#import "../data/MoonPhase.h"               // iter-243: offline moon phase
#import "../rendering/FontResolver.h"  // FCCurrentTimeFormat
#import "DateFormatPrefix.h"              // FCDateFormatPrefix
#import "SkyGlyph.h"                       // FCSkyGlyphForHour

// Nanoseconds until next second boundary. Used by setupTimer's first fire.
static uint64_t nsUntilNextSecond(void) {
    NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
    double frac = t - floor(t);
    return (uint64_t)((1.0 - frac) * NSEC_PER_SEC);
}

// v4 iter-111 / iter-113: date-format preset dispatcher lives in
// Sources/core/DateFormatPrefix.{h,m} now — FCDateFormatPrefix(id)
// is the public entry point. Runtime.m's 2 call sites below route
// through it.

// v4 iter-98 / iter-107: TimeSeparator helpers live in FontResolver.{h,m}
// now — `FCCurrentTimeFormat(is12h, showSec)` is the public entry point.
// Kept the 3 call sites below intact; they just route through the
// public function instead of the old file-scoped static helpers.

@implementation FloatingClockPanel (Runtime)

- (void)setupTimer {
    dispatch_queue_t q = dispatch_get_main_queue();
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(_timer,
        dispatch_time(DISPATCH_TIME_NOW, nsUntilNextSecond()),
        NSEC_PER_SEC,
        (uint64_t)(NSEC_PER_SEC / 10));  // 100ms leeway for power savings
    dispatch_source_set_event_handler(_timer, ^{ [self tick]; });
    dispatch_resume(_timer);
    [self tick];  // immediate paint so window isn't blank
}

- (void)tick {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *mode = [d stringForKey:@"DisplayMode"];
    // v4 iter-235 bug fix: when SegmentsCollapsed=YES, applyLocalOnlyLayout
    // hides _localSeg/_activeSeg/_nextSeg and shows _label. tick() must
    // route to tickLegacy in that case so _label gets populated — otherwise
    // the canvas shows a blank gray box (the bug user reported).
    BOOL collapsed = [d boolForKey:@"SegmentsCollapsed"];
    if ([mode isEqualToString:@"three-segment"] && !collapsed) {
        [self tickThreeSegment];
    } else {
        [self tickLegacy];
    }
}

- (void)tickThreeSegment {
    NSMutableString *fmt = [NSMutableString string];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL showDate = [d boolForKey:@"ShowDate"];
    NSString *tf = [d stringForKey:@"TimeFormat"];

    // v4 iter-46: honor ShowSeconds pref. Prior comment said "always
    // shown" but the menu toggle still existed and users could check/
    // uncheck it with no effect. Now it really strips the ":ss" portion
    // — less jitter, less clutter for minimalist setups.
    BOOL showSec = [d boolForKey:@"ShowSeconds"];
    if (showDate) [fmt appendString:FCDateFormatPrefix([d stringForKey:@"DateFormat"])];
    // v4 iter-98: separator chosen via FCCurrentTimeFormat (was hardcoded `:`).
    [fmt appendString:FCCurrentTimeFormat([tf isEqualToString:@"12h"], showSec)];

    if (!_dateFormatter) _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateFormat = fmt;
    NSTimeZone *localTz = [NSTimeZone localTimeZone];
    _dateFormatter.timeZone = localTz;

    NSDate *nowLocal = [NSDate date];
    NSString *localLabel = fullTzLabelForZone(localTz, nowLocal);

    // Inline UTC reference honors user directive 2026-04-24: "the original
    // time must also be considered". UTC is the canonical astronomical
    // origin; showing it alongside local time disambiguates any DST edge
    // case and gives a fixed reference for cross-timezone coordination.
    // Canonical rendering: always 24h (scientific convention — UTC is
    // written HH:mm:ss in every ISO-8601 context, regardless of the user's
    // local 12h preference). Hidden when ShowUTCReference pref is NO.
    BOOL showUTC = ![d objectForKey:@"ShowUTCReference"] || [d boolForKey:@"ShowUTCReference"];
    NSString *localBase = [_dateFormatter stringFromDate:nowLocal];

    // v4 iter-42 + iter-112: sun/moon glyph — subtle day/night cue.
    // No astronomical calculation (needs lat/lon + solar position);
    // simple hour buckets match civil-twilight expectations closely.
    // iter-112 upgrades binary (☀/🌙) to 5 phases for more nuance:
    //   [5, 7)   🌅 dawn / sunrise
    //   [7, 12)  ☀️ morning
    //   [12, 17) ☀️ afternoon (same glyph, phase name differs)
    //   [17, 19) 🌇 dusk / sunset
    //   [19, 5)  🌙 night
    // Hidden when ShowSkyState pref is explicitly NO.
    BOOL showSky = ![d objectForKey:@"ShowSkyState"] || [d boolForKey:@"ShowSkyState"];
    NSString *skyGlyph = @"";
    if (showSky) {
        NSCalendar *cal = [NSCalendar currentCalendar];
        cal.timeZone = localTz;
        NSInteger hour = [cal component:NSCalendarUnitHour fromDate:nowLocal];
        skyGlyph = [NSString stringWithFormat:@" %@", FCSkyGlyphForHour(hour)];
    }

    // v4 iter-243: pure-offline moon-phase glyph (synodic-month
    // calculation from a known new-moon epoch — no lat/lon, no
    // network). Default ON; toggle via Show Moon Phase menu item.
    NSString *moonGlyph = @"";
    BOOL showMoon = ![d objectForKey:@"ShowMoonPhase"] || [d boolForKey:@"ShowMoonPhase"];
    if (showMoon) {
        moonGlyph = [NSString stringWithFormat:@" %@", FCMoonPhaseGlyph(nowLocal)];
    }

    // v4 iter-229: optional week-progress bar appended inline. Shows
    // "▕<bar>▏" where <bar> is a fractional fill across 14 cells (2
    // per day × 7 days). Default ON so users see the new feature
    // after rebuild; toggle via Show Week Progress menu item.
    if (showUTC) {
        if (!_utcFormatter) {
            _utcFormatter = [[NSDateFormatter alloc] init];
            _utcFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        }
        // UTC always 24h canonical; separator follows user's TimeSeparator pref
        // for visual consistency with the local time beside it.
        _utcFormatter.dateFormat = FCCurrentTimeFormat(NO, showSec);
        NSString *utcStr = [_utcFormatter stringFromDate:nowLocal];
        _localSeg.timeLabel.stringValue = [NSString stringWithFormat:@"%@ %@ · %@ UTC%@%@",
            localBase, localLabel, utcStr, skyGlyph, moonGlyph];
    } else {
        _localSeg.timeLabel.stringValue = [NSString stringWithFormat:@"%@ %@%@%@",
            localBase, localLabel, skyGlyph, moonGlyph];
    }

    // v4 iter-231 / iter-232: week-progress bar in its own NSTextField
    // (weekBarLabel). cellsPerDay computed dynamically from the LOCAL
    // segment width (per user directive iter-232 — "take full advantage
    // of horizontality"). User can still pin a value via
    // WeekProgressCellsPerDay > 0; default 0 = auto-fit width.
    if ([d boolForKey:@"ShowWeekProgress"]) {
        NSInteger cellsPerDay = [d integerForKey:@"WeekProgressCellsPerDay"];
        if (cellsPerDay <= 0) {
            // Auto: estimate mono char width from the bar's font (set
            // in Layout.m to activeFont). Available width = segment
            // width minus side padding (8pt each side) and ▕▏ brackets
            // (~2 chars). Reserve 6 day-separators. Then divide by 7.
            CGFloat segW = _localSeg.bounds.size.width;
            NSFont *barFont = _localSeg.weekBarLabel.font ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
            CGFloat charW = [@"M" sizeWithAttributes:@{NSFontAttributeName: barFont}].width;
            if (charW < 4) charW = 7.0;  // safety floor
            // iter-234: drop margin from 16pt → 4pt (2pt each side)
            // per user directive — make the most of horizontal space.
            NSInteger maxChars = (NSInteger)((segW - 4.0) / charW);
            NSInteger usableForCells = maxChars - 2 - 6;  // brackets + separators
            cellsPerDay = usableForCells / 7;
            if (cellsPerDay < 1) cellsPerDay = 1;
            if (cellsPerDay > 32) cellsPerDay = 32;  // sanity cap
        }
        // v4 iter-233: render with weekend-dimming via attributed string.
        // LocalTheme drives the filled cell color so the bar harmonizes
        // with the LOCAL segment's foreground; FCProgressEmptyColor stays
        // for empties + separators (matches ACTIVE bar conventions).
        const ClockTheme *localTheme = themeForId([d stringForKey:@"LocalTheme"]);
        NSColor *barFilled = [NSColor colorWithRed:localTheme->fg_r green:localTheme->fg_g blue:localTheme->fg_b alpha:1.0];
        NSColor *barEmpty  = FCProgressEmptyColor();
        NSFont *barFont = _localSeg.weekBarLabel.font ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        NSAttributedString *body = FCBuildWeekProgressBarAttributed(nowLocal, (int)cellsPerDay,
                                                                     barFilled, barEmpty, barFont);
        // Wrap with `▕…▏` brackets in the empty-color (subtle frame).
        NSMutableAttributedString *full = [[NSMutableAttributedString alloc] init];
        NSDictionary *frameAttrs = @{NSFontAttributeName: barFont,
                                     NSForegroundColorAttributeName: barEmpty};
        [full appendAttributedString:[[NSAttributedString alloc] initWithString:@"▕" attributes:frameAttrs]];
        [full appendAttributedString:body];
        [full appendAttributedString:[[NSAttributedString alloc] initWithString:@"▏" attributes:frameAttrs]];
        _localSeg.weekBarLabel.attributedStringValue = full;

        // v4 iter-234: day-letter row above the bar — pad with one
        // space on each side so it visually aligns with the bracketed
        // bar below (` <labels> ` matches `▕<cells>▏`).
        NSString *plainLabels = FCBuildWeekDayLabels((int)cellsPerDay);
        NSString *paddedLabels = [NSString stringWithFormat:@" %@ ", plainLabels];
        NSDictionary *labelAttrs = @{NSFontAttributeName: barFont,
                                     NSForegroundColorAttributeName: barFilled};
        _localSeg.weekDayLabelsLabel.attributedStringValue =
            [[NSAttributedString alloc] initWithString:paddedLabels attributes:labelAttrs];

        // v4 iter-234: ISO 8601 week-of-year top-left.
        NSInteger isoWeek = FCISOWeekOfYear(nowLocal);
        _localSeg.weekNumberLabel.stringValue = [NSString stringWithFormat:@"W%02ld", (long)isoWeek];
    } else {
        _localSeg.weekBarLabel.stringValue = @"";
        _localSeg.weekDayLabelsLabel.stringValue = @"";
        _localSeg.weekNumberLabel.stringValue = @"";
    }
    [_localSeg setNeedsLayout:YES];
    _activeSeg.contentLabel.attributedStringValue = FCBuildActiveSegmentContent();
    _nextSeg.contentLabel.attributedStringValue = FCBuildNextSegmentContent();

    // Per-tick resize: markets open/close, content height changes. Cheap —
    // setFrame no-ops when values match.
    [self relayoutThreeSegmentIfNeeded];
}

- (void)tickLegacy {
    NSMutableString *fmt = [NSMutableString string];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL showDate = [d boolForKey:@"ShowDate"];
    NSString *timeFormat = [d stringForKey:@"TimeFormat"];

    BOOL showSec2 = [d boolForKey:@"ShowSeconds"];
    if (showDate) [fmt appendString:FCDateFormatPrefix([d stringForKey:@"DateFormat"])];
    // v4 iter-98: separator chosen via FCCurrentTimeFormat.
    [fmt appendString:FCCurrentTimeFormat([timeFormat isEqualToString:@"12h"], showSec2)];

    if (!_dateFormatter) _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateFormat = fmt;

    NSString *marketId = [d stringForKey:@"SelectedMarket"];
    const ClockMarket *mkt = marketForId(marketId);
    NSDate *now = [NSDate date];
    NSTimeZone *effectiveTz = [NSTimeZone localTimeZone];
    if (strlen(mkt->iana) > 0) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
        if (tz) effectiveTz = tz;
    }
    _dateFormatter.timeZone = effectiveTz;

    NSString *legacyLabel = (strlen(mkt->iana) > 0)
        ? fullTzLabelForIana(mkt->iana, now)
        : fullTzLabelForZone(effectiveTz, now);
    _label.stringValue = [NSString stringWithFormat:@"%@ %@",
        [_dateFormatter stringFromDate:now], legacyLabel];

    if (strlen(mkt->iana) == 0) return;  // local mode — no session label

    SessionState state;
    double progress01;
    long secsToNext;
    computeSessionState(mkt, now, &state, &progress01, &secsToNext);

    NSString *glyph = glyphForState(state);
    NSString *code = [NSString stringWithUTF8String:mkt->code];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];

    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:glyph attributes:@{
            NSFontAttributeName: _sessionLabel.font,
            NSForegroundColorAttributeName: colorForState(state, NULL)}]];

    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *theme = themeForId(themeId);
    NSColor *themeFg = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dim = [NSColor colorWithWhite:0.5 alpha:1.0];

    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@" %@ ", code]
        attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: themeFg}]];

    if (FCStateIsTrading(state)) {  // iter-168
        NSString *bar = buildProgressBar(progress01, 12);
        NSInteger splitIdx = fcProgressBarFullCells(progress01, 12);
        if (splitIdx > (NSInteger)bar.length) splitIdx = bar.length;
        NSMutableAttributedString *barAttr = [[NSMutableAttributedString alloc]
            initWithString:bar attributes:@{NSFontAttributeName: _sessionLabel.font}];
        [barAttr addAttribute:NSForegroundColorAttributeName value:themeFg range:NSMakeRange(0, splitIdx)];
        [barAttr addAttribute:NSForegroundColorAttributeName value:dim range:NSMakeRange(splitIdx, bar.length - splitIdx)];
        [attr appendAttributedString:barAttr];

        NSString *cd = (state == kSessionLunch)
            ? [NSString stringWithFormat:@" LUNCH %@", formatCountdown(secsToNext)]
            : [NSString stringWithFormat:@" %@", formatCountdown(secsToNext)];
        [attr appendAttributedString:[[NSAttributedString alloc]
            initWithString:cd attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: themeFg}]];
    } else {
        // v4 iter-134: state-accurate label. iter-123/125 introduced
        // PRE-MARKET and AFTER-HOURS as distinct states, but this legacy
        // single-market path kept the literal "CLOSED" prefix — the glyph
        // color said one thing, the text said another. Map the state to
        // its word-form now so the two agree.
        // v4 iter-135: state→word mapping lifted to `labelForState` in
        // MarketSessionCalculator (testable, reusable). PRE-MARKET /
        // AFTER-HOURS use their state color; plain CLOSED stays dim.
        NSString *stateWord = labelForState(state);
        NSColor *textColor = (state == kSessionPreMarket || state == kSessionAfterHours)
                              ? colorForState(state, NULL) : dim;
        NSString *countdownText;
        if (secsToNext > kFCMaxBoundedCountdownSecs) {
            NSDate *opensAt = [NSDate dateWithTimeIntervalSinceNow:secsToNext];
            NSDateFormatter *openFmt = [[NSDateFormatter alloc] init];
            openFmt.dateFormat = @"EEE HH:mm";
            NSTimeZone *mktTz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
            if (mktTz) openFmt.timeZone = mktTz;
            NSString *label = fullTzLabelForIana(mkt->iana, opensAt);
            countdownText = [NSString stringWithFormat:@" %@ · opens %@ %@",
                stateWord, [openFmt stringFromDate:opensAt], label];
        } else {
            countdownText = [NSString stringWithFormat:@" %@ · opens in %@",
                stateWord, formatCountdown(secsToNext)];
        }
        [attr appendAttributedString:[[NSAttributedString alloc]
            initWithString:countdownText attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: textColor}]];
    }

    _sessionLabel.attributedStringValue = attr;
}

#pragma mark - Positioning

// Primary display = screens[0] (with menu bar at origin). mainScreen is
// indeterminate for LSUIElement apps before a window is key.
- (NSScreen *)primaryScreen {
    NSArray<NSScreen *> *all = [NSScreen screens];
    if (all.count > 0) return all.firstObject;
    return [NSScreen mainScreen];
}

- (NSRect)defaultFrame {
    NSScreen *s = [self primaryScreen];
    NSRect vf = s.visibleFrame;
    NSRect f = self.frame;
    CGFloat x = vf.origin.x + (vf.size.width - f.size.width) / 2.0;
    CGFloat y = vf.origin.y + 24;
    return NSMakeRect(x, y, f.size.width, f.size.height);
}

- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed {
    NSScreen *s = self.screen ?: [self primaryScreen];
    NSRect vf = s.visibleFrame;
    NSRect r = proposed;
    if (r.size.width > vf.size.width)  r.size.width  = vf.size.width;
    if (r.size.height > vf.size.height) r.size.height = vf.size.height;
    if (NSMaxX(r) > NSMaxX(vf)) r.origin.x = NSMaxX(vf) - r.size.width;
    if (NSMaxY(r) > NSMaxY(vf)) r.origin.y = NSMaxY(vf) - r.size.height;
    if (r.origin.x < vf.origin.x) r.origin.x = vf.origin.x;
    if (r.origin.y < vf.origin.y) r.origin.y = vf.origin.y;
    return r;
}

- (void)windowDidMove:(NSNotification *)n {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:NSStringFromRect(self.frame) forKey:@"FloatingClockWindowFrame"];
    NSNumber *sn = self.screen.deviceDescription[@"NSScreenNumber"];
    if ([sn isKindOfClass:[NSNumber class]]) {
        [d setObject:sn forKey:@"FloatingClockScreenNumber"];
    }
}

- (void)restorePosition {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *frameStr = [d stringForKey:@"FloatingClockWindowFrame"];
    NSNumber *savedScreenNum = [d objectForKey:@"FloatingClockScreenNumber"];

    if ([frameStr isKindOfClass:[NSString class]] && frameStr.length > 0 &&
        [savedScreenNum isKindOfClass:[NSNumber class]]) {
        NSRect r = NSRectFromString(frameStr);
        if (r.size.width > 20 && r.size.height > 20) {
            for (NSScreen *s in [NSScreen screens]) {
                NSNumber *n = s.deviceDescription[@"NSScreenNumber"];
                if ([n isKindOfClass:[NSNumber class]] && [n isEqualToNumber:savedScreenNum]) {
                    if (NSIntersectsRect(r, s.frame)) {
                        [self setFrame:r display:NO];
                        return;
                    }
                    NSRect vf = s.visibleFrame;
                    NSRect clamped = r;
                    clamped.origin.x = MAX(vf.origin.x, MIN(r.origin.x, NSMaxX(vf) - r.size.width));
                    clamped.origin.y = MAX(vf.origin.y, MIN(r.origin.y, NSMaxY(vf) - r.size.height));
                    [self setFrame:clamped display:NO];
                    return;
                }
            }
        }
    }
    [self setFrame:[self defaultFrame] display:NO];
}

- (void)screensChanged:(NSNotification *)n {
    BOOL onLiveScreen = NO;
    for (NSScreen *s in [NSScreen screens]) {
        if (NSIntersectsRect(self.frame, s.frame)) { onLiveScreen = YES; break; }
    }
    if (!onLiveScreen) {
        [self setFrame:[self defaultFrame] display:YES animate:YES];
        NSNumber *sn = [self primaryScreen].deviceDescription[@"NSScreenNumber"];
        if ([sn isKindOfClass:[NSNumber class]]) {
            [[NSUserDefaults standardUserDefaults] setObject:sn forKey:@"FloatingClockScreenNumber"];
        }
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(self.frame)
                                                  forKey:@"FloatingClockWindowFrame"];
    }
}

@end
