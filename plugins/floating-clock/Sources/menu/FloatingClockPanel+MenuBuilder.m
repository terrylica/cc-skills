// Full preferences menu + Profile submenu for FloatingClockPanel.
//
//  - buildMenu           full preferences tree (DISPLAY / THEMES / MARKET /
//                        PROFILE / WINDOW categories)
//  - buildProfileMenu    profile list + save / delete submenus
//
// Segment-scoped menus (LOCAL / ACTIVE / NEXT right-click + 'Full
// Preferences…') live in FloatingClockPanel+SegmentMenus.m (iter-87
// split). Shared NSMenu helpers (submenuTitled / groupedSubmenuTitled
// / setChecksInMenu / representedObject:matchesValue: / refreshMenu
// Checks) live in FloatingClockPanel+MenuHelpers.m (iter-96 split —
// proactive before this file crossed the 500-LoC cap).
#import "../core/FloatingClockPanel.h"
#import "../data/ThemeCatalog.h"
#import "../data/MarketCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"
#import "../preferences/FloatingClockQuickStyles.h"
#import "FloatingClockPanel+MenuHelpers.h"

@implementation FloatingClockPanel (MenuBuilder)

// Helper: wrap the supplied menu items in a top-level submenu titled `title`.
// Each `items` entry is already a fully-formed NSMenuItem. Used by buildMenu
// to assemble the 5 v4 top-level categories.
static NSMenuItem *fcTopCategory(NSString *title, NSArray<NSMenuItem *> *items) {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] init];
    for (NSMenuItem *it in items) {
        if (it) [sub addItem:it];
    }
    root.submenu = sub;
    return root;
}

- (NSMenu *)buildMenu {
    // v4 iter-26: 5 top-level categories replace the former flat menu.
    //   DISPLAY   — toggles + format picks that affect what's rendered
    //   THEMES    — color-theme pickers (per-segment + legacy) with swatches
    //   MARKET    — time-zone picker + date format + display mode
    //   PROFILE   — save/load/switch preset bundles (same as segment menus)
    //   WINDOW    — position reset + about + quit
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    // === DISPLAY ===
    NSMutableArray *displayItems = [NSMutableArray array];

    NSMenuItem *ss = [[NSMenuItem alloc] initWithTitle:@"Show Seconds"
                                                 action:@selector(toggleShowSeconds:) keyEquivalent:@""];
    [displayItems addObject:ss];

    NSMenuItem *sd = [[NSMenuItem alloc] initWithTitle:@"Show Date"
                                                 action:@selector(toggleShowDate:) keyEquivalent:@""];
    [displayItems addObject:sd];

    NSMenuItem *sf = [[NSMenuItem alloc] initWithTitle:@"Show Country Flags"
                                                 action:@selector(toggleShowFlags:) keyEquivalent:@""];
    [displayItems addObject:sf];

    NSMenuItem *su = [[NSMenuItem alloc] initWithTitle:@"Show UTC Reference"
                                                 action:@selector(toggleShowUTCReference:) keyEquivalent:@""];
    [displayItems addObject:su];

    NSMenuItem *sk = [[NSMenuItem alloc] initWithTitle:@"Show Sun/Moon"
                                                 action:@selector(toggleShowSkyState:) keyEquivalent:@""];
    [displayItems addObject:sk];

    NSMenuItem *sp = [[NSMenuItem alloc] initWithTitle:@"Show Progress %"
                                                 action:@selector(toggleShowProgressPercent:) keyEquivalent:@""];
    [displayItems addObject:sp];

    [displayItems addObject:[NSMenuItem separatorItem]];

    [displayItems addObject:[self submenuTitled:@"Time Format" action:@selector(setTimeFormat:)
                                           pairs:@[@[@"24-hour", @"24h"], @[@"12-hour", @"12h"]]
                                     defaultsKey:@"TimeFormat"]];

    // v4 iter-98: time-separator lever. Replaces the `:` between
    // HH/mm/ss tokens with the chosen literal (quoted in UTS#35 form
    // so the formatter treats it as plain text, not a pattern token).
    [displayItems addObject:[self submenuTitled:@"Time Separator"
                                          action:@selector(setTimeSeparator:)
                                           pairs:@[@[@"Colon   (10:37:45)",   @"colon"],
                                                   @[@"Middot  (10·37·45)",   @"middot"],
                                                   @[@"Space   (10 37 45)",   @"space"],
                                                   @[@"Slash   (10/37/45)",   @"slash"],
                                                   @[@"Dash    (10-37-45)",   @"dash"]]
                                     defaultsKey:@"TimeSeparator"]];

    [displayItems addObject:[self groupedSubmenuTitled:@"Font Size"
                                                action:@selector(setFontSize:)
                                                groups:@[
        @[@"Small",  @[@[@"10", @10.0], @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0]]],
        @[@"Medium", @[@[@"18", @18.0], @[@"20", @20.0], @[@"22", @22.0], @[@"24", @24.0]]],
        @[@"Large",  @[@[@"28", @28.0], @[@"32", @32.0], @[@"36", @36.0], @[@"42", @42.0]]],
        @[@"Huge",   @[@[@"48", @48.0], @[@"56", @56.0], @[@"64", @64.0]]],
    ]                                      defaultsKey:@"FontSize"]];

    // v4 iter-88: typographic weight lever. Applies to ACTIVE + NEXT
    // (system monospaced) paths. LOCAL primary uses iTerm2 / named font
    // so weight can't drive it via API — documented limitation.
    [displayItems addObject:[self submenuTitled:@"Font Weight"
                                          action:@selector(setFontWeight:)
                                           pairs:@[@[@"Regular",  @"regular"],
                                                   @[@"Medium",   @"medium"],
                                                   @[@"Semibold", @"semibold"],
                                                   @[@"Bold",     @"bold"],
                                                   @[@"Heavy",    @"heavy"]]
                                     defaultsKey:@"FontWeight"]];

    // v4 iter-94: typographic tracking (letter-spacing) lever.
    // Applied via NSKernAttributeName to ACTIVE + NEXT attributed
    // strings only — LOCAL's plain-text label isn't kerned (would
    // require switching to attributedStringValue, out of scope).
    [displayItems addObject:[self submenuTitled:@"Letter Spacing"
                                          action:@selector(setLetterSpacing:)
                                           pairs:@[@[@"Compact (-1.0)", @"compact"],
                                                   @[@"Tight   (-0.5)", @"tight"],
                                                   @[@"Normal  ( 0.0)", @"normal"],
                                                   @[@"Airy    (+0.5)", @"airy"],
                                                   @[@"Wide    (+1.0)", @"wide"]]
                                     defaultsKey:@"LetterSpacing"]];

    // v4 iter-95: leading (line spacing) lever — vertical rhythm
    // control for multi-line ACTIVE + NEXT segments via
    // NSParagraphStyle.lineSpacing. Values are additive points
    // between line fragments. Default "normal" = 2.0pt.
    [displayItems addObject:[self submenuTitled:@"Line Spacing"
                                          action:@selector(setLineSpacing:)
                                           pairs:@[@[@"Tight  (0pt)", @"tight"],
                                                   @[@"Snug   (1pt)", @"snug"],
                                                   @[@"Normal (2pt)", @"normal"],
                                                   @[@"Loose  (4pt)", @"loose"],
                                                   @[@"Airy   (7pt)", @"airy"]]
                                     defaultsKey:@"LineSpacing"]];

    [displayItems addObject:[self submenuTitled:@"Transparency"
                                          action:@selector(setCanvasOpacity:)
                                           pairs:@[@[@"Opaque (100%)", @1.0],
                                                   @[@"Solid (90%)",   @0.9],
                                                   @[@"Glass (75%)",   @0.75],
                                                   @[@"Medium (50%)",  @0.5],
                                                   @[@"Faint (30%)",   @0.3],
                                                   @[@"Ghost (15%)",   @0.15]]
                                     defaultsKey:@"CanvasOpacity"]];

    // v4 iter-28: segment arrangement presets.
    [displayItems addObject:[self submenuTitled:@"Layout"
                                          action:@selector(setLayoutMode:)
                                           pairs:@[@[@"Local on top (stacked)",    @"stacked-local-top"],
                                                   @[@"Local on bottom (stacked)", @"stacked-local-bottom"],
                                                   @[@"Triptych (single row)",     @"horizontal-triptych"]]
                                     defaultsKey:@"LayoutMode"]];

    // v4 iter-35 + iter-99: 6 density presets — scales inner-row padding.
    [displayItems addObject:[self submenuTitled:@"Density"
                                          action:@selector(setDensity:)
                                           pairs:@[@[@"Ultracompact  (4pt)",  @"ultracompact"],
                                                   @[@"Compact      (12pt)",  @"compact"],
                                                   @[@"Default      (24pt)",  @"default"],
                                                   @[@"Comfortable  (36pt)",  @"comfortable"],
                                                   @[@"Spacious     (48pt)",  @"spacious"],
                                                   @[@"Cavernous    (64pt)",  @"cavernous"]]
                                     defaultsKey:@"Density"]];

    // v4 iter-29 + iter-108: 7 inter-segment gap presets.
    [displayItems addObject:[self submenuTitled:@"Segment Gap"
                                          action:@selector(setSegmentGap:)
                                           pairs:@[@[@"Flush      (0pt)",  @"flush"],
                                                   @[@"Tight      (2pt)",  @"tight"],
                                                   @[@"Snug       (3pt)",  @"snug"],
                                                   @[@"Normal     (4pt)",  @"normal"],
                                                   @[@"Airy       (8pt)",  @"airy"],
                                                   @[@"Spacious  (14pt)",  @"spacious"],
                                                   @[@"Cavernous (24pt)",  @"cavernous"]]
                                     defaultsKey:@"SegmentGap"]];

    // v4 iter-30 + iter-97: 8 corner-style presets (applies to all segments).
    [displayItems addObject:[self submenuTitled:@"Corners"
                                          action:@selector(setCornerStyle:)
                                           pairs:@[@[@"Sharp     (0pt)",  @"sharp"],
                                                   @[@"Hairline  (1pt)",  @"hairline"],
                                                   @[@"Micro     (3pt)",  @"micro"],
                                                   @[@"Rounded   (6pt)",  @"rounded"],
                                                   @[@"Soft     (10pt)",  @"soft"],
                                                   @[@"Squircle (14pt)",  @"squircle"],
                                                   @[@"Jumbo    (22pt)",  @"jumbo"],
                                                   @[@"Pill (half-axis)", @"pill"]]
                                     defaultsKey:@"CornerStyle"]];

    // v4 iter-31 + iter-93: 7 shadow / glow presets.
    [displayItems addObject:[self submenuTitled:@"Shadow"
                                          action:@selector(setShadowStyle:)
                                           pairs:@[@[@"None (flat)",              @"none"],
                                                   @[@"Subtle",                   @"subtle"],
                                                   @[@"Lifted",                   @"lifted"],
                                                   @[@"Glow (theme fg)",           @"glow"],
                                                   @[@"Crisp (pixel-hard)",        @"crisp"],
                                                   @[@"Plinth (dramatic drop)",    @"plinth"],
                                                   @[@"Halo (theme bg bloom)",     @"halo"]]
                                     defaultsKey:@"ShadowStyle"]];

    [m addItem:fcTopCategory(@"Display", displayItems)];

    // === THEMES ===
    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        NSString *display = [NSString stringWithUTF8String:kThemes[i].display];
        NSString *idStr = [NSString stringWithUTF8String:kThemes[i].id];
        [themePairs addObject:@[display, idStr]];
    }
    NSMutableArray *themeItems = [NSMutableArray array];
    [themeItems addObject:[self submenuTitled:@"Top Segment (Local)"
                                        action:@selector(setLocalTheme:)
                                         pairs:themePairs defaultsKey:@"LocalTheme"]];
    [themeItems addObject:[self submenuTitled:@"Active Markets"
                                        action:@selector(setActiveTheme:)
                                         pairs:themePairs defaultsKey:@"ActiveTheme"]];
    [themeItems addObject:[self submenuTitled:@"Next To Open"
                                        action:@selector(setNextTheme:)
                                         pairs:themePairs defaultsKey:@"NextTheme"]];
    [themeItems addObject:[NSMenuItem separatorItem]];
    [themeItems addObject:[self submenuTitled:@"Legacy Global"
                                        action:@selector(setColorTheme:)
                                         pairs:themePairs defaultsKey:@"ColorTheme"]];

    NSMenuItem *themesRoot = fcTopCategory(@"Themes", themeItems);
    // Swatch decoration: each theme submenu's items get an NSImage swatch.
    for (NSMenuItem *item in themesRoot.submenu.itemArray) {
        if (item.submenu) {
            NSArray *leaves = item.submenu.itemArray;
            for (size_t i = 0; i < leaves.count && i < kNumThemes; i++) {
                [(NSMenuItem *)leaves[i] setImage:swatchForTheme(&kThemes[i])];
            }
        }
    }
    [m addItem:themesRoot];

    // === MARKET ===
    NSMutableArray *marketItems = [NSMutableArray array];

    // Time Zone submenu (regional groups).
    NSMutableArray *americasItems = [NSMutableArray array];
    NSMutableArray *europeItems   = [NSMutableArray array];
    NSMutableArray *asiaItems     = [NSMutableArray array];
    NSMutableArray *oceaniaItems  = [NSMutableArray array];
    for (size_t i = 1; i < kNumMarkets; i++) {
        NSString *display = [NSString stringWithUTF8String:kMarkets[i].display];
        NSString *idStr = [NSString stringWithUTF8String:kMarkets[i].id];
        NSArray *pair = @[display, idStr];
        if (i <= 2)        [americasItems addObject:pair];
        else if (i <= 6)   [europeItems addObject:pair];
        else if (i <= 11)  [asiaItems addObject:pair];
        else               [oceaniaItems addObject:pair];
    }
    NSMenuItem *tzRoot = [[NSMenuItem alloc] initWithTitle:@"Time Zone" action:nil keyEquivalent:@""];
    NSMenu *tzSub = [[NSMenu alloc] init];
    NSMenuItem *localItem = [tzSub addItemWithTitle:@"Local Time" action:@selector(setMarket:) keyEquivalent:@""];
    localItem.representedObject = @"local";
    localItem.target = self;
    [tzSub addItem:[NSMenuItem separatorItem]];
    for (NSArray *region in @[@[@"Americas", americasItems], @[@"Europe", europeItems],
                              @[@"Asia", asiaItems], @[@"Oceania", oceaniaItems]]) {
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
    [marketItems addObject:tzRoot];

    // Date Format presets (used by LOCAL when ShowDate=YES).
    [marketItems addObject:[self submenuTitled:@"Date Format"
                                         action:@selector(setDateFormat:)
                                          pairs:@[@[@"Short (Thu Apr 23)", @"short"],
                                                  @[@"Long (Thursday April 23)", @"long"],
                                                  @[@"ISO (2026-04-23)", @"iso"],
                                                  @[@"Numeric (4/23)", @"numeric"],
                                                  @[@"Week Number (Wk 17)", @"weeknum"],
                                                  @[@"Day of Year (Day 114)", @"dayofyr"]]
                                    defaultsKey:@"DateFormat"]];

    [marketItems addObject:[NSMenuItem separatorItem]];

    // Display Mode submenu (three-segment / single-market / local-only).
    NSMenuItem *dmRoot = [[NSMenuItem alloc] initWithTitle:@"Display Mode" action:nil keyEquivalent:@""];
    NSMenu *dmSub = [[NSMenu alloc] init];
    NSMenuItem *threeSeg = [dmSub addItemWithTitle:@"Three-Segment" action:@selector(setDisplayMode:) keyEquivalent:@""];
    threeSeg.representedObject = @"three-segment";  threeSeg.target = self;
    NSMenuItem *singleMkt = [dmSub addItemWithTitle:@"Single Market" action:@selector(setDisplayMode:) keyEquivalent:@""];
    singleMkt.representedObject = @"single-market"; singleMkt.target = self;
    NSMenuItem *localOnly = [dmSub addItemWithTitle:@"Local Only" action:@selector(setDisplayMode:) keyEquivalent:@""];
    localOnly.representedObject = @"local-only";   localOnly.target = self;
    dmRoot.submenu = dmSub;
    [marketItems addObject:dmRoot];

    [m addItem:fcTopCategory(@"Market", marketItems)];

    // === PROFILE ===
    // buildProfileMenu already returns an NSMenuItem titled "Profile" with
    // full submenu machinery — promote it to the top level as-is.
    NSMenuItem *profileItem = [self buildProfileMenu];
    [m addItem:profileItem];

    // === QUICK STYLE === (v4 iter-102)
    // Like Profile but scoped to aesthetic levers only — doesn't touch
    // FontSize, SelectedMarket, DisplayMode, Profiles catalog, etc.
    // Picking a Quick Style sets 6-8 prefs atomically to evoke a mood.
    [m addItem:[self buildQuickStylesMenu]];

    // === WINDOW ===
    NSMutableArray *windowItems = [NSMutableArray array];
    // v4 iter-85: clipboard snapshot — quick share of current state.
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy Clock State"
                                                       action:@selector(copyStateToClipboard:) keyEquivalent:@"c"];
    copyItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [windowItems addObject:copyItem];
    [windowItems addObject:[NSMenuItem separatorItem]];
    [windowItems addObject:[[NSMenuItem alloc] initWithTitle:@"Reset Position"
                                                       action:@selector(resetPosition:) keyEquivalent:@""]];
    // v4 iter-109: restore aesthetic levers to registered defaults
    // without touching SelectedMarket / DisplayMode / ActiveProfile /
    // Profiles / FontName / window frame — user's workflow stays put.
    [windowItems addObject:[[NSMenuItem alloc] initWithTitle:@"Reset Visual Style"
                                                       action:@selector(resetVisualStyle:) keyEquivalent:@""]];
    [windowItems addObject:[NSMenuItem separatorItem]];
    [windowItems addObject:[[NSMenuItem alloc] initWithTitle:@"About Floating Clock"
                                                       action:@selector(showAbout:) keyEquivalent:@""]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Floating Clock"
                                                       action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [windowItems addObject:quitItem];

    [m addItem:fcTopCategory(@"Window", windowItems)];

    return m;
}

- (NSMenuItem *)buildProfileMenu {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Profile" action:nil keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] init];

    NSDictionary *profiles = [[NSUserDefaults standardUserDefaults] objectForKey:@"Profiles"];
    NSString *active = [[NSUserDefaults standardUserDefaults] stringForKey:@"ActiveProfile"];
    NSArray *starters = @[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Researcher", @"Watch Party"];

    for (NSString *name in starters) {
        if (profiles[name] == nil) continue;
        NSMenuItem *item = [sub addItemWithTitle:name action:@selector(switchToProfile:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
        if ([name isEqualToString:active]) item.state = NSControlStateValueOn;
    }

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

    NSMenuItem *defItem = [sub addItemWithTitle:@"Save as Default" action:@selector(saveAsDefaultProfile:) keyEquivalent:@"S"];
    defItem.target = self;
    defItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenuItem *saveItem = [sub addItemWithTitle:@"Save Current As…" action:@selector(saveCurrentProfileAs:) keyEquivalent:@""];
    saveItem.target = self;

    // v4 iter-84: destructive factory reset. Confirmation-gated in the
    // action handler, separator above to visually decouple from save ops.
    [sub addItem:[NSMenuItem separatorItem]];
    NSMenuItem *resetItem = [sub addItemWithTitle:@"Reset All to Factory Defaults…" action:@selector(resetAllToFactory:) keyEquivalent:@""];
    resetItem.target = self;

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

// v4 iter-102 / iter-104: Quick Style presets — each entry is a
// dictionary of NSUserDefaults keys → values. applyQuickStyle: writes
// them all at once. Scoped to aesthetic levers only: Theme (3
// segments), Corner / Shadow, Density / LineSpacing / LetterSpacing,
// FontWeight, TimeSeparator. Deliberately omits FontSize,
// SelectedMarket, DisplayMode — those are user-chosen scale/content
// prefs, not aesthetic mood. iter-104 extracted the bundle data to
// Sources/preferences/FloatingClockQuickStyles.m so tests can
// validate each bundle's contents against known allowed value sets.
- (NSMenuItem *)buildQuickStylesMenu {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Quick Style"
                                                   action:nil
                                            keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] init];

    for (NSArray *style in buildQuickStyles()) {
        NSMenuItem *it = [sub addItemWithTitle:style[0]
                                         action:@selector(applyQuickStyle:)
                                  keyEquivalent:@""];
        it.representedObject = style[1];
        it.target = self;
    }

    root.submenu = sub;
    return root;
}

@end
