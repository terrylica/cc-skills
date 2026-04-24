#import "FloatingClockPanel+ProfileManagement.h"
#import "FloatingClockStarterProfiles.h"
#import "../core/FloatingClockPanel+Layout.h"
#import "../menu/FloatingClockPanel+MenuBuilder.h"

@implementation FloatingClockPanel (ProfileManagement)

- (void)activateProfile:(NSString *)name {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *profiles = [d objectForKey:@"Profiles"];
    if (![profiles isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *profile = profiles[name];
    if (![profile isKindOfClass:[NSDictionary class]]) return;

    // v4 iter-194: clear ALL managed keys first, then apply the profile's
    // keys. Previous impl did `if (val != nil) set` which left stale
    // top-level keys from the previous profile when the new profile
    // didn't specify them. That leaked stale values across profile
    // switches — e.g. Profile-A had LocalOpacity=0.3 set, switching to
    // Profile-B (which doesn't specify LocalOpacity) left LocalOpacity
    // at 0.3, overriding B's CanvasOpacity via the iter-90 per-segment
    // > global fallback. Clear-then-apply gives clean-slate semantics.
    for (NSString *key in profileManagedKeys()) {
        [d removeObjectForKey:key];
    }
    for (NSString *key in profileManagedKeys()) {
        id val = profile[key];
        if (val != nil) [d setObject:val forKey:key];
    }

    [d setObject:name forKey:@"ActiveProfile"];
    [self applyDisplaySettings];
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
    [d synchronize];

    [self recordProfileActivationInCCMemory:name];
    self.contentView.menu = [self buildMenu];
}

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
    // Without synchronize, a fast quit after Save can lose the write — the
    // persistent domain only auto-flushes on ~5s tick or on terminate.
    [d synchronize];
    [self recordProfileActivationInCCMemory:active];
}

// Always-targets-Default variant. Use this when the user's intent is "make
// my current state the factory default" independent of which profile is
// active. Matches the user's mental model of "Save as Default" more
// reliably than quickSaveCurrentProfile, which ties to ActiveProfile.
- (void)saveAsDefaultProfile:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *profiles = [[d objectForKey:@"Profiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in profileManagedKeys()) {
        id val = [d objectForKey:key];
        if (val != nil) snapshot[key] = val;
    }
    profiles[@"Default"] = snapshot;
    [d setObject:profiles forKey:@"Profiles"];
    [d setObject:@"Default" forKey:@"ActiveProfile"];
    [d synchronize];
    [self recordProfileActivationInCCMemory:@"Default"];
    self.contentView.menu = [self buildMenu];
}

// v4 iter-84: nuke user customizations and reseed starter profiles.
// Confirmation-gated because this is destructive. Only the saved
// profile dict + managed raw keys are reset — window position and
// screen number are preserved (ergonomic state, not profile state).
- (void)resetAllToFactory:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset to Factory Defaults?";
    alert.informativeText = @"This wipes all customizations including saved "
        @"profiles. Window position is preserved. This cannot be undone.";
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // Clear every profile-managed key so registerDefaults' starter
    // values take effect again on next read.
    for (NSString *key in profileManagedKeys()) {
        [d removeObjectForKey:key];
    }
    // Reseed starter profile bundle.
    [d setObject:buildStarterProfiles() forKey:@"Profiles"];
    [d setObject:@"Default" forKey:@"ActiveProfile"];
    [d synchronize];

    // Re-apply visuals + rebuild menu so reset is immediately visible.
    [self applyDisplaySettings];
    self.contentView.menu = [self buildMenu];
    [self recordProfileActivationInCCMemory:@"Default"];
}

- (void)deleteProfile:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (![name isKindOfClass:[NSString class]]) return;

    NSSet *protected = [NSSet setWithArray:@[@"Default", @"Day Trader", @"Night Owl", @"Minimalist", @"Researcher", @"Watch Party"]];
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

    NSString *active = [d stringForKey:@"ActiveProfile"];
    if ([active isEqualToString:name]) [self activateProfile:@"Default"];
    self.contentView.menu = [self buildMenu];
}

- (void)switchToProfile:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [self activateProfile:sender.representedObject];
        self.contentView.menu = [self buildMenu];
    }
}

- (void)recordProfileActivationInCCMemory:(NSString *)profileName {
    NSString *memDir = [NSHomeDirectory() stringByAppendingPathComponent:
        @".claude/projects/-Users-terryli-eon-cc-skills/memory"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:memDir isDirectory:&isDir] || !isDir) return;

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
    if (err) NSLog(@"[floating-clock] Could not write memory entry: %@", err);

    NSString *indexPath = [memDir stringByAppendingPathComponent:@"MEMORY.md"];
    NSString *existing = [NSString stringWithContentsOfFile:indexPath encoding:NSUTF8StringEncoding error:nil];
    if (existing && ![existing containsString:@"floating_clock_active_profile.md"]) {
        NSString *entry = @"\n- [Floating clock active profile](./floating_clock_active_profile.md) — currently-selected clock profile, auto-updated\n";
        NSString *updated = [existing stringByAppendingString:entry];
        [updated writeToFile:indexPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
