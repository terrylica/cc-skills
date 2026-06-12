// Profile submenu builder — split from FloatingClockPanel+MenuBuilder
// during the 2026-06-12 modularization (MenuBuilder had breached the
// 500-line cap). Shared by the full-preferences menu AND the segment
// menus (both call buildProfileMenu).
#import "FloatingClockPanel+ProfileMenu.h"
#import "../preferences/FloatingClockPanel+ProfileManagement.h"
#import "FloatingClockPanel+MenuHelpers.h"

@implementation FloatingClockPanel (ProfileMenu)

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

@end
