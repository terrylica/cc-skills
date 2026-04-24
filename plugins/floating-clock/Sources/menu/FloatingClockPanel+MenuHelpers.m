// Shared NSMenu-building helpers. Extracted v4 iter-96 from
// FloatingClockPanel+MenuBuilder.m once it approached the 500-LoC
// cap (contract rule). See header for rationale.
#import "FloatingClockPanel+MenuHelpers.h"

@implementation FloatingClockPanel (MenuHelpers)

- (NSMenuItem *)submenuTitled:(NSString *)title
                        action:(SEL)action
                         pairs:(NSArray *)pairs
                   defaultsKey:(NSString *)key {
    (void)key;
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

- (NSMenuItem *)groupedSubmenuTitled:(NSString *)title
                                action:(SEL)action
                                groups:(NSArray *)groups
                          defaultsKey:(NSString *)key {
    (void)key;
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *rootSub = [[NSMenu alloc] init];

    for (NSArray *group in groups) {
        NSString *groupTitle = group[0];
        NSArray *items = group[1];

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

    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:@"Show Seconds"]) {
            item.state = [d boolForKey:@"ShowSeconds"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Date"]) {
            item.state = [d boolForKey:@"ShowDate"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Country Flags"]) {
            item.state = [d boolForKey:@"ShowFlags"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show UTC Reference"]) {
            BOOL on = ![d objectForKey:@"ShowUTCReference"] || [d boolForKey:@"ShowUTCReference"];
            item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Sun/Moon"]) {
            BOOL on = ![d objectForKey:@"ShowSkyState"] || [d boolForKey:@"ShowSkyState"];
            item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Progress %"]) {
            item.state = [d boolForKey:@"ShowProgressPercent"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if (item.submenu) {
            NSString *subTitle = item.title;
            id currentValue = nil;

            if ([subTitle isEqualToString:@"Time Format"])          currentValue = [d stringForKey:@"TimeFormat"];
            else if ([subTitle isEqualToString:@"Font Size"])       currentValue = [d objectForKey:@"FontSize"];
            else if ([subTitle isEqualToString:@"Time Zone"])       currentValue = [d stringForKey:@"SelectedMarket"];
            else if ([subTitle isEqualToString:@"Color Theme (Local)"])  currentValue = [d stringForKey:@"LocalTheme"];
            else if ([subTitle isEqualToString:@"Color Theme (Active)"]) currentValue = [d stringForKey:@"ActiveTheme"];
            else if ([subTitle isEqualToString:@"Color Theme (Next)"])   currentValue = [d stringForKey:@"NextTheme"];
            else if ([subTitle isEqualToString:@"Color Theme (Legacy)"]) currentValue = [d stringForKey:@"ColorTheme"];
            else if ([subTitle isEqualToString:@"Display Mode"])    currentValue = [d stringForKey:@"DisplayMode"];

            [self setChecksInMenu:item.submenu forKey:subTitle currentValue:currentValue];
        }
    }
}

@end
