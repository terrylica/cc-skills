#import <Cocoa/Cocoa.h>
#import "rendering/VerticallyCenteredTextFieldCell.h"
#import "rendering/AttributedStringLayoutMeasurer.h"
#import "rendering/FontResolver.h"
#import "data/ThemeCatalog.h"
#import "data/MarketCatalog.h"
#import "data/MarketSessionCalculator.h"
#import "preferences/FloatingClockStarterProfiles.h"
#import "content/ActiveSegmentContentBuilder.h"
#import "content/NextSegmentContentBuilder.h"
#import "segments/FloatingClockSegmentViews.h"
#import "core/FloatingClockPanel.h"
#import "core/FloatingClockPanel+Layout.h"
#import "menu/FloatingClockPanel+MenuBuilder.h"

// # FILE-SIZE-OK

// Forward declaration
// Forward declarations no longer needed — FloatingClockPanel and ClockContentView
// are now imported from core/FloatingClockPanel.h and segments/FloatingClockSegmentViews.h

// Calculate nanoseconds until next second boundary
static uint64_t nsUntilNextSecond(void) {
    NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
    double frac = t - floor(t);
    return (uint64_t)((1.0 - frac) * NSEC_PER_SEC);
}

// ClockTheme + kThemes + themeForId moved to Sources/data/ThemeCatalog.{h,m}
// ClockMarket + kMarkets + marketForId moved to Sources/data/MarketCatalog.{h,m}

// SessionState enum + computeSessionState + formatCountdown + buildProgressBar
// + glyphForState + colorForState moved to Sources/data/MarketSessionCalculator.{h,m}

// buildStarterProfiles + profileManagedKeys moved to Sources/preferences/FloatingClockStarterProfiles.{h,m}

// Map DateFormat preset id → DateFormatter pattern prefix (includes trailing
// "  " separator before the time). Falls back to "short" if unknown/absent.
static NSString *dateFormatPrefix(NSString *presetId) {
    if ([presetId isEqualToString:@"long"])    return @"EEEE MMMM d  ";    // "Thursday April 23"
    if ([presetId isEqualToString:@"iso"])     return @"yyyy-MM-dd  ";     // "2026-04-23"
    if ([presetId isEqualToString:@"numeric"]) return @"M/d  ";            // "4/23"
    if ([presetId isEqualToString:@"weeknum"]) return @"'Wk' w  ";         // "Wk 17"
    if ([presetId isEqualToString:@"dayofyr"]) return @"'Day' D  ";        // "Day 114"
    return @"EEE MMM d  ";  // default "short": "Thu Apr 23"
}

// cityCodeForIana moved to Sources/data/MarketCatalog.{h,m}

// colorForState moved to Sources/data/MarketSessionCalculator.{h,m}

// swatchForTheme moved to Sources/data/ThemeCatalog.{h,m}

// resolveClockFont moved to Sources/rendering/FontResolver.{h,m}

// ClockContentView + LocalSegmentView + ActiveSegmentView + NextSegmentView
// moved to Sources/segments/FloatingClockSegmentViews.{h,m}

// FloatingClockPanel @interface moved to Sources/core/FloatingClockPanel.h

@implementation FloatingClockPanel

- (instancetype)init {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Migrate from legacy TextColor to ColorTheme BEFORE registerDefaults
    if ([d objectForKey:@"ColorTheme"] == nil) {
        NSString *mapped = @"terminal";
        // Check if legacy TextColor was explicitly set (not a default)
        NSString *legacy = [d objectForKey:@"TextColor"];
        if ([legacy isKindOfClass:[NSString class]]) {
            if ([legacy isEqualToString:@"amber"])      mapped = @"amber_crt";
            else if ([legacy isEqualToString:@"green"]) mapped = @"green_phosphor";
            // cyan/red/white all fall through to "terminal"
        }
        [d setObject:mapped forKey:@"ColorTheme"];
        [d synchronize];
    }

    // Migrate DisplayMode: if not set and SelectedMarket != "local", use "single-market"; else use "three-segment"
    if ([d objectForKey:@"DisplayMode"] == nil) {
        NSString *sel = [d stringForKey:@"SelectedMarket"];
        NSString *mode = @"three-segment";  // default for fresh installs
        if ([sel isKindOfClass:[NSString class]] && ![sel isEqualToString:@"local"]) {
            mode = @"single-market";  // migrate legacy users
        }
        [d setObject:mode forKey:@"DisplayMode"];
        [d synchronize];
    }

    // Register default values for NSUserDefaults (after migration, so if ColorTheme wasn't set, it's now there)
    [d registerDefaults:@{
        @"ShowSeconds": @YES,
        @"ShowDate": @YES,
        @"TimeFormat": @"24h",
        @"FontSize": @24.0,
        @"SelectedMarket": @"local",
        @"DisplayMode": @"three-segment",
        @"LocalTheme": @"terminal",
        @"ActiveTheme": @"green_phosphor",
        @"NextTheme": @"soft_glass",
        @"ActiveBarCells": @7,
        @"NextItemCount": @3,
        @"DateFormat": @"short",
        @"CanvasOpacity": @1.0,
        @"Profiles": buildStarterProfiles(),
        @"ActiveProfile": @"Default",
    }];

    // Ensure Profiles and ActiveProfile are persisted (registerDefaults doesn't persist to disk)
    if ([d objectForKey:@"Profiles"] == nil) {
        [d setObject:buildStarterProfiles() forKey:@"Profiles"];
    }
    if ([d objectForKey:@"ActiveProfile"] == nil) {
        [d setObject:@"Default" forKey:@"ActiveProfile"];
    }
    [d synchronize];

    NSRect defaultFrame = NSMakeRect(0, 0, 140, 50);
    self = [super initWithContentRect:defaultFrame
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) return nil;

    self.level = NSFloatingWindowLevel;
    self.floatingPanel = YES;
    self.becomesKeyOnlyIfNeeded = YES;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    self.hasShadow = YES;
    self.opaque = NO;
    self.titleVisibility = NSWindowTitleHidden;
    // Panel background must be fully clear in three-segment mode — segment
    // views own their own backgrounds. Otherwise the panel's default solid
    // windowBackgroundColor blocks desktop/other-app visibility when
    // CanvasOpacity < 1. (Single-market and local-only modes overwrite this
    // with the theme's bg color.)
    self.backgroundColor = [NSColor clearColor];

    // Custom content view for menu support
    ClockContentView *cv = [[ClockContentView alloc] initWithFrame:defaultFrame];
    cv.wantsLayer = YES;
    cv.layer.cornerRadius = 10.0;
    cv.layer.masksToBounds = YES;
    cv.layer.backgroundColor = [[NSColor clearColor] CGColor];
    cv.panel = self;
    self.contentView = cv;

    // Text field for clock display
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSInsetRect(defaultFrame, 8, 8)];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentCenter;
    label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:label];
    _label = label;

    // Secondary label for session state (hidden in local mode)
    NSTextField *sessionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 8, 200, 16)];
    sessionLabel.editable = NO;
    sessionLabel.selectable = NO;
    sessionLabel.bezeled = NO;
    sessionLabel.drawsBackground = NO;
    sessionLabel.alignment = NSTextAlignmentCenter;
    sessionLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    sessionLabel.hidden = YES;  // default hidden for local mode
    sessionLabel.autoresizingMask = NSViewWidthSizable;
    [cv addSubview:sessionLabel];
    _sessionLabel = sessionLabel;

    // Attach menu to content view
    NSMenu *menu = [self buildMenu];
    cv.menu = menu;
    menu.delegate = cv;

    [self restorePosition];
    [self applyDisplaySettings];
    [self setupTimer];

    // Install ⌘Q global handler; retain the returned observer so we can
    // remove it on terminate — otherwise leaks reports a 32-byte root leak
    // on the _NSLocalEventObserver.
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                        handler:^NSEvent *(NSEvent *e) {
        if ((e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand &&
            [e.charactersIgnoringModifiers isEqualToString:@"q"]) {
            [NSApp terminate:nil];
            return nil;
        }
        return e;
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidMove:)
                                                 name:NSWindowDidMoveNotification
                                               object:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screensChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    return self;
}

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
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"DisplayMode"];
    if ([mode isEqualToString:@"three-segment"]) {
        [self tickThreeSegment];
    } else {
        [self tickLegacy];
    }
}

- (void)tickThreeSegment {
    // Build format for LOCAL segment from user prefs
    NSMutableString *fmt = [NSMutableString string];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL showDate = [d boolForKey:@"ShowDate"];
    NSString *tf = [d stringForKey:@"TimeFormat"];

    // Seconds are always shown — user requires second-level granularity
    // everywhere a time is rendered. ShowSeconds pref is retained only for
    // backward compatibility with the menu toggle; it no longer suppresses
    // seconds in the LOCAL segment.
    if (showDate) [fmt appendString:dateFormatPrefix([d stringForKey:@"DateFormat"])];
    if ([tf isEqualToString:@"12h"]) {
        [fmt appendString:@"h:mm:ss a"];
    } else {
        [fmt appendString:@"HH:mm:ss"];
    }

    if (!_dateFormatter) _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateFormat = fmt;
    _dateFormatter.timeZone = [NSTimeZone localTimeZone];  // LOCAL segment is always local

    _localSeg.timeLabel.stringValue = [_dateFormatter stringFromDate:[NSDate date]];
    _activeSeg.contentLabel.attributedStringValue = FCBuildActiveSegmentContent();
    _nextSeg.contentLabel.attributedStringValue = FCBuildNextSegmentContent();

    // Re-layout whenever content height changes (markets opening/closing across
    // the day, first paint after launch, etc.). Measurement is cheap — one
    // NSLayoutManager pass per segment — and setFrame is a no-op when nothing
    // actually changed, so running this on every tick is safe.
    [self relayoutThreeSegmentIfNeeded];
}

// buildActiveSegmentContent + buildNextSegmentContent converted to C functions
// in Sources/content/{Active,Next}SegmentContentBuilder.{h,m} —
// FCBuildActiveSegmentContent(), FCBuildNextSegmentContent().

- (void)tickLegacy {
    // Original iter-9 behavior for single-market and local-only modes
    // Build format string dynamically from current settings
    NSMutableString *fmt = [NSMutableString string];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    BOOL showDate = [d boolForKey:@"ShowDate"];
    NSString *timeFormat = [d stringForKey:@"TimeFormat"];

    if (showDate) {
        [fmt appendString:dateFormatPrefix([d stringForKey:@"DateFormat"])];
    }

    // Seconds always shown (user spec).
    if ([timeFormat isEqualToString:@"12h"]) {
        [fmt appendString:@"h:mm:ss a"];
    } else {
        [fmt appendString:@"HH:mm:ss"];
    }

    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
    }
    _dateFormatter.dateFormat = fmt;

    // Set timezone based on SelectedMarket
    NSString *marketId = [d stringForKey:@"SelectedMarket"];
    const ClockMarket *mkt = marketForId(marketId);
    NSDate *now = [NSDate date];
    if (strlen(mkt->iana) > 0) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
        if (tz) {
            _dateFormatter.timeZone = tz;
        } else {
            _dateFormatter.timeZone = [NSTimeZone localTimeZone];
        }
    } else {
        _dateFormatter.timeZone = [NSTimeZone localTimeZone];
    }

    _label.stringValue = [_dateFormatter stringFromDate:now];

    // Secondary session line
    if (strlen(mkt->iana) == 0) return;  // local mode — no session label

    SessionState state;
    double progress01;
    long secsToNext;
    computeSessionState(mkt, now, &state, &progress01, &secsToNext);

    NSString *glyph = glyphForState(state);
    NSString *code = [NSString stringWithUTF8String:mkt->code];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];

    // Glyph (colored per state)
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:glyph attributes:@{
            NSFontAttributeName: _sessionLabel.font,
            NSForegroundColorAttributeName: colorForState(state, NULL)}]];

    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *theme = themeForId(themeId);
    NSColor *themeFg = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dim = [NSColor colorWithWhite:0.5 alpha:1.0];

    // " MARKET "
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@" %@ ", code]
        attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: themeFg}]];

    if (state == kSessionOpen || state == kSessionLunch) {
        // Progress bar with color split
        NSString *bar = buildProgressBar(progress01, 12);
        NSInteger splitIdx = 0;
        for (NSUInteger i = 0; i < bar.length; i++) {
            if ([bar characterAtIndex:i] == 0x2591) { splitIdx = i; break; }
            splitIdx = i + 1;
        }
        NSMutableAttributedString *barAttr = [[NSMutableAttributedString alloc]
            initWithString:bar attributes:@{NSFontAttributeName: _sessionLabel.font}];
        [barAttr addAttribute:NSForegroundColorAttributeName value:themeFg range:NSMakeRange(0, splitIdx)];
        [barAttr addAttribute:NSForegroundColorAttributeName value:dim range:NSMakeRange(splitIdx, bar.length - splitIdx)];
        [attr appendAttributedString:barAttr];

        // Countdown
        NSString *cd = (state == kSessionLunch)
            ? [NSString stringWithFormat:@" LUNCH %@", formatCountdown(secsToNext)]
            : [NSString stringWithFormat:@" %@", formatCountdown(secsToNext)];
        [attr appendAttributedString:[[NSAttributedString alloc]
            initWithString:cd attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: themeFg}]];
    } else {
        // CLOSED state
        NSString *countdownText;
        if (secsToNext > 99 * 3600) {
            NSDate *opensAt = [NSDate dateWithTimeIntervalSinceNow:secsToNext];
            NSDateFormatter *openFmt = [[NSDateFormatter alloc] init];
            openFmt.dateFormat = @"EEE HH:mm";
            openFmt.timeZone = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mkt->iana]];
            countdownText = [NSString stringWithFormat:@" CLOSED · opens %@", [openFmt stringFromDate:opensAt]];
        } else {
            countdownText = [NSString stringWithFormat:@" CLOSED · opens in %@", formatCountdown(secsToNext)];
        }
        [attr appendAttributedString:[[NSAttributedString alloc]
            initWithString:countdownText attributes:@{NSFontAttributeName: _sessionLabel.font, NSForegroundColorAttributeName: dim}]];
    }

    _sessionLabel.attributedStringValue = attr;
}

// Primary display = the one at origin (0,0) with the menu bar.
// [NSScreen mainScreen] returns the screen with keyboard focus — indeterminate
// for accessory apps before any window is shown — so we explicitly pick screens[0].
- (NSScreen *)primaryScreen {
    NSArray<NSScreen *> *all = [NSScreen screens];
    if (all.count > 0) return all.firstObject;
    return [NSScreen mainScreen];  // absolute last resort
}

- (NSRect)defaultFrame {
    NSScreen *s = [self primaryScreen];
    NSRect vf = s.visibleFrame;  // excludes menu bar + dock
    NSRect f = self.frame;
    CGFloat x = vf.origin.x + (vf.size.width - f.size.width) / 2.0;
    CGFloat y = vf.origin.y + 24;  // 24pt above Dock / bottom edge
    return NSMakeRect(x, y, f.size.width, f.size.height);
}

// Clamp a proposed frame so no edge extends past the current screen's
// visibleFrame. Used after each layout resize so the window never slips
// below the Dock, above the menu bar, or past the sides. The window's
// current screen is preferred; falls back to primary if unknown.
- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed {
    NSScreen *s = self.screen ?: [self primaryScreen];
    NSRect vf = s.visibleFrame;
    NSRect r = proposed;
    // If window is larger than the screen, prefer anchoring to bottom-left.
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
                    // Saved monitor is still connected
                    if (NSIntersectsRect(r, s.frame)) {
                        [self setFrame:r display:NO];
                        return;
                    }
                    // Screen shrunk / config changed — clamp to visibleFrame
                    NSRect vf = s.visibleFrame;
                    NSRect clamped = r;
                    clamped.origin.x = MAX(vf.origin.x, MIN(r.origin.x, NSMaxX(vf) - r.size.width));
                    clamped.origin.y = MAX(vf.origin.y, MIN(r.origin.y, NSMaxY(vf) - r.size.height));
                    [self setFrame:clamped display:NO];
                    return;
                }
            }
            // Saved screen disconnected — fall through to default
        }
    }
    [self setFrame:[self defaultFrame] display:NO];
}

- (void)screensChanged:(NSNotification *)n {
    // If current window is no longer on any live screen, relocate to default
    BOOL onLiveScreen = NO;
    for (NSScreen *s in [NSScreen screens]) {
        if (NSIntersectsRect(self.frame, s.frame)) {
            onLiveScreen = YES;
            break;
        }
    }
    if (!onLiveScreen) {
        [self setFrame:[self defaultFrame] display:YES animate:YES];
        // Also update saved screen number to primary screen's
        NSNumber *sn = [self primaryScreen].deviceDescription[@"NSScreenNumber"];
        if ([sn isKindOfClass:[NSNumber class]]) {
            [[NSUserDefaults standardUserDefaults] setObject:sn forKey:@"FloatingClockScreenNumber"];
        }
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(self.frame)
                                                  forKey:@"FloatingClockWindowFrame"];
    }
}

#pragma mark - Display Settings

// buildMenu / submenuTitled / groupedSubmenuTitled / setChecksInMenu /
// representedObject:matchesValue: / refreshMenuChecks moved to
// Sources/menu/FloatingClockPanel+MenuBuilder.m

// applyDisplaySettings / applyThreeSegmentLayout / relayoutThreeSegmentIfNeeded /
// applyLocalOnlyLayout / applySingleMarketLayout moved to
// Sources/core/FloatingClockPanel+Layout.{h,m}

/* applyThreeSegmentLayout — moved */

// Re-measure ACTIVE/NEXT content and resize window if it changed. Called
// from tickThreeSegment on every 1Hz update so the clock grows/shrinks as
// markets open and close throughout the day. setFrame is a no-op when
// values match, so this stays cheap.

#pragma mark - Profile Management


- (void)setDateFormat:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"DateFormat"];
        [self applyDisplaySettings];
    }
}


@end

// @implementation blocks for the 4 view classes moved to
// Sources/segments/FloatingClockSegmentViews.m

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        FloatingClockPanel *panel = [[FloatingClockPanel alloc] init];
        [panel makeKeyAndOrderFront:nil];
        [app run];
    }
    return 0;
}
