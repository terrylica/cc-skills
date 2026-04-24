#import "FloatingClockPanel+ActionHandlers.h"
#import "../core/FloatingClockPanel+Layout.h"
#import "../core/FloatingClockPanel+Runtime.h"
#import "../core/ClipboardHeader.h"  // iter-160: extracted testable helper
#import "../rendering/SegmentOpacityResolver.h"

// v4 iter-160: fcCopyWithHeader now wraps the pure FCComposeClipboardSnapshot.
// This ObjC-level wrapper stays local because it touches NSPasteboard
// (side-effecting); the composition logic is exported for testing.
static void fcCopyWithHeader(NSString *label, NSString *body) {
    NSString *text = FCComposeClipboardSnapshot(label, body, nil);
    if (text.length == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
}

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
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setDouble:[sender.representedObject doubleValue] forKey:@"CanvasOpacity"];
        // v4 iter-194: clear per-segment overrides so the global Canvas
        // Opacity setting actually takes visible effect across ALL
        // segments. Without this, stale LocalOpacity / ActiveOpacity /
        // NextOpacity keys win the iter-90 three-tier fallback and
        // pin those segments to the old value — user drags Canvas
        // Opacity and sees ~2/3 of the clock frozen, correctly
        // reports "Transparency failed to work".
        [d removeObjectForKey:@"LocalOpacity"];
        [d removeObjectForKey:@"ActiveOpacity"];
        [d removeObjectForKey:@"NextOpacity"];
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
// v4 iter-153: routed through fcCopyWithHeader for output consistency
// with iter-149/150/152's per-segment Copy actions. All four clipboard
// outputs now share the same header format.
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
    fcCopyWithHeader(@"FULL CLOCK STATE", snapshot);
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
         "• 28 color themes · 13 Quick Style moods (Brutalist / Zen / Retro CRT / Executive / Neon / Hacker / Glacier / Midnight / Featherlight / Industrial / Trading Floor / Scholar / Samba)\n"
         "• 13 major global exchanges (Americas / Europe / Africa / Asia / Oceania) with 5-state session tracking (OPEN · LUNCH · PRE-MARKET · AFTER-HOURS · CLOSED)\n"
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

// v4 iter-167: reveal the running app's bundle in Finder. Useful when
// users want to right-click → Show Package Contents, verify a copy
// they moved, or just find where FloatingClock lives. Uses the
// running process's mainBundle so it always points to the actually-
// executing binary (whether that's /Applications/FloatingClock.app
// or the plugin's local build/).
- (void)revealAppInFinder:(id)sender {
    NSURL *bundleURL = [NSBundle mainBundle].bundleURL;
    if (!bundleURL) return;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[bundleURL]];
}

// v4 iter-160: body extracted to Sources/core/ClipboardHeader.{h,m}.
// The wrapper (top of file) now only handles the NSPasteboard write;
// composition is pure-function + tested.

// v4 iter-149: copy the LOCAL row's current display (time + TZ label,
// and UTC reference if enabled) to the system clipboard.
// v4 iter-150: fix — in three-segment mode (the default DisplayMode
// since iter-11) the LOCAL time lives in `_localSeg.timeLabel`;
// `_label` is the legacy single-market / local-only path. Prefer the
// populated source so Copy Time actually works across all modes.
- (void)copyTime:(id)sender {
    NSString *threeSeg = _localSeg.timeLabel.stringValue;
    NSString *legacy   = _label.stringValue;
    NSString *text = threeSeg.length > 0 ? threeSeg : legacy;
    fcCopyWithHeader(@"LOCAL", text);
}

// v4 iter-150: copy ACTIVE segment's multi-line content to clipboard —
// the full list of currently-open markets with progress/countdown.
// Useful for pasting a "market snapshot" into notes/chat.
- (void)copyActiveMarkets:(id)sender {
    fcCopyWithHeader(@"ACTIVE MARKETS", _activeSeg.contentLabel.attributedStringValue.string);
}

// v4 iter-150: copy NEXT segment's multi-line content — upcoming opens
// with countdowns. Mirror of copyActiveMarkets.
- (void)copyNextOpens:(id)sender {
    fcCopyWithHeader(@"NEXT TO OPEN", _nextSeg.contentLabel.attributedStringValue.string);
}

@end
