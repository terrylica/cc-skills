// Segment-scoped context menus (LOCAL / ACTIVE / NEXT right-click) plus
// the 'Full Preferences…' item that pops the full menu from any segment.
//
// Extracted v4 iter-87 from FloatingClockPanel+MenuBuilder.m once it
// crossed the 500-LoC hard cap. MenuBuilder.m retains buildMenu +
// buildProfileMenu; iter-96 further split the shared submenu helpers
// (submenuTitled / groupedSubmenuTitled / setChecks / refreshMenuChecks)
// into FloatingClockPanel+MenuHelpers.{h,m} — this file imports both.
#import "FloatingClockPanel+SegmentMenus.h"
#import "FloatingClockPanel+MenuBuilder.h"
#import "FloatingClockPanel+MenuHelpers.h"
#import "../data/ThemeCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"

@implementation FloatingClockPanel (SegmentMenus)

- (NSMenu *)buildLocalSegmentMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = (ClockContentView *)self.contentView;

    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setLocalTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"LocalTheme"];
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    NSMenuItem *ss = [m addItemWithTitle:@"Show Seconds" action:@selector(toggleShowSeconds:) keyEquivalent:@""];
    ss.target = self;
    NSMenuItem *sd = [m addItemWithTitle:@"Show Date" action:@selector(toggleShowDate:) keyEquivalent:@""];
    sd.target = self;

    [m addItem:[self submenuTitled:@"Time Format"
                             action:@selector(setTimeFormat:)
                              pairs:@[@[@"24-hour", @"24h"], @[@"12-hour", @"12h"]]
                        defaultsKey:@"TimeFormat"]];

    [m addItem:[self submenuTitled:@"Date Format"
                             action:@selector(setDateFormat:)
                              pairs:@[@[@"Short         (Thu Apr 23)",          @"short"],
                                      @[@"Long          (Thursday April 23)",   @"long"],
                                      @[@"ISO           (2026-04-23)",          @"iso"],
                                      @[@"Compact ISO   (04-23)",               @"compact_iso"],
                                      @[@"Numeric       (4/23)",                @"numeric"],
                                      @[@"USA           (4/23/2026)",           @"usa"],
                                      @[@"European      (23.4.2026)",           @"european"],
                                      @[@"Week Number   (Wk 17)",               @"weeknum"],
                                      @[@"Day of Year   (Day 114)",             @"dayofyr"]]
                        defaultsKey:@"DateFormat"]];

    [m addItem:[self groupedSubmenuTitled:@"Font Size"
                                    action:@selector(setFontSize:)
                                    groups:@[
        @[@"Small",  @[@[@"10", @10.0], @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0]]],
        @[@"Medium", @[@[@"18", @18.0], @[@"20", @20.0], @[@"22", @22.0], @[@"24", @24.0]]],
        @[@"Large",  @[@[@"28", @28.0], @[@"32", @32.0], @[@"36", @36.0], @[@"42", @42.0]]],
        @[@"Huge",   @[@[@"48", @48.0], @[@"56", @56.0], @[@"64", @64.0]]],
    ]                           defaultsKey:@"FontSize"]];

    // v4 iter-90: LOCAL's scoped Transparency now writes the per-segment
    // key (LocalOpacity) so adjusting it from this menu dims LOCAL only.
    // Global CanvasOpacity remains reachable via Full Preferences…
    [m addItem:[self submenuTitled:@"Transparency"
                             action:@selector(setLocalOpacity:)
                              pairs:@[@[@"Opaque (100%)", @1.0],
                                      @[@"Solid (90%)",   @0.9],
                                      @[@"Glass (75%)",   @0.75],
                                      @[@"Medium (50%)",  @0.5],
                                      @[@"Faint (30%)",   @0.3],
                                      @[@"Ghost (15%)",   @0.15]]
                        defaultsKey:@"LocalOpacity"]];

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

    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setActiveTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"ActiveTheme"];
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    [m addItem:[self groupedSubmenuTitled:@"Progress Bar Width"
                                    action:@selector(setActiveBarCells:)
                                    groups:@[
        @[@"Small",  @[@[@"6 cells", @6], @[@"7 cells", @7], @[@"8 cells", @8], @[@"10 cells", @10]]],
        @[@"Medium", @[@[@"12 cells", @12], @[@"14 cells", @14], @[@"16 cells", @16], @[@"18 cells", @18]]],
        @[@"Large",  @[@[@"20 cells", @20], @[@"24 cells", @24], @[@"28 cells", @28], @[@"32 cells", @32]]],
        @[@"Huge",   @[@[@"36 cells", @36], @[@"40 cells", @40]]],
    ]                          defaultsKey:@"ActiveBarCells"]];

    // Progress-bar glyph style — 10 presets (iter-27: 6, iter-91: +4).
    [m addItem:[self submenuTitled:@"Progress Bar Style"
                             action:@selector(setProgressBarStyle:)
                              pairs:@[@[@"Blocks  (█ ▒)",  @"blocks"],
                                      @[@"Dots    (● ○)",  @"dots"],
                                      @[@"Dashes  (━ ╌)",  @"dashes"],
                                      @[@"Arrows  (▶ ▷)",  @"arrows"],
                                      @[@"Binary  (█ ░)",  @"binary"],
                                      @[@"Braille (⣿ ⣀)", @"braille"],
                                      @[@"Hearts  (♥ ♡)",  @"hearts"],
                                      @[@"Stars   (★ ☆)",  @"stars"],
                                      @[@"Ribbon  (▰ ▱)",  @"ribbon"],
                                      @[@"Diamond (◆ ◇)",  @"diamond"]]
                        defaultsKey:@"ProgressBarStyle"]];

    // Per-segment font size (v4 iter-33).
    [m addItem:[self submenuTitled:@"Font Size"
                             action:@selector(setActiveFontSize:)
                              pairs:@[@[@"9", @9.0],  @[@"10", @10.0], @[@"11", @11.0],
                                      @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0],
                                      @[@"18", @18.0], @[@"20", @20.0]]
                        defaultsKey:@"ActiveFontSize"]];

    // Per-segment font weight (v4 iter-89). Falls back to global FontWeight
    // if unset. Unlike Font Size, shares the same 5 presets as the global lever.
    [m addItem:[self submenuTitled:@"Font Weight"
                             action:@selector(setActiveWeight:)
                              pairs:@[@[@"Regular",  @"regular"],
                                      @[@"Medium",   @"medium"],
                                      @[@"Semibold", @"semibold"],
                                      @[@"Bold",     @"bold"],
                                      @[@"Heavy",    @"heavy"]]
                        defaultsKey:@"ActiveWeight"]];

    // Per-segment canvas opacity (v4 iter-90). Falls back to global
    // CanvasOpacity, then to theme->alpha via FCResolveSegmentOpacity.
    [m addItem:[self submenuTitled:@"Transparency"
                             action:@selector(setActiveOpacity:)
                              pairs:@[@[@"Opaque (100%)", @1.0],
                                      @[@"Solid (90%)",   @0.9],
                                      @[@"Glass (75%)",   @0.75],
                                      @[@"Medium (50%)",  @0.5],
                                      @[@"Faint (30%)",   @0.3],
                                      @[@"Ghost (15%)",   @0.15]]
                        defaultsKey:@"ActiveOpacity"]];

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

    NSMutableArray *themePairs = [NSMutableArray array];
    for (size_t i = 0; i < kNumThemes; i++) {
        [themePairs addObject:@[[NSString stringWithUTF8String:kThemes[i].display],
                                [NSString stringWithUTF8String:kThemes[i].id]]];
    }
    NSMenuItem *themeItem = [self submenuTitled:@"Theme"
                                          action:@selector(setNextTheme:)
                                           pairs:themePairs
                                     defaultsKey:@"NextTheme"];
    NSArray *sub = themeItem.submenu.itemArray;
    for (size_t i = 0; i < sub.count && i < kNumThemes; i++) {
        [(NSMenuItem *)sub[i] setImage:swatchForTheme(&kThemes[i])];
    }
    [m addItem:themeItem];

    [m addItem:[NSMenuItem separatorItem]];

    // v4 iter-101: Show Count 4 → 7 presets. 12 exchanges → up to ~11 can
    // be CLOSED at once, so values up to 10 are meaningful.
    [m addItem:[self submenuTitled:@"Show Count"
                             action:@selector(setNextItemCount:)
                              pairs:@[@[@"1",  @1], @[@"2", @2], @[@"3", @3], @[@"4", @4],
                                      @[@"5",  @5], @[@"7", @7], @[@"10", @10]]
                        defaultsKey:@"NextItemCount"]];

    [m addItem:[self submenuTitled:@"Font Size"
                             action:@selector(setNextFontSize:)
                              pairs:@[@[@"9", @9.0],  @[@"10", @10.0], @[@"11", @11.0],
                                      @[@"12", @12.0], @[@"14", @14.0], @[@"16", @16.0],
                                      @[@"18", @18.0], @[@"20", @20.0]]
                        defaultsKey:@"NextFontSize"]];

    // Per-segment font weight (v4 iter-89). Falls back to global FontWeight
    // when unset. Helpful when NEXT's lower-priority countdowns should
    // read lighter than ACTIVE's live markets.
    [m addItem:[self submenuTitled:@"Font Weight"
                             action:@selector(setNextWeight:)
                              pairs:@[@[@"Regular",  @"regular"],
                                      @[@"Medium",   @"medium"],
                                      @[@"Semibold", @"semibold"],
                                      @[@"Bold",     @"bold"],
                                      @[@"Heavy",    @"heavy"]]
                        defaultsKey:@"NextWeight"]];

    // Per-segment canvas opacity (v4 iter-90). Dim NEXT independently
    // of ACTIVE — useful for peripheral-visibility styling.
    [m addItem:[self submenuTitled:@"Transparency"
                             action:@selector(setNextOpacity:)
                              pairs:@[@[@"Opaque (100%)", @1.0],
                                      @[@"Solid (90%)",   @0.9],
                                      @[@"Glass (75%)",   @0.75],
                                      @[@"Medium (50%)",  @0.5],
                                      @[@"Faint (30%)",   @0.3],
                                      @[@"Ghost (15%)",   @0.15]]
                        defaultsKey:@"NextOpacity"]];

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
    NSMenu *full = [self buildMenu];
    [NSMenu popUpContextMenu:full withEvent:[NSApp currentEvent] forView:self.contentView];
}

@end
