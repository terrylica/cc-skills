#import <Cocoa/Cocoa.h>

// Forward declaration
@class FloatingClockPanel;
@class ClockContentView;

// Calculate nanoseconds until next second boundary
static uint64_t nsUntilNextSecond(void) {
    NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
    double frac = t - floor(t);
    return (uint64_t)((1.0 - frac) * NSEC_PER_SEC);
}

// Map color name to NSColor
static NSColor *colorFromName(NSString *name) {
    if ([name isEqualToString:@"amber"])  return [NSColor colorWithRed:1.0 green:0.75 blue:0.0 alpha:1.0];
    if ([name isEqualToString:@"green"])  return [NSColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
    if ([name isEqualToString:@"cyan"])   return [NSColor colorWithRed:0.3 green:0.9 blue:0.95 alpha:1.0];
    if ([name isEqualToString:@"red"])    return [NSColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
    return [NSColor whiteColor];
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

@interface FloatingClockPanel : NSPanel {
    NSTextField *_label;
    dispatch_source_t _timer;
    NSDateFormatter *_dateFormatter;
    id _keyMonitor;
}
- (NSMenu *)buildMenu;
- (void)refreshMenuChecks:(NSMenu *)menu;
- (NSMenuItem *)submenuTitled:(NSString *)title action:(SEL)action pairs:(NSArray *)pairs defaultsKey:(NSString *)key;
- (void)applyDisplaySettings;
- (void)toggleShowSeconds:(NSMenuItem *)sender;
- (void)toggleShowDate:(NSMenuItem *)sender;
- (void)setTimeFormat:(NSMenuItem *)sender;
- (void)setFontSize:(NSMenuItem *)sender;
- (void)setOpacity:(NSMenuItem *)sender;
- (void)setTextColor:(NSMenuItem *)sender;
- (void)resetPosition:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;
@end

@implementation FloatingClockPanel

- (instancetype)init {
    // Register default values for NSUserDefaults
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"ShowSeconds": @YES,
        @"ShowDate": @NO,
        @"TimeFormat": @"24h",
        @"FontSize": @24.0,
        @"BackgroundAlpha": @0.32,
        @"TextColor": @"white",
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
    _label.stringValue = [_dateFormatter stringFromDate:[NSDate date]];
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

    [m addItem:[self submenuTitled:@"Font Size" action:@selector(setFontSize:)
                              pairs:@[@[@"18", @18], @[@"20", @20], @[@"22", @22], @[@"24", @24], @[@"28", @28], @[@"32", @32]]
                        defaultsKey:@"FontSize"]];

    [m addItem:[self submenuTitled:@"Opacity" action:@selector(setOpacity:)
                              pairs:@[@[@"10%", @0.10], @[@"20%", @0.20], @[@"32%", @0.32], @[@"50%", @0.50], @[@"70%", @0.70], @[@"Opaque", @1.00]]
                        defaultsKey:@"BackgroundAlpha"]];

    [m addItem:[self submenuTitled:@"Text Color" action:@selector(setTextColor:)
                              pairs:@[@[@"White", @"white"], @[@"Amber", @"amber"], @[@"Green", @"green"], @[@"Cyan", @"cyan"], @[@"Red", @"red"]]
                        defaultsKey:@"TextColor"]];

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

- (void)refreshMenuChecks:(NSMenu *)menu {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Update toggle items (Show Seconds, Show Date)
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:@"Show Seconds"]) {
            item.state = [d boolForKey:@"ShowSeconds"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([item.title isEqualToString:@"Show Date"]) {
            item.state = [d boolForKey:@"ShowDate"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if (item.submenu) {
            // Update submenu items
            NSString *subTitle = item.title;
            id currentValue = nil;

            if ([subTitle isEqualToString:@"Time Format"]) {
                currentValue = [d stringForKey:@"TimeFormat"];
            } else if ([subTitle isEqualToString:@"Font Size"]) {
                currentValue = [d objectForKey:@"FontSize"];
            } else if ([subTitle isEqualToString:@"Opacity"]) {
                currentValue = [d objectForKey:@"BackgroundAlpha"];
            } else if ([subTitle isEqualToString:@"Text Color"]) {
                currentValue = [d stringForKey:@"TextColor"];
            }

            for (NSMenuItem *subItem in item.submenu.itemArray) {
                if (subItem.representedObject) {
                    BOOL matches = NO;
                    if ([currentValue isKindOfClass:[NSString class]]) {
                        matches = [subItem.representedObject isEqualToString:currentValue];
                    } else if ([currentValue isKindOfClass:[NSNumber class]]) {
                        matches = [subItem.representedObject isEqual:currentValue];
                    }
                    subItem.state = matches ? NSControlStateValueOn : NSControlStateValueOff;
                }
            }
        }
    }
}

- (void)applyDisplaySettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Update label with new font and color
    CGFloat fontSize = [d doubleForKey:@"FontSize"];
    NSString *colorName = [d stringForKey:@"TextColor"];

    _label.font = resolveClockFont(fontSize);
    _label.textColor = colorFromName(colorName);

    // Update background alpha
    CGFloat alpha = [d doubleForKey:@"BackgroundAlpha"];
    self.backgroundColor = [NSColor colorWithWhite:0.0 alpha:alpha];

    // Measure text to resize window
    [self tick];  // Update label with new format

    NSString *text = _label.stringValue;
    NSDictionary *attrs = @{NSFontAttributeName: _label.font};
    NSSize textSize = [text sizeWithAttributes:attrs];

    // Add generous padding and ceil to avoid subpixel clipping on the right edge.
    // Label is NSInsetRect(bounds, 8, 8) so window padding must be > label inset
    // AND leave slack for font renderer's trailing advance + antialiasing.
    CGFloat newWidth  = ceilf(textSize.width)  + 32;  // 16pt slack per side
    CGFloat newHeight = ceilf(textSize.height) + 20;  // 10pt slack per side

    NSRect oldFrame = self.frame;
    CGFloat oldWidth = oldFrame.size.width;
    CGFloat oldHeight = oldFrame.size.height;

    // Resize anchored at center
    CGFloat centerX = oldFrame.origin.x + oldWidth / 2.0;
    CGFloat centerY = oldFrame.origin.y + oldHeight / 2.0;

    NSRect newFrame = NSMakeRect(centerX - newWidth / 2.0, centerY - newHeight / 2.0, newWidth, newHeight);
    [self setFrame:newFrame display:YES animate:NO];

    // Resize label to fill content view
    _label.frame = NSInsetRect(self.contentView.bounds, 8, 8);
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

- (void)setOpacity:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"BackgroundAlpha"];
        [self applyDisplaySettings];
    }
}

- (void)setTextColor:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"TextColor"];
        [self applyDisplaySettings];
    }
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
