#import <Cocoa/Cocoa.h>

// Calculate nanoseconds until next second boundary
static uint64_t nsUntilNextSecond(void) {
    NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
    double frac = t - floor(t);
    return (uint64_t)((1.0 - frac) * NSEC_PER_SEC);
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
    self.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.55];
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
    label.font = [NSFont monospacedDigitSystemFontOfSize:24 weight:NSFontWeightMedium];
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

- (void)windowDidMove:(NSNotification *)n {
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(self.frame)
                                              forKey:@"FloatingClockWindowFrame"];
}

- (void)restorePosition {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"FloatingClockWindowFrame"];
    if (s) {
        NSRect r = NSRectFromString(s);
        // Clamp to main screen visibleFrame — refuse off-screen frames
        NSRect vf = [NSScreen mainScreen].visibleFrame;
        if (NSIntersectsRect(r, vf) && r.size.width > 20 && r.size.height > 20) {
            [self setFrame:r display:NO];
            return;
        }
    }
    [self center];
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
