#import <Cocoa/Cocoa.h>

// Calculate nanoseconds until next second boundary
static uint64_t nsUntilNextSecond(void) {
    NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
    double frac = t - floor(t);
    return (uint64_t)((1.0 - frac) * NSEC_PER_SEC);
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

@interface FloatingClockPanel : NSPanel {
    NSTextField *_label;
    dispatch_source_t _timer;
}
@end

@implementation FloatingClockPanel

- (instancetype)init {
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
    self.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.32];
    self.titleVisibility = NSWindowTitleHidden;

    // Rounded corners
    self.contentView.wantsLayer = YES;
    self.contentView.layer.cornerRadius = 10.0;
    self.contentView.layer.masksToBounds = YES;

    // Text field for clock display
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSInsetRect(defaultFrame, 8, 8)];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.textColor = [NSColor whiteColor];
    label.font = resolveClockFont(24.0);
    label.alignment = NSTextAlignmentCenter;
    label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.contentView addSubview:label];
    _label = label;

    [self restorePosition];
    [self setupTimer];

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
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss";
    });
    _label.stringValue = [fmt stringFromDate:[NSDate date]];
}

- (NSRect)defaultFrame {
    NSScreen *s = [NSScreen mainScreen];
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
        // Also update saved screen number to main screen's
        NSNumber *sn = [NSScreen mainScreen].deviceDescription[@"NSScreenNumber"];
        if ([sn isKindOfClass:[NSNumber class]]) {
            [[NSUserDefaults standardUserDefaults] setObject:sn forKey:@"FloatingClockScreenNumber"];
        }
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(self.frame)
                                                  forKey:@"FloatingClockWindowFrame"];
    }
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
