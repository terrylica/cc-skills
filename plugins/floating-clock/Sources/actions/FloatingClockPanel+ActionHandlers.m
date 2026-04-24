#import "FloatingClockPanel+ActionHandlers.h"
#import "../core/FloatingClockPanel+Layout.h"
#import "../core/FloatingClockPanel+Runtime.h"
#import "../rendering/SegmentOpacityResolver.h"

@implementation FloatingClockPanel (ActionHandlers)

- (void)toggleShowSeconds:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowSeconds"] forKey:@"ShowSeconds"];
    [self applyDisplaySettings];
}

- (void)toggleShowDate:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowDate"] forKey:@"ShowDate"];
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
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"CanvasOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveBarCells:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"ActiveBarCells"];
        [self applyDisplaySettings];
    }
}

- (void)setProgressBarStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ProgressBarStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setLayoutMode:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LayoutMode"];
        [self applyDisplaySettings];
    }
}

- (void)setSegmentGap:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"SegmentGap"];
        [self applyDisplaySettings];
    }
}

- (void)setCornerStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"CornerStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setShadowStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ShadowStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveFontSize:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"ActiveFontSize"];
        [self applyDisplaySettings];
    }
}

- (void)setNextFontSize:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"NextFontSize"];
        [self applyDisplaySettings];
    }
}

- (void)setFontWeight:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"FontWeight"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveWeight:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ActiveWeight"];
        [self applyDisplaySettings];
    }
}

- (void)setNextWeight:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"NextWeight"];
        [self applyDisplaySettings];
    }
}

- (void)setLetterSpacing:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LetterSpacing"];
        [self applyDisplaySettings];
    }
}

- (void)setLineSpacing:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LineSpacing"];
        [self applyDisplaySettings];
    }
}

- (void)setTimeSeparator:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"TimeSeparator"];
        [self applyDisplaySettings];
    }
}

- (void)setSessionSignalWindow:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"SessionSignalWindow"];
        [self applyDisplaySettings];
    }
}

// v4 iter-102: Quick Style application. The menu item's representedObject
// is a dictionary of pref-key → value pairs. Each k/v is written to
// NSUserDefaults atomically (writes to standardUserDefaults are
// implicitly ordered; applyDisplaySettings re-renders after all
// writes). Scoped: only aesthetic levers are in these bundles — the
// user's chosen FontSize / SelectedMarket / DisplayMode are untouched.
- (void)applyQuickStyle:(NSMenuItem *)sender {
    if (![sender.representedObject isKindOfClass:[NSDictionary class]]) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *bundle = sender.representedObject;
    for (NSString *k in bundle) {
        [d setObject:bundle[k] forKey:k];
    }
    [self applyDisplaySettings];
}

- (void)toggleShowFlags:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowFlags"] forKey:@"ShowFlags"];
    [self applyDisplaySettings];
}

- (void)toggleShowUTCReference:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = ![d objectForKey:@"ShowUTCReference"] || [d boolForKey:@"ShowUTCReference"];
    [d setBool:!cur forKey:@"ShowUTCReference"];
    [self applyDisplaySettings];
}

- (void)toggleShowSkyState:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = ![d objectForKey:@"ShowSkyState"] || [d boolForKey:@"ShowSkyState"];
    [d setBool:!cur forKey:@"ShowSkyState"];
    [self applyDisplaySettings];
}

- (void)toggleShowProgressPercent:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowProgressPercent"] forKey:@"ShowProgressPercent"];
    [self applyDisplaySettings];
}

// v4 iter-85: dump a plain-text snapshot of the current clock to the
// system clipboard. Useful for sharing state in chat/notes. Uses the
// same attributed-string content that the UI renders so formatting
// stays in sync automatically.
- (void)copyStateToClipboard:(id)sender {
    NSMutableString *snapshot = [NSMutableString string];
    if (_localSeg && _localSeg.timeLabel.stringValue.length > 0) {
        [snapshot appendString:_localSeg.timeLabel.stringValue];
        [snapshot appendString:@"\n\n"];
    }
    if (_activeSeg && _activeSeg.contentLabel.attributedStringValue.string.length > 0) {
        [snapshot appendString:_activeSeg.contentLabel.attributedStringValue.string];
        [snapshot appendString:@"\n"];
    }
    if (_nextSeg && _nextSeg.contentLabel.attributedStringValue.string.length > 0) {
        [snapshot appendString:_nextSeg.contentLabel.attributedStringValue.string];
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:snapshot forType:NSPasteboardTypeString];
}

- (void)setDensity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"Density"];
        [self applyDisplaySettings];
    }
}

- (void)setNextItemCount:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"NextItemCount"];
        [self applyDisplaySettings];
    }
}

- (void)applyTheme:(const ClockTheme *)theme
     toSegmentView:(NSView *)seg
         textField:(NSTextField *)field
       opacityKey:(NSString *)opacityKey {
    // v4 iter-90: opacity resolution goes through the shared 3-tier
    // resolver (per-segment → global CanvasOpacity → theme->alpha).
    // Caller passes the per-segment key ("LocalOpacity" / "ActiveOpacity"
    // / "NextOpacity") so each segment can dim independently. Text
    // always stays at alpha=1.0 regardless (user needs to keep reading
    // the clock face even when the canvas fades into the desktop).
    CGFloat bgAlpha = FCResolveSegmentOpacity(opacityKey, theme->alpha);
    seg.layer.backgroundColor = [[NSColor colorWithRed:theme->bg_r green:theme->bg_g blue:theme->bg_b alpha:bgAlpha] CGColor];
    field.textColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
}

- (void)setLocalOpacity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"LocalOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveOpacity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"ActiveOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)setNextOpacity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"NextOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)resetPosition:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"FloatingClockWindowFrame"];
    [d removeObjectForKey:@"FloatingClockScreenNumber"];
    [self setFrame:[self defaultFrame] display:YES animate:YES];
}

// v4 iter-109: Clear every aesthetic-pref key so NSUserDefaults falls
// back to the values registered in clock.m's registerDefaults. Leaves
// market / display-mode / active profile / profiles catalog / font
// name override / window frame intact — the user's workflow keeps
// its shape, only the visual style snaps back to factory.
- (void)resetVisualStyle:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *keys = @[
        @"ShowSeconds", @"ShowDate", @"ShowFlags", @"ShowUTCReference",
        @"ShowSkyState", @"ShowProgressPercent",
        @"TimeFormat", @"TimeSeparator", @"DateFormat", @"SessionSignalWindow",
        @"FontSize", @"ActiveFontSize", @"NextFontSize",
        @"FontWeight", @"ActiveWeight", @"NextWeight",
        @"LetterSpacing", @"LineSpacing",
        @"ColorTheme", @"LocalTheme", @"ActiveTheme", @"NextTheme",
        @"CanvasOpacity", @"LocalOpacity", @"ActiveOpacity", @"NextOpacity",
        @"ActiveBarCells", @"NextItemCount", @"ProgressBarStyle",
        @"LayoutMode", @"SegmentGap", @"Density",
        @"CornerStyle", @"ShadowStyle",
    ];
    for (NSString *k in keys) [d removeObjectForKey:k];
    [self applyDisplaySettings];
}

- (void)showAbout:(id)sender {
    // v4 iter-110: pull version from Info.plist so the dialog stays
    // in sync with plugin.json via CFBundleShortVersionString; append
    // the v4-campaign iteration number from CFBundleVersion.
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *vers  = [info objectForKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *build = [info objectForKey:@"CFBundleVersion"] ?: @"";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Floating Clock %@", vers];
    alert.informativeText = [NSString stringWithFormat:
        @"Always-on-top floating desktop clock for macOS.\n\n"
         "• 27 color themes · 12 Quick Style moods (Brutalist / Zen / Retro CRT / Executive / Neon / Hacker / Glacier / Midnight / Featherlight / Industrial / Trading Floor / Scholar)\n"
         "• 12 major global exchanges with 5-state session tracking (OPEN · LUNCH · PRE-MARKET · AFTER-HOURS · CLOSED)\n"
         "• SessionSignalWindow lever controls PRE/AFTER auction gate (off / 5-60 min)\n"
         "• Three-segment dashboard · 6 bundled profiles · per-segment Theme / Opacity / Weight\n"
         "• Typography trilogy: FontWeight (7) · LetterSpacing · LineSpacing · 12 progress-bar glyphs\n"
         "• Sub-0.1%% idle CPU · ~216 KB signed binary\n\n"
         "Objective-C + NSPanel · build %@\n"
         "© 2026 Terry Li", build];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

// v4 iter-149: copy the LOCAL row's current display (time + TZ label,
// and UTC reference if enabled) to the system clipboard. Available only
// from the LOCAL segment's right-click menu — the ACTIVE/NEXT segments
// don't have a single "the time" to copy since each entry has its own.
- (void)copyTime:(id)sender {
    NSString *text = _label.stringValue;
    if (text.length == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
}

@end
