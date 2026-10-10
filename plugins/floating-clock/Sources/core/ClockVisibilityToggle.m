#import "ClockVisibilityToggle.h"
#import "HotKeySpec.h"
#import <Carbon/Carbon.h>
#import <os/log.h>

// Names derive from the bundle identifier (Info.plist CFBundleIdentifier), so
// the running app and its own `--toggle` CLI always agree, and no identifier
// is hard-coded twice. A bare build/floating-clock outside its bundle falls
// back to "floating-clock".
static NSString *FCBundleID(void) {
    NSString *b = [NSBundle mainBundle].bundleIdentifier;
    return b.length ? b : @"floating-clock";
}

NSString *FCVisibilityNotificationName(NSString *verb) {
    return [NSString stringWithFormat:@"%@.visibility.%@", FCBundleID(), verb];
}
// Chosen 2026-10-10 from a survey of the shortcuts claimed by the system and
// by installed tools and apps, plus a live press-and-watch test
// (docs/visibility-toggle.md). A four-modifier chord
// with no Hyper key cannot be hit by accident; F16-F20 were rejected because
// no MacBook key produces them; ., , and / belong to sysdiagnose.
NSString *const FCToggleVisibilityHotKeyDefault = @"ctrl+opt+shift+cmd+H";

static BOOL gHidden = NO;
BOOL FCClockUserHidden(void) { return gHidden; }

static os_log_t FCVisLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create(FCBundleID().UTF8String, "visibility"); });
    return log;
}

static const OSType kFCHotKeySignature = 'FCLK';

@implementation FCClockVisibilityToggle {
    __weak NSPanel *_panel;
    void (^_afterChange)(void);
    EventHotKeyRef _hotKeyRef;
    EventHandlerRef _handlerRef;
    CFAbsoluteTime _lastPress;
    NSString *_hotKeyDisplay;
}

+ (instancetype)shared {
    static FCClockVisibilityToggle *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSString *)hotKeyDisplay { return _hotKeyDisplay; }

static OSStatus FCHotKeyHandler(EventHandlerCallRef next, EventRef event, void *ctx) {
    (void)next;
    EventHotKeyID hk;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                          sizeof(hk), NULL, &hk) != noErr || hk.signature != kFCHotKeySignature) {
        return eventNotHandledErr;   // someone else's hotkey in this process
    }
    FCClockVisibilityToggle *self = (__bridge FCClockVisibilityToggle *)ctx;
    // Debounce: a held chord or a bouncy key must not flip twice.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - self->_lastPress < 0.25) return noErr;
    self->_lastPress = now;
    dispatch_async(dispatch_get_main_queue(), ^{ [self toggleWithSource:@"hotkey"]; });
    return noErr;
}

- (void)installWithPanel:(NSPanel *)panel afterChange:(void (^)(void))afterChange {
    _panel = panel;
    _afterChange = [afterChange copy];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d registerDefaults:@{ @"ToggleVisibilityHotKey": FCToggleVisibilityHotKeyDefault }];
    NSString *spec = [d stringForKey:@"ToggleVisibilityHotKey"];
    [self registerHotKeySpec:spec];

    // Background (LSUIElement) apps are never "active", and AppKit holds back
    // distributed notifications for inactive apps unless the observer asks for
    // DeliverImmediately — which only the selector form of the API can say.
    NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
    for (NSString *name in @[ FCVisibilityNotificationName(@"toggle"), FCVisibilityNotificationName(@"show"),
                              FCVisibilityNotificationName(@"hide") ]) {
        [dnc addObserver:self selector:@selector(visibilityNotification:) name:name object:nil
      suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
}

- (void)visibilityNotification:(NSNotification *)n {
    if ([n.name isEqualToString:FCVisibilityNotificationName(@"toggle")]) {
        [self toggleWithSource:@"notification"];
    } else {
        [self setHidden:[n.name isEqualToString:FCVisibilityNotificationName(@"hide")] source:@"notification"];
    }
}

- (void)registerHotKeySpec:(NSString *)spec {
    if (spec.length == 0 || [spec.lowercaseString isEqualToString:@"none"]) {
        os_log(FCVisLog(), "hotkey disabled by ToggleVisibilityHotKey=%{public}@", spec ?: @"(nil)");
        return;
    }
    uint32_t code = 0, mods = 0;
    if (!FCParseHotKeySpec(spec, &code, &mods)) {
        os_log_error(FCVisLog(), "unparseable ToggleVisibilityHotKey=%{public}@; no hotkey", spec);
        return;
    }
    if (!_handlerRef) {
        EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
        InstallApplicationEventHandler(&FCHotKeyHandler, 1, &type, (__bridge void *)self, &_handlerRef);
    }
    EventHotKeyID hkID = { kFCHotKeySignature, 1 };
    OSStatus st = RegisterEventHotKey(code, mods, hkID, GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (st != noErr) {
        os_log_error(FCVisLog(), "RegisterEventHotKey(%{public}@) failed: %d", spec, (int)st);
        _hotKeyRef = NULL;
        return;
    }
    _hotKeyDisplay = FCHotKeySpecDisplayString(spec);
    os_log(FCVisLog(), "hotkey registered: %{public}@", _hotKeyDisplay);
}

- (void)toggleWithSource:(NSString *)source {
    [self setHidden:!gHidden source:source];
}

- (void)setHidden:(BOOL)hidden source:(NSString *)source {
    NSPanel *panel = _panel;
    if (!panel || hidden == gHidden) return;
    gHidden = hidden;
    os_log(FCVisLog(), "clock %{public}@ via %{public}@", hidden ? @"hidden" : @"shown", source);
    if (hidden) {
        if (_afterChange) _afterChange();   // rails run their hide ceremony first
        [panel orderOut:nil];
    } else {
        [panel orderFrontRegardless];       // accessory app: never "active"
        if (_afterChange) _afterChange();   // rails re-attach and show
    }
}

@end

BOOL FCHandleVisibilityCommandLine(int argc, const char *argv[]) {
    NSString *name = nil;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--toggle") == 0) name = FCVisibilityNotificationName(@"toggle");
        else if (strcmp(argv[i], "--show") == 0) name = FCVisibilityNotificationName(@"show");
        else if (strcmp(argv[i], "--hide") == 0) name = FCVisibilityNotificationName(@"hide");
    }
    if (!name) return NO;
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:name object:nil
                                                                 userInfo:nil deliverImmediately:YES];
    return YES;
}
