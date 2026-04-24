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

// # FILE-SIZE-OK

// Forward declaration
@class FloatingClockPanel;
@class ClockContentView;

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

@interface FloatingClockPanel : NSPanel {
    NSTextField *_label;
    NSTextField *_sessionLabel;
    dispatch_source_t _timer;
    NSDateFormatter *_dateFormatter;
    id _keyMonitor;
    LocalSegmentView *_localSeg;
    ActiveSegmentView *_activeSeg;
    NextSegmentView *_nextSeg;
}
- (NSMenu *)buildMenu;
- (void)refreshMenuChecks:(NSMenu *)menu;
- (NSMenuItem *)submenuTitled:(NSString *)title action:(SEL)action pairs:(NSArray *)pairs defaultsKey:(NSString *)key;
- (NSMenuItem *)groupedSubmenuTitled:(NSString *)title action:(SEL)action groups:(NSArray *)groups defaultsKey:(NSString *)key;
- (BOOL)setChecksInMenu:(NSMenu *)menu forKey:(NSString *)key currentValue:(id)current;
- (BOOL)representedObject:(id)ro matchesValue:(id)v;
- (void)applyDisplaySettings;
- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed;
- (void)applyThreeSegmentLayout;
- (void)relayoutThreeSegmentIfNeeded;
- (void)applySingleMarketLayout;
- (void)applyLocalOnlyLayout;
- (void)tickThreeSegment;
- (void)tickLegacy;
- (void)toggleShowSeconds:(NSMenuItem *)sender;
- (void)toggleShowDate:(NSMenuItem *)sender;
- (void)setTimeFormat:(NSMenuItem *)sender;
- (void)setFontSize:(NSMenuItem *)sender;
- (void)setColorTheme:(NSMenuItem *)sender;
- (void)setLocalTheme:(NSMenuItem *)sender;
- (void)setActiveTheme:(NSMenuItem *)sender;
- (void)setNextTheme:(NSMenuItem *)sender;
- (void)setMarket:(NSMenuItem *)sender;
- (void)setDisplayMode:(NSMenuItem *)sender;
- (void)setActiveBarCells:(NSMenuItem *)sender;
- (void)setNextItemCount:(NSMenuItem *)sender;
- (void)setCanvasOpacity:(NSMenuItem *)sender;
- (NSMenu *)buildLocalSegmentMenu;
- (NSMenu *)buildActiveSegmentMenu;
- (NSMenu *)buildNextSegmentMenu;
- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field;
- (void)showFullPreferences:(id)sender;
- (void)resetPosition:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;
- (void)activateProfile:(NSString *)name;
- (void)saveCurrentProfileAs:(id)sender;
- (void)quickSaveCurrentProfile:(id)sender;
- (void)setDateFormat:(NSMenuItem *)sender;
- (void)deleteProfile:(NSMenuItem *)sender;
- (void)switchToProfile:(NSMenuItem *)sender;
- (NSMenuItem *)buildProfileMenu;
- (void)recordProfileActivationInCCMemory:(NSString *)profileName;
@end

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

#pragma mark - Menu Building and Display Settings

- (NSMenu *)buildMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    [m addItemWithTitle:@"Show Seconds" action:@selector(toggleShowSeconds:) keyEquivalent:@""];
    [m addItemWithTitle:@"Show Date" action:@selector(toggleShowDate:) keyEquivalent:@""];

    [m addItem:[NSMenuItem separatorItem]];

    [m addItem:[self buildProfileMenu]];

    [m addItem:[self submenuTitled:@"Time Format" action:@selector(setTimeFormat:)
                              pairs:@[@[@"24-hour", @"24h"], @[@"12-hour", @"12h"]]
                        defaultsKey:@"TimeFormat"]];

    [m addItem:[self groupedSubmenuTitled:@"Font Size"
                                action:@selector(setFontSize:)
                                groups:@[
    @[@"Small",  @[@[@"10", @10.0], @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0]]],
    @[@"Medium", @[@[@"18", @18.0], @[@"20", @20.0], @[@"22", @22.0], @[@"24", @24.0]]],
    @[@"Large",  @[@[@"28", @28.0], @[@"32", @32.0], @[@"36", @36.0], @[@"42", @42.0]]],
    @[@"Huge",   @[@[@"48", @48.0], @[@"56", @56.0], @[@"64", @64.0]]],
]                          defaultsKey:@"FontSize"]];

    // Build Time Zone submenu with regional groups
    NSMutableArray *americasItems = [NSMutableArray array];
    NSMutableArray *europeItems   = [NSMutableArray array];
    NSMutableArray *asiaItems     = [NSMutableArray array];
    NSMutableArray *oceaniaItems  = [NSMutableArray array];

    // Skip index 0 (local — handled separately)
    for (size_t i = 1; i < kNumMarkets; i++) {
        NSString *display = [NSString stringWithUTF8String:kMarkets[i].display];
        NSString *idStr = [NSString stringWithUTF8String:kMarkets[i].id];
        NSArray *pair = @[display, idStr];
        if (i <= 2) {
            [americasItems addObject:pair];      // NYSE, TSX
        } else if (i <= 6) {
            [europeItems addObject:pair];        // LSE, Euronext, XETRA, SIX
        } else if (i <= 11) {
            [asiaItems addObject:pair];          // TSE, HKEX, SSE, KRX, NSE
        } else {
            [oceaniaItems addObject:pair];       // ASX
        }
    }

    // Build root Time Zone submenu manually
    NSMenuItem *tzRoot = [[NSMenuItem alloc] initWithTitle:@"Time Zone" action:nil keyEquivalent:@""];
    NSMenu *tzSub = [[NSMenu alloc] init];

    NSMenuItem *localItem = [tzSub addItemWithTitle:@"Local Time" action:@selector(setMarket:) keyEquivalent:@""];
    localItem.representedObject = @"local";
    localItem.target = self;
    [tzSub addItem:[NSMenuItem separatorItem]];

    // Nested region groups
    for (NSArray *region in @[
        @[@"Americas", americasItems],
        @[@"Europe", europeItems],
        @[@"Asia", asiaItems],
        @[@"Oceania", oceaniaItems]]) {
        NSMenuItem *regionItem = [[NSMenuItem alloc] initWithTitle:region[0] action:nil keyEquivalent:@""];
        NSMenu *regionSub = [[NSMenu alloc] init];
        for (NSArray *pair in region[1]) {
            NSMenuItem *leaf = [regionSub addItemWithTitle:pair[0] action:@selector(setMarket:) keyEquivalent:@""];
            leaf.representedObject = pair[1];
            leaf.target = self;
        }
        regionItem.submenu = regionSub;
        [tzSub addItem:regionItem];
    }

    tzRoot.submenu = tzSub;
    [m addItem:tzRoot];

    // Build Display Mode submenu
    NSMenuItem *displayModeRoot = [[NSMenuItem alloc] initWithTitle:@"Display Mode" action:nil keyEquivalent:@""];
    NSMenu *displayModeSub = [[NSMenu alloc] init];

    NSMenuItem *threeSegItem = [displayModeSub addItemWithTitle:@"Three-Segment" action:@selector(setDisplayMode:) keyEquivalent:@""];
    threeSegItem.representedObject = @"three-segment";
    threeSegItem.target = self;

    NSMenuItem *singleMktItem = [displayModeSub addItemWithTitle:@"Single Market" action:@selector(setDisplayMode:) keyEquivalent:@""];
    singleMktItem.representedObject = @"single-market";
    singleMktItem.target = self;

    NSMenuItem *localOnlyItem = [displayModeSub addItemWithTitle:@"Local Only" action:@selector(setDisplayMode:) keyEquivalent:@""];
    localOnlyItem.representedObject = @"local-only";
    localOnlyItem.target = self;

    displayModeRoot.submenu = displayModeSub;
    [m addItem:displayModeRoot];

    // Build per-segment Color Theme submenus with swatches
    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        NSString *display = [NSString stringWithUTF8String:kThemes[i].display];
        NSString *idStr = [NSString stringWithUTF8String:kThemes[i].id];
        [themePairs addObject:@[display, idStr]];
    }
    [m addItem:[self submenuTitled:@"Color Theme (Local)"
                         action:@selector(setLocalTheme:)
                          pairs:themePairs
                    defaultsKey:@"LocalTheme"]];

    [m addItem:[self submenuTitled:@"Color Theme (Active)"
                         action:@selector(setActiveTheme:)
                          pairs:themePairs
                    defaultsKey:@"ActiveTheme"]];

    [m addItem:[self submenuTitled:@"Color Theme (Next)"
                         action:@selector(setNextTheme:)
                          pairs:themePairs
                    defaultsKey:@"NextTheme"]];

    // Legacy global Color Theme (for non-three-segment modes)
    [m addItem:[self submenuTitled:@"Color Theme (Legacy)"
                         action:@selector(setColorTheme:)
                          pairs:themePairs
                    defaultsKey:@"ColorTheme"]];

    // Decorate all Color Theme items with swatches
    for (NSMenuItem *rootItem in m.itemArray) {
        if (([rootItem.title isEqualToString:@"Color Theme (Local)"] ||
             [rootItem.title isEqualToString:@"Color Theme (Active)"] ||
             [rootItem.title isEqualToString:@"Color Theme (Next)"] ||
             [rootItem.title isEqualToString:@"Color Theme (Legacy)"]) && rootItem.submenu) {
            NSArray *subItems = rootItem.submenu.itemArray;
            for (size_t i = 0; i < subItems.count && i < kNumThemes; i++) {
                [(NSMenuItem *)subItems[i] setImage:swatchForTheme(&kThemes[i])];
            }
        }
    }

    [m addItem:[NSMenuItem separatorItem]];
    [m addItemWithTitle:@"Reset Position" action:@selector(resetPosition:) keyEquivalent:@""];

    [m addItem:[NSMenuItem separatorItem]];
    [m addItemWithTitle:@"About Floating Clock" action:@selector(showAbout:) keyEquivalent:@""];
    NSMenuItem *quitItem = [m addItemWithTitle:@"Quit Floating Clock" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    return m;
}

- (NSMenuItem *)submenuTitled:(NSString *)title action:(SEL)action pairs:(NSArray *)pairs defaultsKey:(NSString *)key {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] init];
    for (NSArray *pair in pairs) {
        NSMenuItem *i = [sub addItemWithTitle:pair[0] action:action keyEquivalent:@""];
        i.representedObject = pair[1];
        i.target = self;
    }
    item.submenu = sub;
    return item;
}

- (NSMenuItem *)groupedSubmenuTitled:(NSString *)title action:(SEL)action groups:(NSArray *)groups defaultsKey:(NSString *)key {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *rootSub = [[NSMenu alloc] init];

    for (NSArray *group in groups) {
        NSString *groupTitle = group[0];
        NSArray *items = group[1];  // array of [label, value] pairs

        NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:groupTitle action:nil keyEquivalent:@""];
        NSMenu *groupSub = [[NSMenu alloc] init];

        for (NSArray *pair in items) {
            NSMenuItem *leaf = [groupSub addItemWithTitle:pair[0] action:action keyEquivalent:@""];
            leaf.representedObject = pair[1];
            leaf.target = self;
        }

        groupItem.submenu = groupSub;
        [rootSub addItem:groupItem];
    }

    root.submenu = rootSub;
    return root;
}

- (BOOL)setChecksInMenu:(NSMenu *)menu forKey:(NSString *)key currentValue:(id)current {
    BOOL anyChecked = NO;
    for (NSMenuItem *item in menu.itemArray) {
        if (item.submenu) {
            BOOL childChecked = [self setChecksInMenu:item.submenu forKey:key currentValue:current];
            // Optionally check the group item itself when one of its children is checked
            item.state = childChecked ? NSControlStateValueMixed : NSControlStateValueOff;
            if (childChecked) anyChecked = YES;
        } else if (item.representedObject) {
            BOOL match = [self representedObject:item.representedObject matchesValue:current];
            item.state = match ? NSControlStateValueOn : NSControlStateValueOff;
            if (match) anyChecked = YES;
        }
    }
    return anyChecked;
}

- (BOOL)representedObject:(id)ro matchesValue:(id)v {
    if ([ro isKindOfClass:[NSNumber class]] && [v isKindOfClass:[NSNumber class]]) {
        return [ro doubleValue] == [v doubleValue];
    }
    return [ro isEqual:v];
}

- (void)refreshMenuChecks:(NSMenu *)menu {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Update toggle items (Show Seconds, Show Date)
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:@"Show Seconds"]) {
            item.state = [d boolForKey:@"ShowSeconds"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Date"]) {
            item.state = [d boolForKey:@"ShowDate"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if (item.submenu) {
            // Update submenu items using recursive helper
            NSString *subTitle = item.title;
            id currentValue = nil;

            if ([subTitle isEqualToString:@"Time Format"]) {
                currentValue = [d stringForKey:@"TimeFormat"];
            } else if ([subTitle isEqualToString:@"Font Size"]) {
                currentValue = [d objectForKey:@"FontSize"];
            } else if ([subTitle isEqualToString:@"Time Zone"]) {
                currentValue = [d stringForKey:@"SelectedMarket"];
            } else if ([subTitle isEqualToString:@"Color Theme (Local)"]) {
                currentValue = [d stringForKey:@"LocalTheme"];
            } else if ([subTitle isEqualToString:@"Color Theme (Active)"]) {
                currentValue = [d stringForKey:@"ActiveTheme"];
            } else if ([subTitle isEqualToString:@"Color Theme (Next)"]) {
                currentValue = [d stringForKey:@"NextTheme"];
            } else if ([subTitle isEqualToString:@"Color Theme (Legacy)"]) {
                currentValue = [d stringForKey:@"ColorTheme"];
            } else if ([subTitle isEqualToString:@"Display Mode"]) {
                currentValue = [d stringForKey:@"DisplayMode"];
            }

            [self setChecksInMenu:item.submenu forKey:subTitle currentValue:currentValue];
        }
    }
}

- (void)applyDisplaySettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *mode = [d stringForKey:@"DisplayMode"];
    if (!mode) mode = @"three-segment";

    // Canvas-only transparency. User directive: text must stay fully
    // opaque, only backgrounds dim. NSWindow.alphaValue is NOT used
    // (that would dim text too). Instead, applyTheme multiplies the
    // theme's bg alpha by CanvasOpacity when setting segment layer
    // backgrounds — text color always rendered at alpha=1.0.
    // Ensure panel.alphaValue is always 1.0 (no whole-window dimming).
    self.alphaValue = 1.0;

    if ([mode isEqualToString:@"three-segment"]) {
        [self applyThreeSegmentLayout];
    } else if ([mode isEqualToString:@"local-only"]) {
        [self applyLocalOnlyLayout];
    } else {
        [self applySingleMarketLayout];
    }
}

- (void)applyThreeSegmentLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Lazily create segment views if not present
    if (!_localSeg) {
        _localSeg = [[LocalSegmentView alloc] initWithFrame:NSZeroRect];
        _localSeg.panel = self;
        [self.contentView addSubview:_localSeg];
    }
    if (!_activeSeg) {
        _activeSeg = [[ActiveSegmentView alloc] initWithFrame:NSZeroRect];
        _activeSeg.panel = self;
        [self.contentView addSubview:_activeSeg];
    }
    if (!_nextSeg) {
        _nextSeg = [[NextSegmentView alloc] initWithFrame:NSZeroRect];
        _nextSeg.panel = self;
        [self.contentView addSubview:_nextSeg];
    }

    // Hide legacy labels
    _label.hidden = YES;
    _sessionLabel.hidden = YES;

    // Update segment visibility
    _localSeg.hidden = NO;
    _activeSeg.hidden = NO;
    _nextSeg.hidden = NO;

    // Apply per-segment themes
    const ClockTheme *tLocal  = themeForId([d stringForKey:@"LocalTheme"]);
    const ClockTheme *tActive = themeForId([d stringForKey:@"ActiveTheme"]);
    const ClockTheme *tNext   = themeForId([d stringForKey:@"NextTheme"]);

    [self applyTheme:tLocal  toSegmentView:_localSeg  textField:_localSeg.timeLabel];
    [self applyTheme:tActive toSegmentView:_activeSeg textField:_activeSeg.contentLabel];
    [self applyTheme:tNext   toSegmentView:_nextSeg   textField:_nextSeg.contentLabel];

    // Trigger tick to populate content (which itself will call
    // relayoutThreeSegmentIfNeeded and do the sizing pass).
    [self tick];
}

// Re-measure ACTIVE/NEXT content and resize window if it changed. Called
// from tickThreeSegment on every 1Hz update so the clock grows/shrinks as
// markets open and close throughout the day. setFrame is a no-op when
// values match, so this stays cheap.
- (void)relayoutThreeSegmentIfNeeded {
    if (!_activeSeg || !_nextSeg || !_localSeg) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    NSFont *primaryFont = resolveClockFont(fontSize);
    NSFont *contentFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSDictionary *primaryAttrs = @{NSFontAttributeName: primaryFont};
    NSDictionary *contentAttrs = @{NSFontAttributeName: contentFont};

    _localSeg.timeLabel.font = primaryFont;
    // Measure LOCAL using the same NSLayoutManager path that VerticallyCenteredTextFieldCell
    // uses for rendering — keeps measurement and render in lockstep so the
    // segment height always has enough slack for glyph ascent/descent at
    // any font size. sizeWithAttributes alone under-reports cap-height for
    // many fonts, causing top-clip at 48pt+.
    NSString *localStr = _localSeg.timeLabel.stringValue.length > 0
        ? _localSeg.timeLabel.stringValue : @"HH:MM:SS";
    NSAttributedString *localAttr = [[NSAttributedString alloc]
        initWithString:localStr attributes:primaryAttrs];
    NSSize localSize = FCMeasureAttributedUnwrapped(localAttr);
    if (localSize.height < 10) {
        localSize = [localStr sizeWithAttributes:primaryAttrs];
    }
    // Add breathing room equal to font lineHeight * 0.3 — covers ascent
    // extensions (caps, diacritics) and descent tail at every font size,
    // so content is never clipped top or bottom.
    localSize.height = ceilf(localSize.height + primaryFont.ascender * 0.3);
    _localSeg.timeLabel.alignment = NSTextAlignmentCenter;
    _localSeg.timeLabel.cell.alignment = NSTextAlignmentCenter;
    _localSeg.timeLabel.usesSingleLineMode = YES;

    NSSize activeSize = FCMeasureAttributedUnwrapped(_activeSeg.contentLabel.attributedStringValue);
    if (activeSize.height < 10) {
        activeSize = [@"ACTIVE (—)" sizeWithAttributes:contentAttrs];
    }

    NSSize nextSize = FCMeasureAttributedUnwrapped(_nextSeg.contentLabel.attributedStringValue);
    if (nextSize.height < 10) {
        nextSize = [@"NEXT TO OPEN" sizeWithAttributes:contentAttrs];
    }

    CGFloat localHeight  = ceilf(localSize.height);
    CGFloat activeHeight = ceilf(activeSize.height);
    CGFloat nextHeight   = ceilf(nextSize.height);

    // Stacked block layout: LOCAL on top spanning full width; ACTIVE + NEXT
    // share the second row. Gives a rectangular, stable silhouette where
    // the LOCAL clock anchors the top and market detail flows below it.
    CGFloat topRowHeight    = localHeight  + 24;
    CGFloat bottomRowHeight = MAX(activeHeight, nextHeight) + 24;

    CGFloat activeSegWidth = ceilf(activeSize.width) + 32;
    CGFloat nextSegWidth   = ceilf(nextSize.width) + 32;
    CGFloat bottomRowInnerWidth = activeSegWidth + 4 + nextSegWidth;

    // LOCAL stretches to whichever is wider: its own content, or the bottom
    // row, so the top and bottom are flush.
    CGFloat topRowWidth = MAX(ceilf(localSize.width) + 32, bottomRowInnerWidth);

    CGFloat windowWidth  = topRowWidth + 16;   // 8pt L+R margins
    CGFloat windowHeight = topRowHeight + 4 + bottomRowHeight + 16; // 4pt inter-row gap, 8pt T+B margins

    NSRect oldFrame = self.frame;
    if (fabs(oldFrame.size.width  - windowWidth)  < 0.5 &&
        fabs(oldFrame.size.height - windowHeight) < 0.5) {
        return;
    }

    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    // contentView origin is bottom-left. Bottom row first (y=8), then top row.
    CGFloat bottomY = 8;
    CGFloat topY    = 8 + bottomRowHeight + 4;

    // LOCAL top row stretches full inner width; centered horizontally inside.
    _localSeg.frame = NSMakeRect(8, topY, topRowWidth, topRowHeight);

    // ACTIVE + NEXT share the bottom row. Center them as a pair under LOCAL
    // so the layout stays visually balanced even when LOCAL is wider.
    CGFloat bottomPairX = 8 + (topRowWidth - bottomRowInnerWidth) / 2.0;
    _activeSeg.frame = NSMakeRect(bottomPairX, bottomY, activeSegWidth, bottomRowHeight);
    _nextSeg.frame   = NSMakeRect(bottomPairX + activeSegWidth + 4, bottomY, nextSegWidth, bottomRowHeight);

    // LOCAL: full-segment frame, VerticallyCenteredTextFieldCell does the centering. Adaptive
    // at any font size. Previous direct-positioning approach sized the
    // frame to sizeWithAttributes height, which is the nominal line height
    // and excludes glyph cap-height extensions above — resulting in the top
    // of the glyphs getting clipped at larger font sizes.
    _localSeg.timeLabel.frame     = NSMakeRect(8, 0, topRowWidth - 16, topRowHeight);
    _activeSeg.contentLabel.frame = NSMakeRect(8, 0, activeSegWidth - 16, bottomRowHeight);
    _nextSeg.contentLabel.frame   = NSMakeRect(8, 0, nextSegWidth - 16, bottomRowHeight);

    _localSeg.timeLabel.font      = primaryFont;
    _activeSeg.contentLabel.font  = contentFont;
    _nextSeg.contentLabel.font    = contentFont;
}

- (void)applyLocalOnlyLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Update label with new font
    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    _label.font = resolveClockFont(fontSize);

    // Apply theme: foreground, background, and alpha atomically
    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *t = themeForId(themeId);
    _label.textColor = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
    self.backgroundColor = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:t->alpha];

    _sessionLabel.hidden = YES;

    // Hide segment views if they exist
    _localSeg.hidden = YES;
    _activeSeg.hidden = YES;
    _nextSeg.hidden = YES;

    // Show legacy labels
    _label.hidden = NO;

    // Measure text to resize window
    [self tick];

    [_label sizeToFit];
    NSSize textSize = _label.frame.size;

    CGFloat w1 = ceilf(textSize.width),  h1 = ceilf(textSize.height);

    CGFloat contentWidth  = w1 + 16;
    CGFloat contentHeight = h1;
    CGFloat windowWidth   = contentWidth + 32;
    CGFloat windowHeight  = contentHeight + 20;

    NSRect oldFrame = self.frame;
    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    // 1-line centered
    _label.frame = NSInsetRect(self.contentView.bounds, 8, 8);
}

- (void)applySingleMarketLayout {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Update label with new font
    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    _label.font = resolveClockFont(fontSize);

    // Apply theme: foreground, background, and alpha atomically
    NSString *themeId = [d stringForKey:@"ColorTheme"];
    const ClockTheme *t = themeForId(themeId);
    _label.textColor = [NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0];
    self.backgroundColor = [NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:t->alpha];

    NSString *marketId = [d stringForKey:@"SelectedMarket"];
    const ClockMarket *mkt = marketForId(marketId);
    BOOL marketMode = (strlen(mkt->iana) > 0);
    _sessionLabel.hidden = !marketMode;

    // Hide segment views if they exist
    _localSeg.hidden = YES;
    _activeSeg.hidden = YES;
    _nextSeg.hidden = YES;

    // Show legacy labels
    _label.hidden = NO;

    // Measure text to resize window
    [self tick];

    [_label sizeToFit];
    NSSize textSize = _label.frame.size;

    NSSize size2 = NSZeroSize;
    if (marketMode) {
        [_sessionLabel sizeToFit];
        size2 = _sessionLabel.frame.size;
    }

    CGFloat w1 = ceilf(textSize.width),  h1 = ceilf(textSize.height);
    CGFloat w2 = ceilf(size2.width),     h2 = ceilf(size2.height);

    CGFloat contentWidth  = MAX(w1, w2) + 16;
    CGFloat contentHeight = marketMode ? (h1 + h2 + 4) : h1;
    CGFloat windowWidth   = contentWidth + 32;
    CGFloat windowHeight  = contentHeight + 20;

    NSRect oldFrame = self.frame;
    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    newFrame = [self clampFrameToVisibleScreen:newFrame];
    [self setFrame:newFrame display:YES animate:NO];

    // Lay out labels within contentView
    if (marketMode) {
        // Secondary label at bottom (macOS origin is bottom-left)
        _sessionLabel.frame = NSMakeRect(16, 10, contentWidth, h2);
        // Primary label above it
        _label.frame = NSMakeRect(16, 10 + h2 + 4, contentWidth, h1);
    } else {
        // 1-line centered
        _label.frame = NSInsetRect(self.contentView.bounds, 8, 8);
    }
}

#pragma mark - Menu Actions

- (void)toggleShowSeconds:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = [d boolForKey:@"ShowSeconds"];
    [d setBool:!cur forKey:@"ShowSeconds"];
    [self applyDisplaySettings];
}

- (void)toggleShowDate:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = [d boolForKey:@"ShowDate"];
    [d setBool:!cur forKey:@"ShowDate"];
    [self applyDisplaySettings];
}

- (void)setTimeFormat:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"TimeFormat"];
        [self applyDisplaySettings];
    }
}

- (void)setFontSize:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"FontSize"];
        [self applyDisplaySettings];
    }
}

- (void)setColorTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ColorTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setLocalTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LocalTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ActiveTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setNextTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"NextTheme"];
        [self applyDisplaySettings];
    }
}

- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field {
    // Canvas-only transparency: multiply the theme bg alpha by CanvasOpacity
    // so ONLY the backgrounds dim. Text always renders at alpha=1.0.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    double op = [d objectForKey:@"CanvasOpacity"] ? [d doubleForKey:@"CanvasOpacity"] : 1.0;
    if (op < 0.10) op = 0.10;
    if (op > 1.00) op = 1.00;
    CGFloat bgAlpha = theme->alpha * op;
    seg.layer.backgroundColor = [[NSColor colorWithRed:theme->bg_r green:theme->bg_g blue:theme->bg_b alpha:bgAlpha] CGColor];
    field.textColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
}

- (void)setMarket:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"SelectedMarket"];
        [self applyDisplaySettings];
    }
}

- (void)setDisplayMode:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"DisplayMode"];
        [self applyDisplaySettings];
    }
}

- (void)setCanvasOpacity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue]
                                                  forKey:@"CanvasOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveBarCells:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"ActiveBarCells"];
        [self applyDisplaySettings];
    }
}

- (void)setNextItemCount:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"NextItemCount"];
        [self applyDisplaySettings];
    }
}

- (NSMenu *)buildLocalSegmentMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    // Theme submenu (10 themes, sets LocalTheme)
    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setLocalTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"LocalTheme"];
    // Decorate with swatches
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    // Show Seconds, Show Date toggles
    NSMenuItem *ss = [m addItemWithTitle:@"Show Seconds" action:@selector(toggleShowSeconds:) keyEquivalent:@""];
    ss.target = self;
    NSMenuItem *sd = [m addItemWithTitle:@"Show Date" action:@selector(toggleShowDate:) keyEquivalent:@""];
    sd.target = self;

    // Time Format submenu
    [m addItem:[self submenuTitled:@"Time Format"
                             action:@selector(setTimeFormat:)
                              pairs:@[@[@"24-hour", @"24h"], @[@"12-hour", @"12h"]]
                        defaultsKey:@"TimeFormat"]];

    // Date Format presets (used when Show Date is on)
    [m addItem:[self submenuTitled:@"Date Format"
                             action:@selector(setDateFormat:)
                              pairs:@[@[@"Short (Thu Apr 23)", @"short"],
                                      @[@"Long (Thursday April 23)", @"long"],
                                      @[@"ISO (2026-04-23)", @"iso"],
                                      @[@"Numeric (4/23)", @"numeric"],
                                      @[@"Week Number (Wk 17)", @"weeknum"],
                                      @[@"Day of Year (Day 114)", @"dayofyr"]]
                        defaultsKey:@"DateFormat"]];

    // Font Size hierarchical
    [m addItem:[self groupedSubmenuTitled:@"Font Size"
                                    action:@selector(setFontSize:)
                                    groups:@[
        @[@"Small",  @[@[@"10", @10.0], @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0]]],
        @[@"Medium", @[@[@"18", @18.0], @[@"20", @20.0], @[@"22", @22.0], @[@"24", @24.0]]],
        @[@"Large",  @[@[@"28", @28.0], @[@"32", @32.0], @[@"36", @36.0], @[@"42", @42.0]]],
        @[@"Huge",   @[@[@"48", @48.0], @[@"56", @56.0], @[@"64", @64.0]]],
    ]                           defaultsKey:@"FontSize"]];

    // Canvas-wide transparency (applies to the entire window, not just LOCAL).
    // Values are NSWindow.alphaValue — 1.0 opaque, 0.10 ghost.
    [m addItem:[self submenuTitled:@"Transparency"
                             action:@selector(setCanvasOpacity:)
                              pairs:@[@[@"Opaque (100%)", @1.0],
                                      @[@"Solid (90%)",   @0.9],
                                      @[@"Glass (75%)",   @0.75],
                                      @[@"Medium (50%)",  @0.5],
                                      @[@"Faint (30%)",   @0.3],
                                      @[@"Ghost (15%)",   @0.15]]
                        defaultsKey:@"CanvasOpacity"]];

    [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self buildProfileMenu]];
    NSMenuItem *qs = [m addItemWithTitle:@"Quick Save Profile" action:@selector(quickSaveCurrentProfile:) keyEquivalent:@"s"];
    qs.target = self;

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fp = [m addItemWithTitle:@"Full Preferences…" action:@selector(showFullPreferences:) keyEquivalent:@""];
    fp.target = self;

    return m;
}

- (NSMenu *)buildActiveSegmentMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    // Theme submenu (10 themes, sets ActiveTheme)
    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setActiveTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"ActiveTheme"];
    // Decorate with swatches
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    // Progress Bar Width submenu — hierarchical Small/Medium/Large/Huge up to 40 cells
    [m addItem:[self groupedSubmenuTitled:@"Progress Bar Width"
                                    action:@selector(setActiveBarCells:)
                                    groups:@[
        @[@"Small",  @[@[@"6 cells", @6], @[@"7 cells", @7], @[@"8 cells", @8], @[@"10 cells", @10]]],
        @[@"Medium", @[@[@"12 cells", @12], @[@"14 cells", @14], @[@"16 cells", @16], @[@"18 cells", @18]]],
        @[@"Large",  @[@[@"20 cells", @20], @[@"24 cells", @24], @[@"28 cells", @28], @[@"32 cells", @32]]],
        @[@"Huge",   @[@[@"36 cells", @36], @[@"40 cells", @40]]],
    ]                          defaultsKey:@"ActiveBarCells"]];

    [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self buildProfileMenu]];
    NSMenuItem *qs = [m addItemWithTitle:@"Quick Save Profile" action:@selector(quickSaveCurrentProfile:) keyEquivalent:@""];
    qs.target = self;

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fp = [m addItemWithTitle:@"Full Preferences…" action:@selector(showFullPreferences:) keyEquivalent:@""];
    fp.target = self;

    return m;
}

- (NSMenu *)buildNextSegmentMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    // Theme submenu (10 themes, sets NextTheme)
    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setNextTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"NextTheme"];
    // Decorate with swatches
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    // Show Count submenu
    [m addItem:[self submenuTitled:@"Show Count"
                             action:@selector(setNextItemCount:)
                              pairs:@[@[@"1", @1], @[@"2", @2], @[@"3", @3], @[@"5", @5]]
                        defaultsKey:@"NextItemCount"]];

    [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self buildProfileMenu]];
    NSMenuItem *qs = [m addItemWithTitle:@"Quick Save Profile" action:@selector(quickSaveCurrentProfile:) keyEquivalent:@""];
    qs.target = self;

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fp = [m addItemWithTitle:@"Full Preferences…" action:@selector(showFullPreferences:) keyEquivalent:@""];
    fp.target = self;

    return m;
}

- (void)showFullPreferences:(id)sender {
    // Show the existing full menu as a popup at current mouse location
    NSMenu *full = [self buildMenu];
    [NSMenu popUpContextMenu:full withEvent:[NSApp currentEvent] forView:self.contentView];
}

- (void)resetPosition:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"FloatingClockWindowFrame"];
    [d removeObjectForKey:@"FloatingClockScreenNumber"];
    [self setFrame:[self defaultFrame] display:YES animate:YES];
}

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Floating Clock";
    alert.informativeText = @"Minimal always-on-top floating desktop clock.\n\nSingle-file Objective-C using NSPanel.\nBinary: ~60 KB.\n\n© 2026 Terry Li";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - Profile Management

- (void)activateProfile:(NSString *)name {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *profiles = [d objectForKey:@"Profiles"];
    if (![profiles isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *profile = profiles[name];
    if (![profile isKindOfClass:[NSDictionary class]]) return;

    // Apply every key from the profile that's in the managed set
    for (NSString *key in profileManagedKeys()) {
        id val = profile[key];
        if (val != nil) {
            [d setObject:val forKey:key];
        }
    }

    [d setObject:name forKey:@"ActiveProfile"];
    [self applyDisplaySettings];

    // Auto-memory integration: append to ~/.claude/projects/.../memory/
    [self recordProfileActivationInCCMemory:name];
}

- (void)saveCurrentProfileAs:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save Profile As";
    alert.informativeText = @"Enter a name for this profile:";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    input.stringValue = @"";
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    NSModalResponse resp = [alert runModal];
    if (resp != NSAlertFirstButtonReturn) return;

    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (name.length == 0) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *profiles = [[d objectForKey:@"Profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in profileManagedKeys()) {
        id val = [d objectForKey:key];
        if (val != nil) snapshot[key] = val;
    }
    profiles[name] = snapshot;
    [d setObject:profiles forKey:@"Profiles"];
    [d setObject:name forKey:@"ActiveProfile"];

    [self recordProfileActivationInCCMemory:name];
    // Rebuild menu so the new profile appears
    self.contentView.menu = [self buildMenu];
}

// Silently overwrite the currently-active profile with current settings.
// No dialog, no prompt — one-click save for the common "remember this" case.
- (void)quickSaveCurrentProfile:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *active = [d stringForKey:@"ActiveProfile"];
    if (!active || active.length == 0) active = @"Default";

    NSMutableDictionary *profiles = [[d objectForKey:@"Profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in profileManagedKeys()) {
        id val = [d objectForKey:key];
        if (val != nil) snapshot[key] = val;
    }
    profiles[active] = snapshot;
    [d setObject:profiles forKey:@"Profiles"];
    [self recordProfileActivationInCCMemory:active];
}

- (void)setDateFormat:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"DateFormat"];
        [self applyDisplaySettings];
    }
}

- (void)deleteProfile:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (![name isKindOfClass:[NSString class]]) return;

    // Refuse to delete the built-in 5 starters and "Default"
    NSSet *protected = [NSSet setWithArray:@[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Watch Party"]];
    if ([protected containsObject:name]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Cannot delete starter profile";
        a.informativeText = [NSString stringWithFormat:@"\"%@\" is a built-in starter and cannot be deleted.", name];
        [a addButtonWithTitle:@"OK"];
        [a runModal];
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *profiles = [[d objectForKey:@"Profiles"] mutableCopy];
    [profiles removeObjectForKey:name];
    [d setObject:profiles forKey:@"Profiles"];

    // If we deleted the active profile, fall back to Default
    NSString *active = [d stringForKey:@"ActiveProfile"];
    if ([active isEqualToString:name]) {
        [self activateProfile:@"Default"];
    }
    self.contentView.menu = [self buildMenu];
}

- (void)switchToProfile:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [self activateProfile:sender.representedObject];
        // Rebuild menu so checkmark moves
        self.contentView.menu = [self buildMenu];
    }
}

- (NSMenuItem *)buildProfileMenu {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Profile" action:nil keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] init];

    NSDictionary *profiles = [[NSUserDefaults standardUserDefaults] objectForKey:@"Profiles"];
    NSString *active = [[NSUserDefaults standardUserDefaults] stringForKey:@"ActiveProfile"];
    NSArray *starters = @[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Watch Party"];

    // Starters first (in defined order)
    for (NSString *name in starters) {
        if (profiles[name] == nil) continue;
        NSMenuItem *item = [sub addItemWithTitle:name action:@selector(switchToProfile:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
        if ([name isEqualToString:active]) item.state = NSControlStateValueOn;
    }

    // Separator if custom profiles exist
    NSMutableArray *customNames = [NSMutableArray array];
    for (NSString *name in profiles.allKeys) {
        if (![starters containsObject:name]) [customNames addObject:name];
    }
    [customNames sortUsingSelector:@selector(compare:)];

    if (customNames.count > 0) {
        [sub addItem:[NSMenuItem separatorItem]];
        for (NSString *name in customNames) {
            NSMenuItem *item = [sub addItemWithTitle:name action:@selector(switchToProfile:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = name;
            if ([name isEqualToString:active]) item.state = NSControlStateValueOn;
        }
    }

    [sub addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveItem = [sub addItemWithTitle:@"Save Current As…" action:@selector(saveCurrentProfileAs:) keyEquivalent:@""];
    saveItem.target = self;

    // Delete submenu (only shows non-starter profiles)
    if (customNames.count > 0) {
        NSMenuItem *delRoot = [[NSMenuItem alloc] initWithTitle:@"Delete…" action:nil keyEquivalent:@""];
        NSMenu *delSub = [[NSMenu alloc] init];
        for (NSString *name in customNames) {
            NSMenuItem *di = [delSub addItemWithTitle:name action:@selector(deleteProfile:) keyEquivalent:@""];
            di.target = self;
            di.representedObject = name;
        }
        delRoot.submenu = delSub;
        [sub addItem:delRoot];
    }

    root.submenu = sub;
    return root;
}

- (void)recordProfileActivationInCCMemory:(NSString *)profileName {
    NSString *memDir = [NSHomeDirectory() stringByAppendingPathComponent:
        @".claude/projects/-Users-terryli-eon-cc-skills/memory"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:memDir isDirectory:&isDir] || !isDir) {
        // Don't create the directory — if it doesn't exist, just skip silently
        return;
    }

    NSString *path = [memDir stringByAppendingPathComponent:@"floating_clock_active_profile.md"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss zzz";
    NSString *now = [fmt stringFromDate:[NSDate date]];

    NSString *content = [NSString stringWithFormat:
        @"---\n"
        @"name: floating_clock_active_profile\n"
        @"description: User's currently-active floating-clock profile (auto-updated by the app on every profile switch)\n"
        @"type: project\n"
        @"---\n"
        @"\n"
        @"## Active Profile\n"
        @"\n"
        @"User's floating-clock is running the **%@** profile as of %@.\n"
        @"\n"
        @"**Why:** set automatically by the floating-clock app whenever the user activates a profile via the right-click menu → Profile → <name>.\n"
        @"**How to apply:** when the user references clock display preferences or asks what their settings are, this file reflects the current state.\n",
        profileName, now];

    NSError *err = nil;
    [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        NSLog(@"[floating-clock] Could not write memory entry: %@", err);
    }

    // Also update MEMORY.md index if it exists (don't create if missing)
    NSString *indexPath = [memDir stringByAppendingPathComponent:@"MEMORY.md"];
    NSString *existing = [NSString stringWithContentsOfFile:indexPath encoding:NSUTF8StringEncoding error:nil];
    if (existing && ![existing containsString:@"floating_clock_active_profile.md"]) {
        NSString *entry = @"\n- [Floating clock active profile](./floating_clock_active_profile.md) — currently-selected clock profile, auto-updated\n";
        NSString *updated = [existing stringByAppendingString:entry];
        [updated writeToFile:indexPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
