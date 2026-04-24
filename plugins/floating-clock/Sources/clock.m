#import <Cocoa/Cocoa.h>

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

// Color theme definition
typedef struct {
    const char *id;              // NSUserDefaults value, e.g. "terminal"
    const char *display;         // Menu label, e.g. "Terminal"
    double fg_r, fg_g, fg_b;     // 0.0–1.0
    double bg_r, bg_g, bg_b;     // 0.0–1.0
    double alpha;                // 0.0–1.0
} ClockTheme;

static const ClockTheme kThemes[] = {
    {"terminal",      "Terminal",       1.00, 1.00, 1.00,  0.00, 0.00, 0.00, 0.32},
    {"amber_crt",     "Amber CRT",      1.00, 0.75, 0.00,  0.00, 0.00, 0.00, 0.38},
    {"green_phosphor","Green Phosphor", 0.18, 0.98, 0.36,  0.00, 0.00, 0.00, 0.35},
    {"solarized_dark","Solarized Dark", 0.71, 0.54, 0.00,  0.00, 0.17, 0.21, 0.40},
    {"dracula",       "Dracula",        0.74, 0.58, 0.98,  0.16, 0.16, 0.21, 0.45},
    {"nord",          "Nord",           0.53, 0.75, 0.82,  0.18, 0.20, 0.25, 0.45},
    {"gruvbox",       "Gruvbox",        0.98, 0.74, 0.18,  0.16, 0.16, 0.16, 0.42},
    {"rose_pine",     "Rose Pine",      0.92, 0.74, 0.73,  0.10, 0.09, 0.15, 0.42},
    {"high_contrast", "High Contrast",  1.00, 1.00, 1.00,  0.00, 0.00, 0.00, 1.00},
    {"soft_glass",    "Soft Glass",     0.96, 0.96, 0.97,  0.00, 0.00, 0.00, 0.18},
};
static const size_t kNumThemes = sizeof(kThemes) / sizeof(kThemes[0]);

// Market/exchange definition with IANA timezone
typedef struct {
    const char *id;               // NSUserDefaults value, e.g. "nyse"
    const char *display;          // Menu label, e.g. "NYSE/NASDAQ (New York)"
    const char *code;             // Short code for status line (iter-9), e.g. "NYSE"
    const char *iana;             // IANA timezone, e.g. "America/New_York"
    int open_h, open_m;           // Regular session open in local time
    int close_h, close_m;         // Regular session close
    int lunch_start_h, lunch_start_m; // -1, -1 if no lunch break
    int lunch_end_h, lunch_end_m;     // -1, -1 if no lunch break
} ClockMarket;

static const ClockMarket kMarkets[] = {
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
static const size_t kNumMarkets = sizeof(kMarkets) / sizeof(kMarkets[0]);

// Lookup market by id; returns first market (local) if not found
static const ClockMarket *marketForId(NSString *idStr) {
    if (!idStr) return &kMarkets[0];  // local
    const char *c = idStr.UTF8String;
    for (size_t i = 0; i < kNumMarkets; i++) {
        if (strcmp(kMarkets[i].id, c) == 0) return &kMarkets[i];
    }
    return &kMarkets[0];
}

// Lookup theme by id; returns first theme if not found
static const ClockTheme *themeForId(NSString *idStr) {
    if (!idStr) return &kThemes[0];
    const char *cstr = idStr.UTF8String;
    for (size_t i = 0; i < kNumThemes; i++) {
        if (strcmp(kThemes[i].id, cstr) == 0) return &kThemes[i];
    }
    return &kThemes[0];  // fallback to first theme (terminal)
}

// Session state values
typedef enum {
    kSessionOpen = 0,        // regular session (including pre-open auctions)
    kSessionLunch = 1,       // midday break on Asian exchanges
    kSessionClosed = 2,      // overnight, weekend
} SessionState;

// Computes session state + progress + secs to next transition for the given market at `now`.
// `progress01` is 0.0–1.0 representing how far through the regular session we are.
// `secs_to_next` is seconds until the next boundary (close if open; open if closed/lunch).
static void computeSessionState(const ClockMarket *mkt, NSDate *now,
                                 SessionState *outState, double *outProgress01,
                                 long *outSecsToNext) {
    if (strlen(mkt->iana) == 0) {
        // Local — not applicable. Caller should not call this for local.
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

    // Weekday: 1=Sunday, 2=Monday, ..., 7=Saturday (Gregorian default)
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

    // Progress: 0.0 at open, 1.0 at close (straight-line, ignoring lunch for simplicity).
    double progress = 0.0;
    if (state == kSessionOpen || state == kSessionLunch) {
        double elapsed = (double)(nowMins - openMins);
        double total = (double)(closeMins - openMins);
        if (total > 0) progress = MIN(1.0, MAX(0.0, elapsed / total));
    } else if (nowMins >= closeMins) {
        progress = 1.0;
    }

    // Seconds to next boundary.
    NSInteger nextBoundaryMins;
    if (state == kSessionClosed) {
        // Next open — today if pre-session, tomorrow (skipping weekend) if post-session
        if (!isWeekend && nowMins < openMins) {
            nextBoundaryMins = openMins;
        } else {
            // Next trading day's open. Find days_until_next_trading_day.
            int addDays = 1;
            NSInteger nextWeekday = ((comps.weekday) % 7) + 1;  // tomorrow's weekday
            while (nextWeekday == 1 || nextWeekday == 7) {      // skip Sat(7) and Sun(1)
                addDays++;
                nextWeekday = (nextWeekday % 7) + 1;
            }
            // Minutes from now to end-of-today + addDays full days + open time
            nextBoundaryMins = (24 * 60 - nowMins) + (addDays - 1) * 24 * 60 + openMins;
        }
    } else if (state == kSessionLunch) {
        nextBoundaryMins = lunchEndMins - nowMins;
    } else {
        // Open — time to close (if there's a lunch between now and close, still count toward close
        // to match user mental model of "session end")
        nextBoundaryMins = closeMins - nowMins;
    }
    long secsToNext = nextBoundaryMins * 60L - comps.second;
    if (secsToNext < 0) secsToNext = 0;

    if (outState) *outState = state;
    if (outProgress01) *outProgress01 = progress;
    if (outSecsToNext) *outSecsToNext = secsToNext;
}

// Format countdown in human-readable form: "5s", "47m", "2h17m"
static NSString *formatCountdown(long secs) {
    if (secs < 60) return [NSString stringWithFormat:@"%lds", secs];
    long mins = secs / 60;
    if (mins < 60) return [NSString stringWithFormat:@"%ldm", mins];
    long hours = mins / 60;
    long rmins = mins % 60;
    if (hours < 100) return [NSString stringWithFormat:@"%ldh%02ldm", hours, rmins];
    // >99h — return special placeholder; caller will swap in a date format
    return [NSString stringWithFormat:@"%ldh", hours];
}

// Returns a fixed-length bar string (totalCells chars) with filled portion
// proportional to progress01. Uses 1/8-width block increments for smoothness.
static NSString *buildProgressBar(double progress01, int totalCells) {
    if (progress01 < 0) progress01 = 0;
    if (progress01 > 1) progress01 = 1;
    double totalEighths = progress01 * totalCells * 8.0;
    int fullCells = (int)(totalEighths / 8);
    int remainderEighths = ((int)totalEighths) % 8;

    // Partial cell glyphs — ordered from 1/8 to 7/8 width from LEFT
    // U+258F (1/8), U+258E (2/8), ... U+2589 (7/8), U+2588 (full)
    NSString *partials[] = {@"", @"▏", @"▎", @"▍", @"▌", @"▋", @"▊", @"▉"};

    NSMutableString *bar = [NSMutableString string];
    for (int i = 0; i < fullCells && i < totalCells; i++) [bar appendString:@"█"];
    if (fullCells < totalCells && remainderEighths > 0) {
        [bar appendString:partials[remainderEighths]];
        fullCells++;
    }
    // Pad remainder with dim fill character
    for (int i = fullCells; i < totalCells; i++) [bar appendString:@"░"];
    return bar;
}

static NSString *glyphForState(SessionState s) {
    switch (s) {
        case kSessionOpen:    return @"●";
        case kSessionLunch:   return @"◑";
        case kSessionClosed:  return @"○";
    }
    return @"○";
}

// Short 3-letter city codes for the ACTIVE segment headers.
// IANA zone → city code mapping.
static const char *cityCodeForIana(const char *iana) {
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
    // Fallback: last 3 chars of IANA city portion, uppercased
    static char fallback[4];
    const char *slash = strrchr(iana, '/');
    if (slash && strlen(slash + 1) >= 3) {
        fallback[0] = toupper(slash[1]);
        fallback[1] = toupper(slash[2]);
        fallback[2] = toupper(slash[3]);
        fallback[3] = 0;
        return fallback;
    }
    return "???";
}

static NSColor *colorForState(SessionState s, const ClockTheme *theme) {
    switch (s) {
        case kSessionOpen:    return [NSColor colorWithRed:0.20 green:0.95 blue:0.40 alpha:1.0];  // green
        case kSessionLunch:   return [NSColor colorWithRed:0.80 green:0.55 blue:0.95 alpha:1.0];  // violet
        case kSessionClosed:  return [NSColor colorWithWhite:0.55 alpha:1.0];                    // dim gray
    }
    return [NSColor whiteColor];
}

// Generate 14×14 color swatch: bg + fg inner square
static NSImage *swatchForTheme(const ClockTheme *t) {
    NSSize sz = NSMakeSize(14, 14);
    NSImage *img = [[NSImage alloc] initWithSize:sz];
    [img lockFocus];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 12, 12)
                                                       xRadius:3 yRadius:3];
    [[NSColor colorWithRed:t->bg_r green:t->bg_g blue:t->bg_b alpha:1.0] setFill];
    [p fill];
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3, 3, 8, 8)
                                                           xRadius:2 yRadius:2];
    [[NSColor colorWithRed:t->fg_r green:t->fg_g blue:t->fg_b alpha:1.0] setFill];
    [inner fill];
    [img unlockFocus];
    img.template = NO;  // never treat as template — we want actual colors
    return img;
}

// Resolve clock font: user override → iTerm2 default profile → SF Mono → Menlo
static NSFont *resolveClockFont(CGFloat size) {
    // 1. User override: NSUserDefaults "FontName" (future customization)
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"FontName"];
    if ([override isKindOfClass:[NSString class]] && override.length > 0) {
        NSFont *f = [NSFont fontWithName:override size:size];
        if (f) return f;
    }

    // 2. iTerm2 default profile
    NSString *plist = [NSHomeDirectory() stringByAppendingPathComponent:
                       @"Library/Preferences/com.googlecode.iterm2.plist"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:plist];
    if ([prefs isKindOfClass:[NSDictionary class]]) {
        NSArray *bookmarks = prefs[@"New Bookmarks"];
        NSString *defaultGuid = prefs[@"Default Bookmark Guid"];
        NSDictionary *chosen = nil;

        if ([bookmarks isKindOfClass:[NSArray class]]) {
            for (NSDictionary *bm in bookmarks) {
                if (![bm isKindOfClass:[NSDictionary class]]) continue;
                NSString *guid = bm[@"Guid"];
                if ([guid isKindOfClass:[NSString class]] && defaultGuid &&
                    [guid isEqualToString:defaultGuid]) {
                    chosen = bm;
                    break;
                }
            }
            // Fallback to first bookmark if default not found
            if (!chosen && bookmarks.count > 0) {
                NSDictionary *first = bookmarks[0];
                if ([first isKindOfClass:[NSDictionary class]]) {
                    chosen = first;
                }
            }
        }

        if ([chosen isKindOfClass:[NSDictionary class]]) {
            NSString *spec = chosen[@"Normal Font"];
            if ([spec isKindOfClass:[NSString class]] && spec.length > 0) {
                // spec format: "FontName 12" → extract FontName
                NSRange r = [spec rangeOfString:@" " options:NSBackwardsSearch];
                NSString *name = (r.location != NSNotFound) ? [spec substringToIndex:r.location] : spec;
                NSFont *f = [NSFont fontWithName:name size:size];
                if (f) return f;
            }
        }
    }

    // 3. System monospaced fallback (SF Mono on Catalina+)
    if (@available(macOS 10.15, *)) {
        return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightMedium];
    }

    // 4. Pre-Catalina fallback (Menlo)
    NSFont *menlo = [NSFont fontWithName:@"Menlo-Regular" size:size];
    return menlo ?: [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
}

// Custom content view that handles right-click menu
@interface ClockContentView : NSView <NSMenuDelegate>
@property (weak) FloatingClockPanel *panel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

// Three-segment NSView subclasses for iter-11 three-segment layout
@interface LocalSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *timeLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface ActiveSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

@interface NextSegmentView : NSView
@property (weak) FloatingClockPanel *panel;
@property (strong) NSTextField *contentLabel;
- (NSMenu *)menuForEvent:(NSEvent *)event;
@end

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
- (void)applyThreeSegmentLayout;
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
- (NSMenu *)buildLocalSegmentMenu;
- (NSMenu *)buildActiveSegmentMenu;
- (NSMenu *)buildNextSegmentMenu;
- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field;
- (void)showFullPreferences:(id)sender;
- (void)resetPosition:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;
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
        @"ShowDate": @NO,
        @"TimeFormat": @"24h",
        @"FontSize": @24.0,
        @"SelectedMarket": @"local",
        @"DisplayMode": @"three-segment",
        @"LocalTheme": @"terminal",
        @"ActiveTheme": @"green_phosphor",
        @"NextTheme": @"soft_glass",
        @"ActiveBarCells": @7,
        @"NextItemCount": @3,
    }];

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

    // Custom content view for menu support
    ClockContentView *cv = [[ClockContentView alloc] initWithFrame:defaultFrame];
    cv.wantsLayer = YES;
    cv.layer.cornerRadius = 10.0;
    cv.layer.masksToBounds = YES;
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
    BOOL showSeconds = [d boolForKey:@"ShowSeconds"];
    NSString *tf = [d stringForKey:@"TimeFormat"];

    if (showDate) [fmt appendString:@"EEE MMM d  "];
    if ([tf isEqualToString:@"12h"]) {
        [fmt appendString:showSeconds ? @"h:mm:ss a" : @"h:mm a"];
    } else {
        [fmt appendString:showSeconds ? @"HH:mm:ss" : @"HH:mm"];
    }

    if (!_dateFormatter) _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.dateFormat = fmt;
    _dateFormatter.timeZone = [NSTimeZone localTimeZone];  // LOCAL segment is always local

    _localSeg.timeLabel.stringValue = [_dateFormatter stringFromDate:[NSDate date]];
    _activeSeg.contentLabel.attributedStringValue = [self buildActiveSegmentContent];
    _nextSeg.contentLabel.attributedStringValue = [self buildNextSegmentContent];
}

- (NSAttributedString *)buildActiveSegmentContent {
    NSDate *now = [NSDate date];
    NSFont *font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    const ClockTheme *theme = themeForId([d stringForKey:@"ActiveTheme"]);
    NSColor *headerColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dimColor    = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.5];

    // Read configurable bar cells preference
    NSInteger barCells = [d integerForKey:@"ActiveBarCells"];
    if (barCells <= 0) barCells = 7;

    // First pass: find active markets grouped by IANA.
    // Each group entry: @[@(marketIndex), @(state), @(progress), @(secsToNext), ...]
    NSMutableArray<NSMutableArray *> *groups = [NSMutableArray array];
    NSMutableArray<NSString *> *groupIanas = [NSMutableArray array];

    for (size_t i = 1; i < kNumMarkets; i++) {  // skip local at index 0
        const ClockMarket *m = &kMarkets[i];
        SessionState state;
        double progress;
        long secsToNext;
        computeSessionState(m, now, &state, &progress, &secsToNext);
        if (state == kSessionOpen || state == kSessionLunch) {
            // Find or create group for this IANA
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
                // Append to existing group (preserve 4-value tuple structure)
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

        // Header: "TOK 11:15"
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:iana];
        NSDateFormatter *hf = [[NSDateFormatter alloc] init];
        hf.dateFormat = @"HH:mm";
        if (tz) hf.timeZone = tz;
        NSString *headerTime = [hf stringFromDate:now];
        const ClockMarket *firstM = &kMarkets[[(NSNumber *)group[0] intValue]];
        const char *cityCode = cityCodeForIana(firstM->iana);

        NSString *headerLine = [NSString stringWithFormat:@"%s %@\n", cityCode, headerTime];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:headerLine
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

        // Per-market lines
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

            // "  ● NYSE ████▒░░ 2h17m\n"
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"  "
                attributes:@{NSFontAttributeName: font}]];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:glyph
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: glyphColor}]];
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@" %-4s ", [code UTF8String]]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

            // Bar with color split
            NSColor *fillColor = glyphColor;  // same color as state glyph
            NSColor *emptyColor = [NSColor colorWithWhite:0.3 alpha:1.0];
            NSInteger splitIdx = 0;
            for (NSUInteger bi = 0; bi < bar.length; bi++) {
                if ([bar characterAtIndex:bi] == 0x2591) { splitIdx = bi; break; }
                splitIdx = bi + 1;
            }
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

        // Blank line between groups
        if (g < groups.count - 1) {
            [out appendAttributedString:[[NSAttributedString alloc]
                initWithString:@"\n"
                attributes:@{NSFontAttributeName: font}]];
        }
    }

    return out;
}

- (NSAttributedString *)buildNextSegmentContent {
    NSDate *now = [NSDate date];
    NSFont *font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    const ClockTheme *theme = themeForId([d stringForKey:@"NextTheme"]);
    NSColor *headerColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
    NSColor *dimColor    = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.5];
    NSColor *codeColor   = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:0.75];

    // Read configurable item count preference
    NSInteger maxN = [d integerForKey:@"NextItemCount"];
    if (maxN <= 0) maxN = 3;

    // Candidate entry: market pointer + state + secs-to-next + is-lunch-resume flag
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
            // Will open next at its next regular-session open.
            entries[entryCount++] = (NextEntry){m, secsToNext, NO};
        } else if (state == kSessionLunch) {
            // Currently on lunch — will resume soon. secsToNext from computeSessionState
            // is seconds until lunch ends (resume time).
            entries[entryCount++] = (NextEntry){m, secsToNext, YES};
        }
        // Skip kSessionOpen — they're already in ACTIVE
    }

    // Sort by secs ascending using insertion sort (small array)
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

    // Header
    [out appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"NEXT TO OPEN\n"
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: headerColor}]];

    // Top N
    int maxItems = entryCount < maxN ? entryCount : (int)maxN;
    for (int i = 0; i < maxItems; i++) {
        NextEntry e = entries[i];
        NSString *glyph = e.isLunchResume ? @"◑" : @"○";
        NSColor *glyphColor = e.isLunchResume
            ? [NSColor colorWithRed:0.80 green:0.55 blue:0.95 alpha:1.0]  // violet
            : [NSColor colorWithWhite:0.55 alpha:1.0];                    // gray
        NSString *code = [NSString stringWithUTF8String:e.mkt->code];
        NSString *countdown;
        if (e.secs > 99 * 3600) {
            // >99h — show date-like "opens Mon 09:30"
            NSDate *opensAt = [NSDate dateWithTimeIntervalSinceNow:e.secs];
            NSDateFormatter *openFmt = [[NSDateFormatter alloc] init];
            openFmt.dateFormat = @"EEE HH:mm";
            openFmt.timeZone = [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:e.mkt->iana]];
            countdown = [NSString stringWithFormat:@"opens %@", [openFmt stringFromDate:opensAt]];
        } else {
            NSString *verb = e.isLunchResume ? @"resumes in" : @"opens in";
            countdown = [NSString stringWithFormat:@"%@ %@", verb, formatCountdown(e.secs)];
        }
        NSString *suffix = e.isLunchResume ? @" LUNCH" : @"";

        // "  ○ NSE  opens in 1h45m\n"
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:glyph
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: glyphColor}]];
        [out appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@" %-4s ", [code UTF8String]]
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

- (void)tickLegacy {
    // Original iter-9 behavior for single-market and local-only modes
    // Build format string dynamically from current settings
    NSMutableString *fmt = [NSMutableString string];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    BOOL showDate = [d boolForKey:@"ShowDate"];
    NSString *timeFormat = [d stringForKey:@"TimeFormat"];
    BOOL showSeconds = [d boolForKey:@"ShowSeconds"];

    if (showDate) {
        [fmt appendString:@"EEE MMM d  "];
    }

    if ([timeFormat isEqualToString:@"12h"]) {
        [fmt appendString:showSeconds ? @"h:mm:ss a" : @"h:mm a"];
    } else {
        [fmt appendString:showSeconds ? @"HH:mm:ss" : @"HH:mm"];
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
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"DisplayMode"];
    if (!mode) mode = @"three-segment";

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

    // Trigger tick to populate content
    [self tick];

    // Measure segment content to compute sizes
    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    NSFont *primaryFont = resolveClockFont(fontSize);
    NSFont *contentFont = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];

    // Measure placeholder text
    NSDictionary *primaryAttrs = @{NSFontAttributeName: primaryFont};
    NSDictionary *contentAttrs = @{NSFontAttributeName: contentFont};

    NSSize localSize = [@"HH:MM:SS" sizeWithAttributes:primaryAttrs];

    // Measure actual ACTIVE content (may be multi-line)
    NSSize activeSize;
    NSAttributedString *activeAttr = _activeSeg.contentLabel.attributedStringValue;
    if (activeAttr && activeAttr.string.length > 0) {
        activeSize = [activeAttr size];
    } else {
        activeSize = [@"ACTIVE (—)" sizeWithAttributes:contentAttrs];
    }

    // Measure actual NEXT content (may be multi-line)
    NSSize nextSize;
    NSAttributedString *nextAttr = _nextSeg.contentLabel.attributedStringValue;
    if (nextAttr && nextAttr.string.length > 0) {
        nextSize = [nextAttr size];
    } else {
        nextSize = [@"NEXT TO OPEN" sizeWithAttributes:contentAttrs];
    }

    CGFloat localHeight  = ceilf(localSize.height) + 12;
    CGFloat activeHeight = ceilf(activeSize.height) + 12;
    CGFloat nextHeight   = ceilf(nextSize.height) + 12;

    CGFloat segHeight = MAX(MAX(localHeight, activeHeight), nextHeight);

    CGFloat localSegWidth  = ceilf(localSize.width) + 32;
    CGFloat activeSegWidth = ceilf(activeSize.width) + 32;
    CGFloat nextSegWidth   = ceilf(nextSize.width) + 32;

    CGFloat windowWidth  = localSegWidth + 4 + activeSegWidth + 4 + nextSegWidth + 16;  // 4pt gaps + 8pt margins per side
    CGFloat windowHeight = segHeight + 16;

    // Anchor at current window center
    NSRect oldFrame = self.frame;
    CGFloat centerX = oldFrame.origin.x + oldFrame.size.width / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldFrame.size.height / 2.0;
    NSRect newFrame = NSMakeRect(centerX - windowWidth / 2.0, centerY - windowHeight / 2.0, windowWidth, windowHeight);
    [self setFrame:newFrame display:YES animate:NO];

    // Position segments within contentView (origin bottom-left)
    _localSeg.frame = NSMakeRect(8, 8, localSegWidth, segHeight);
    _activeSeg.frame = NSMakeRect(8 + localSegWidth + 4, 8, activeSegWidth, segHeight);
    _nextSeg.frame = NSMakeRect(8 + localSegWidth + 4 + activeSegWidth + 4, 8, nextSegWidth, segHeight);

    // Position text fields within each segment (vertical centering)
    CGFloat localPad = (segHeight - localHeight) / 2.0;
    CGFloat activePad = (segHeight - activeHeight) / 2.0;
    CGFloat nextPad = (segHeight - nextHeight) / 2.0;

    _localSeg.timeLabel.frame = NSMakeRect(8, localPad, localSegWidth - 16, localHeight);
    _activeSeg.contentLabel.frame = NSMakeRect(8, activePad, activeSegWidth - 16, activeHeight);
    _nextSeg.contentLabel.frame = NSMakeRect(8, nextPad, nextSegWidth - 16, nextHeight);

    // Set fonts
    _localSeg.timeLabel.font = primaryFont;
    _activeSeg.contentLabel.font = contentFont;
    _nextSeg.contentLabel.font = contentFont;
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
    seg.layer.backgroundColor = [[NSColor colorWithRed:theme->bg_r green:theme->bg_g blue:theme->bg_b alpha:theme->alpha] CGColor];
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

    // Font Size hierarchical
    [m addItem:[self groupedSubmenuTitled:@"Font Size"
                                    action:@selector(setFontSize:)
                                    groups:@[
        @[@"Small",  @[@[@"10", @10.0], @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0]]],
        @[@"Medium", @[@[@"18", @18.0], @[@"20", @20.0], @[@"22", @22.0], @[@"24", @24.0]]],
        @[@"Large",  @[@[@"28", @28.0], @[@"32", @32.0], @[@"36", @36.0], @[@"42", @42.0]]],
        @[@"Huge",   @[@[@"48", @48.0], @[@"56", @56.0], @[@"64", @64.0]]],
    ]                           defaultsKey:@"FontSize"]];

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

    // Progress Bar Width submenu
    [m addItem:[self submenuTitled:@"Progress Bar Width"
                             action:@selector(setActiveBarCells:)
                              pairs:@[@[@"6 cells", @6], @[@"7 cells", @7], @[@"8 cells", @8],
                                      @[@"10 cells", @10], @[@"12 cells", @12]]
                        defaultsKey:@"ActiveBarCells"]];

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

@end

// LocalSegmentView implementation
@implementation LocalSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.50].CGColor;
    self.layer.cornerRadius = 6.0;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentCenter;
    [self addSubview:label];
    _timeLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self.panel buildLocalSegmentMenu];
}

@end

// ActiveSegmentView implementation
@implementation ActiveSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor colorWithRed:0.02 green:0.08 blue:0.04 alpha:0.50].CGColor;
    self.layer.cornerRadius = 6.0;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentLeft;
    label.usesSingleLineMode = NO;
    label.cell.wraps = NO;
    [label.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    [self addSubview:label];
    _contentLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self.panel buildActiveSegmentMenu];
}

@end

// NextSegmentView implementation
@implementation NextSegmentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.50].CGColor;
    self.layer.cornerRadius = 6.0;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentLeft;
    label.usesSingleLineMode = NO;
    label.cell.wraps = NO;
    [self addSubview:label];
    _contentLabel = label;

    return self;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self.panel buildNextSegmentMenu];
}

@end

// ClockContentView implementation
@implementation ClockContentView

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeOtherMouseDown) {
        return self.menu;
    }
    return [super menuForEvent:event];
}

@end

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
