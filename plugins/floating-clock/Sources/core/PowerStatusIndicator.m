#import "PowerStatusIndicator.h"
#import "PowerRailModel.h"
#import "PowerRailReaders.h"
#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "VPNStatusIndicator.h"
#import "BluetoothPairedAudioDeviceConnector.h"
#import "ClockVisibilityToggle.h"
#import "ClockChildWindowAttachment.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import <IOBluetooth/IOBluetooth.h>
#import <os/log.h>
#include <sys/stat.h>

static const CGFloat kPwrHeight = 20.0;
static const CGFloat kPwrGap    = 3.0;
static const CGFloat kPwrPadX   = 8.0;
static const CGFloat kPwrLabelH = 14.0;   // same fixed label height as the network and audio rails
static const NSUInteger kMaxDevices = 4;

// Re-read cadences, in 1 Hz ticks. The battery and accessory batteries also re-read at once on their
// IOPS change notifications; Bluetooth links re-read at once on IOBluetooth connect/disconnect.
// The device list is the one read that costs bluetoothd XPC work, so it is never read every tick
// (Stats issue #3623: a 1 s reader sent bluetoothd ~20 messages a second).
static const NSUInteger kBatteryEvery  = 10;
static const NSUInteger kPowerEvery    = 3;
static const NSUInteger kDevicesEvery  = 15;
static const NSUInteger kHIDEvery      = 30;
static const NSUInteger kHintEvery     = 5;

static NSString *FCPwrBundleID(void) {
    NSString *b = [NSBundle mainBundle].bundleIdentifier;
    return b.length ? b : @"floating-clock";
}

NSString *FCBluetoothPowerNotificationName(void) {
    return [FCPwrBundleID() stringByAppendingString:@".bluetooth.power"];
}

BOOL FCHandlePowerCommandLine(int argc, const char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bluetooth") != 0) continue;
        NSString *state = i + 1 < argc ? @(argv[i + 1]) : @"";
        if (![@[ @"on", @"off", @"toggle" ] containsObject:state]) {
            fprintf(stderr, "usage: floating-clock --bluetooth on|off|toggle\n");
            exit(64);   // EX_USAGE: a hotkey with a typo should fail loudly, not look like it worked
        }
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:FCBluetoothPowerNotificationName()
                                                                       object:nil
                                                                     userInfo:@{ @"state": state }
                                                           deliverImmediately:YES];
        return YES;
    }
    return NO;
}

static os_log_t FCPwrLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.cc-skills.floating-clock", "power-rail"); });
    return log;
}

@class FCPowerStatusIndicator;

#pragma mark - Rail view

// One label carries the whole line (so its baseline matches the other rails); clicks are mapped to a
// segment by measuring the attributed prefix, which is exact for this monospaced font.
@interface FCPowerRailView : NSView
@property (nonatomic, weak) FCPowerStatusIndicator *owner;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, copy) NSArray<NSDictionary *> *hitRanges;   // {x0, x1, action}
@end

@interface FCPowerStatusIndicator ()
- (void)performAction:(NSString *)action;
- (NSMenu *)railMenu;
@end

@implementation FCPowerRailView

- (NSView *)hitTest:(NSPoint)p {
    return NSPointInRect([self convertPoint:p fromView:self.superview], self.bounds) ? self : nil;
}

- (NSString *)actionAtX:(CGFloat)x {
    for (NSDictionary *r in self.hitRanges) {
        if (x >= [r[@"x0"] doubleValue] - 2 && x <= [r[@"x1"] doubleValue] + 2) return r[@"action"];
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSString *action = [self actionAtX:p.x];
    if (action.length) [self.owner performAction:action];
}

- (NSMenu *)menuForEvent:(NSEvent *)e { return [self.owner railMenu]; }

- (void)resetCursorRects {
    for (NSDictionary *r in self.hitRanges) {
        CGFloat x0 = [r[@"x0"] doubleValue], x1 = [r[@"x1"] doubleValue];
        [self addCursorRect:NSMakeRect(x0, 0, MAX(1, x1 - x0), NSHeight(self.bounds)) cursor:[NSCursor pointingHandCursor]];
    }
}

@end

#pragma mark - Indicator

@implementation FCPowerStatusIndicator {
    __weak NSPanel        *_clock;
    NSPanel               *_rail;
    FCPowerRailView       *_view;
    BOOL                   _showing;
    NSUInteger             _tick;
    FCPowerChangeObserver *_observer;
    BOOL                   _batteryDirty, _accessoryDirty, _devicesDirty;
    FCBatterySnapshot     *_battery;
    NSArray<FCAccessoryPart *> *_accessoryParts;
    NSArray<FCAccessoryPart *> *_btParts;
    NSArray<NSArray *>    *_paired;
    NSDictionary          *_hid;
    NSArray<FCBTDevice *> *_devices;
    int                    _power;          // 1 on, 0 off, -1 unknown
    BOOL                   _powerBusy;
    NSString              *_hintKeys;
    struct timespec        _hintMtime;
    NSMutableSet<NSString *> *_busyDevices;
    NSString              *_renderKey;
    CGFloat                _need;
    IOBluetoothUserNotification *_connectNote;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _power = -1;
        _busyDevices = [NSMutableSet set];
        _batteryDirty = _accessoryDirty = _devicesDirty = YES;
        [self buildRail];
        [[FCOverlayStack shared] registerRail:self order:FCStackOrderPower];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification object:nil];
        // The power request is honoured whether or not the rail is showing: a hotkey must work with
        // the rail hidden. Background apps need DeliverImmediately (see ClockVisibilityToggle.m).
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(powerRequest:)
                                                                name:FCBluetoothPowerNotificationName() object:nil
                                                  suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [_connectNote unregister];
}

#pragma mark Defaults

- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }
- (BOOL)enabled { return [[self d] boolForKey:@"PowerRailEnabled"]; }
- (FCBatteryField)fields { return FCBatteryFieldsFromIDs([[self d] arrayForKey:@"PowerRailBatteryFields"]); }
- (NSString *)registryPath {
    NSString *p = [[self d] stringForKey:@"PowerRailHotkeyRegistry"];
    return p.length ? [p stringByExpandingTildeInPath] : nil;
}

#pragma mark Panel

- (void)buildRail {
    NSRect r = NSMakeRect(0, 0, 200, kPwrHeight);
    _rail = FCCreateOverlayPanel(_clock, r.size, NO);   // interactive
    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 7.0;
    bg.layer.masksToBounds = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth = 1.0;
    bg.layer.borderColor = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _rail.contentView = bg;

    _view = [[FCPowerRailView alloc] initWithFrame:r];
    _view.owner = self;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTextField *l = [NSTextField labelWithString:@""];
    l.font = [self font];
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.frame = NSMakeRect(kPwrPadX, floor((kPwrHeight - kPwrLabelH) / 2.0), r.size.width - 2 * kPwrPadX, kPwrLabelH);
    l.autoresizingMask = NSViewWidthSizable;
    [_view addSubview:l];
    _view.label = l;
    [bg addSubview:_view];
    [_rail orderOut:nil];
}

- (NSFont *)font { return [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium]; }

- (NSColor *)colorForRole:(FCPowerRole)role {
    switch (role) {
        // Heading in amber-gold, distinct from NET (cyan) above and the violet device rail below.
        case FCPowerRoleHeading: return [NSColor colorWithSRGBRed:1.00 green:0.80 blue:0.36 alpha:1.0];
        case FCPowerRoleName:    return [NSColor colorWithSRGBRed:0.82 green:0.90 blue:1.00 alpha:1.0];
        case FCPowerRoleText:    return [NSColor colorWithWhite:1.0 alpha:0.86];
        case FCPowerRoleDim:     return [NSColor colorWithWhite:1.0 alpha:0.50];
        case FCPowerRoleHint:    return [NSColor colorWithWhite:1.0 alpha:0.38];
        case FCPowerRoleOK:      return [NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0];
        case FCPowerRoleWarn:    return [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0];
        case FCPowerRoleError:   return [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0];
    }
    return [NSColor whiteColor];
}

#pragma mark FCStackRail

- (BOOL)isShowing { return _showing; }
- (CGFloat)railHeight { return kPwrHeight; }
- (CGFloat)railGap { return kPwrGap; }

#pragma mark Reads

- (void)ensureObservers {
    if (!_observer) {
        __weak typeof(self) weak = self;
        _observer = [[FCPowerChangeObserver alloc] initWithHandler:^{
            typeof(self) me = weak; if (!me) return;
            me->_batteryDirty = YES; me->_accessoryDirty = YES;
            [me refreshNow];
        }];
    }
    if (!_connectNote) {
        _connectNote = [IOBluetoothDevice registerForConnectNotifications:self selector:@selector(btConnected:device:)];
    }
}

// IOBluetooth delivers these on its own thread, not the main one. Everything they lead to (reads,
// render, the overlay width consensus, -setFrame:) is AppKit or main-confined, and AppKit traps when
// a window is touched off the main thread ("Must only be used from the main thread", EXC_BREAKPOINT):
// on 2026-11-15 the clock crashed at launch whenever a device was connected, because registering for
// connect notifications reports every device already connected straight away. So hop first.
- (void)btConnected:(IOBluetoothUserNotification *)note device:(IOBluetoothDevice *)dev {
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) me = weak; if (!me) return;
        [dev registerForDisconnectNotification:me selector:@selector(btDisconnected:device:)];
        me->_devicesDirty = YES;
        [me refreshNow];
    });
}

- (void)btDisconnected:(IOBluetoothUserNotification *)note device:(IOBluetoothDevice *)dev {
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) me = weak; if (!me) return;
        [note unregister];
        me->_devicesDirty = YES;
        [me refreshNow];
    });
}

- (void)readHint {
    NSString *p = [self registryPath];
    struct stat st;
    if (!p || stat(p.fileSystemRepresentation, &st) != 0) { _hintKeys = nil; _hintMtime = (struct timespec){0}; return; }
    if (st.st_mtimespec.tv_sec == _hintMtime.tv_sec && st.st_mtimespec.tv_nsec == _hintMtime.tv_nsec) return;
    _hintMtime = st.st_mtimespec;
    _hintKeys = FCHotkeyKeysForCommand([NSData dataWithContentsOfFile:p], @[ @"--bluetooth", @"toggle" ]);
}

- (void)readAll {
    if (_batteryDirty || _tick % kBatteryEvery == 0) { _battery = FCReadBatterySnapshot(); _batteryDirty = NO; }
    if (!_powerBusy && (_tick % kPowerEvery == 0 || _power < 0)) _power = FCReadBluetoothPower();
    if (_accessoryDirty || _tick % kDevicesEvery == 0) { _accessoryParts = FCReadAccessoryParts(); _accessoryDirty = NO; }
    if (_power == 1 && (_devicesDirty || _tick % kDevicesEvery == 0)) {
        NSMutableArray *bt = [NSMutableArray array];
        _paired = FCReadPairedBluetoothDevices(bt);
        _btParts = bt;
        _devicesDirty = NO;
    }
    if (_power == 1 && (!_hid || _tick % kHIDEvery == 0)) _hid = FCReadHIDBatteryLevels();
    if (_tick % kHintEvery == 0 || !_hintMtime.tv_sec) [self readHint];
    NSArray *parts = [(_accessoryParts ?: @[]) arrayByAddingObjectsFromArray:_btParts ?: @[]];
    _devices = FCMergeBluetoothDevices(_power == 1 ? (_paired ?: @[]) : @[], parts, _hid ?: @{});
}

#pragma mark Refresh

- (void)refresh {
    _tick++;
    BOOL want = [self enabled] && !FCClockUserHidden();
    if (want != _showing) {
        _showing = want;
        if (!want) {
            FCHideOverlay(_rail);
            [[FCOverlayWidthConsensus shared] clearOverlay:NSStringFromClass(self.class)];
        }
        [[FCOverlayStack shared] noteChanged];
    }
    if (!want) return;
    [self ensureObservers];
    [self readAll];
    [self render];
    [self syncPosition];
}

- (void)refreshNow {
    // Main thread only (see -btConnected:device:); a caller on another thread is re-dispatched, not run.
    if (![NSThread isMainThread]) {
        __weak typeof(self) weak = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weak refreshNow]; });
        return;
    }
    if (!_showing) return;
    [self readAll];
    [self render];
    [self syncPosition];
}

- (void)render {
    NSArray *left = FCBatterySegments(_battery ?: [FCBatterySnapshot new], [self fields]);
    NSString *hint = FCChordGlyphs(_hintKeys);
    NSArray *right = FCBluetoothSegments(_power >= 0, _power == 1, hint, _devices ?: @[], kMaxDevices);
    if (_powerBusy) right = @[ right[0], @[ @" ◌ switching…", @(FCPowerRoleDim), @"" ] ];
    NSMutableArray *segs = [left mutableCopy];
    [segs addObject:@[ @"  │ ", @(FCPowerRoleDim), @"" ]];
    [segs addObjectsFromArray:right];

    NSMutableString *key = [NSMutableString string];
    NSMutableAttributedString *as = [NSMutableAttributedString new];
    NSFont *f = [self font];
    NSFont *fb = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy];
    NSMutableArray *hits = [NSMutableArray array];
    for (NSArray *seg in segs) {
        FCPowerRole role = (FCPowerRole)[seg[1] integerValue];
        NSString *action = seg[2];
        if ([action hasPrefix:@"bt.device:"] && [_busyDevices containsObject:[action substringFromIndex:10]]) role = FCPowerRoleDim;
        [key appendFormat:@"%@\x1f%ld\x1f%@\x1e", seg[0], (long)role, action];
        NSUInteger start = as.length;
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:seg[0] attributes:@{
            NSFontAttributeName: role == FCPowerRoleHeading ? fb : f,
            NSForegroundColorAttributeName: [self colorForRole:role] }]];
        if ([action length]) {
            // Clickable span: skip the segment's leading spaces so the target is the glyphs.
            NSString *text = seg[0];
            NSUInteger lead = 0;
            while (lead < text.length && [text characterAtIndex:lead] == ' ') lead++;
            CGFloat x0 = [[as attributedSubstringFromRange:NSMakeRange(0, start + lead)] size].width;
            CGFloat x1 = [as size].width;
            // NSTextField draws its text 2 pt in from the frame (line fragment padding).
            [hits addObject:@{ @"x0": @(kPwrPadX + 2 + x0), @"x1": @(kPwrPadX + 2 + x1), @"action": action }];
        }
    }
    [key appendFormat:@"%@", [self tooltip]];
    if ([key isEqualToString:_renderKey]) return;   // nothing visible changed
    _renderKey = key;
    _view.label.attributedStringValue = as;
    _view.hitRanges = hits;
    _view.toolTip = [self tooltip];
    [_rail invalidateCursorRectsForView:_view];
    // Width need from the content, rounded up to 24 pt so the stack does not breathe with each digit.
    CGFloat w = ceil(([as size].width + 2 * kPwrPadX + 6) / 24.0) * 24.0;
    if (fabs(w - _need) >= 0.5) {
        _need = w;
        [[FCOverlayWidthConsensus shared] setNeed:_need forOverlay:NSStringFromClass(self.class)];
    }
}

- (NSString *)tooltip {
    return [[self detailLines] componentsJoinedByString:@"\n"];
}

// Every battery fact, whatever the bar shows; then each device with all its levels.
- (NSArray<NSString *> *)detailLines {
    NSMutableArray *l = [NSMutableArray array];
    FCBatterySnapshot *b = _battery;
    if (!b.present) [l addObject:@"Battery: none (on AC)"];
    else {
        NSString *state = @{ @(FCBatteryStateCharging): @"charging", @(FCBatteryStateHeld): @"on AC, not charging",
                             @(FCBatteryStateFull): @"full", @(FCBatteryStateDischarging): @"on battery" }[@([b state])] ?: @"";
        [l addObject:[NSString stringWithFormat:@"Battery %ld%%, %@", (long)b.percent, state]];
        if ([b state] == FCBatteryStateHeld) {
            [l addObject:b.optimizedChargingEngaged ? @"  held by Optimized Battery Charging"
                                                    : [NSString stringWithFormat:@"  held (charge limit; reason code %ld)", (long)b.notChargingReason]];
        }
        NSString *tf = FCBatteryMinutesLabel(b.minutesToFull), *te = FCBatteryMinutesLabel(b.minutesToEmpty);
        if ([b state] == FCBatteryStateCharging && tf.length) [l addObject:[NSString stringWithFormat:@"  %@ to full", tf]];
        if ([b state] == FCBatteryStateDischarging && te.length) [l addObject:[NSString stringWithFormat:@"  %@ to empty", te]];
        if (b.voltageMV > 0) [l addObject:[NSString stringWithFormat:@"  %@ (%.2f V × %ld mA)", FCSignedWattsLabel([b watts]), b.voltageMV / 1000.0, (long)b.amperageMA]];
        if (b.onAC) [l addObject:[NSString stringWithFormat:@"  adapter %@%@", b.adapterWatts > 0 ? [NSString stringWithFormat:@"%ld W", (long)b.adapterWatts] : @"connected",
                                  b.adapterName.length ? [@" · " stringByAppendingString:b.adapterName] : @""]];
        double h = [b healthPercent];
        if (h > 0) [l addObject:[NSString stringWithFormat:@"  health %.1f%% (%ld of %ld mAh design)", h, (long)b.fullMAh, (long)b.designMAh]];
        if (b.cycles >= 0) [l addObject:[NSString stringWithFormat:@"  %ld cycles", (long)b.cycles]];
        if (!isnan(b.temperatureC)) [l addObject:[NSString stringWithFormat:@"  %.1f °C", b.temperatureC]];
    }
    [l addObject:_power < 0 ? @"Bluetooth: unknown" : (_power ? @"Bluetooth: on (click ● to turn off)" : @"Bluetooth: off (click ○ to turn on)")];
    if (_hintKeys.length) [l addObject:[NSString stringWithFormat:@"  shortcut %@ toggles it", FCChordGlyphs(_hintKeys)]];
    for (FCBTDevice *d in _devices) {
        NSMutableArray *lv = [NSMutableArray array];
        for (NSString *k in @[ @"", @"L", @"R", @"C" ]) {
            NSNumber *v = d.levels[k];
            if (!v) continue;
            NSString *name = @{ @"": @"battery", @"L": @"left", @"R": @"right", @"C": @"case" }[k];
            [lv addObject:[NSString stringWithFormat:@"%@ %ld%%", name, (long)v.integerValue]];
        }
        [l addObject:[NSString stringWithFormat:@"  %@ — %@%@%@", d.name, d.connected ? @"connected" : @"not connected",
                      lv.count ? [@", " stringByAppendingString:[lv componentsJoinedByString:@", "]] : @"",
                      d.charging ? @", charging" : @""]];
    }
    return l;
}

#pragma mark Actions

- (void)performAction:(NSString *)action {
    if ([action isEqualToString:@"bt.power"]) {
        [self setPower:@"toggle" source:@"click"];
    } else if ([action hasPrefix:@"bt.device:"]) {
        [self toggleDevice:[action substringFromIndex:10]];
    }
}

- (void)powerRequest:(NSNotification *)n {
    NSString *state = [n.userInfo[@"state"] isKindOfClass:[NSString class]] ? n.userInfo[@"state"] : @"toggle";
    [self setPower:state source:@"notification"];
}

- (void)setPower:(NSString *)state source:(NSString *)source {
    if (_powerBusy) return;
    int now = FCReadBluetoothPower();
    if (now < 0) { os_log_error(FCPwrLog(), "bluetooth power: the private setter is missing"); return; }
    BOOL want = [state isEqualToString:@"toggle"] ? !now : [state isEqualToString:@"on"];
    if ((want ? 1 : 0) == now) { _power = now; [self refreshNow]; return; }
    _powerBusy = YES;
    os_log(FCPwrLog(), "bluetooth power -> %{public}s (%{public}@)", want ? "on" : "off", source);
    [self refreshNow];
    __weak typeof(self) weak = self;
    FCSetBluetoothPower(want, ^(BOOL reached) {
        typeof(self) me = weak; if (!me) return;
        me->_powerBusy = NO;
        me->_power = FCReadBluetoothPower();
        me->_devicesDirty = YES;
        if (!reached) os_log_error(FCPwrLog(), "bluetooth power did not reach %{public}s within 10 s", want ? "on" : "off");
        [me refreshNow];
    });
}

- (void)toggleDevice:(NSString *)address {
    if ([_busyDevices containsObject:address]) return;
    BOOL connected = NO;
    for (NSArray *p in _paired) if ([p[1] isEqualToString:address]) connected = [p[2] boolValue];
    if (connected) {
        BOOL ok = FCDisconnectBluetoothDevice(address);
        os_log(FCPwrLog(), "disconnect %{public}@: %{public}s", address, ok ? "ok" : "failed");
        _devicesDirty = YES;
        [self refreshNow];
        return;
    }
    [_busyDevices addObject:address];
    _renderKey = nil;
    [self refreshNow];
    __weak typeof(self) weak = self;
    [FCBluetoothPairedAudioDeviceConnector connectDeviceWithAddress:address timeout:8.0 completion:^(BOOL success, NSString *reason) {
        typeof(self) me = weak; if (!me) return;
        [me->_busyDevices removeObject:address];
        if (!success) os_log_error(FCPwrLog(), "connect %{public}@ failed: %{public}@", address, reason ?: @"");
        me->_devicesDirty = YES;
        me->_renderKey = nil;
        [me refreshNow];
    }];
}

#pragma mark Menu

- (NSMenu *)railMenu {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Power"];
    m.autoenablesItems = NO;

    NSString *hint = FCChordGlyphs(_hintKeys);
    NSMenuItem *pw = [[NSMenuItem alloc] initWithTitle:(_power == 1 ? @"Turn Bluetooth Off" : @"Turn Bluetooth On")
                                                action:@selector(menuTogglePower:) keyEquivalent:@""];
    pw.target = self;
    pw.enabled = _power >= 0 && !_powerBusy;
    if (hint.length) pw.toolTip = [NSString stringWithFormat:@"Shortcut: %@", hint];
    if (hint.length) pw.title = [pw.title stringByAppendingFormat:@"    %@", hint];
    [m addItem:pw];

    if (_power == 1) {
        [m addItem:[NSMenuItem separatorItem]];
        NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"Devices — click to connect or disconnect" action:nil keyEquivalent:@""];
        hdr.enabled = NO;
        [m addItem:hdr];
        NSMutableDictionary *levels = [NSMutableDictionary dictionary];
        for (FCBTDevice *d in _devices) if (d.name) levels[d.name] = d;
        for (NSArray *p in _paired) {
            FCBTDevice *d = levels[p[0]];
            NSMutableArray *lv = [NSMutableArray array];
            for (NSString *k in @[ @"", @"L", @"R", @"C" ]) {
                NSNumber *v = d.levels[k];
                if (v) [lv addObject:k.length ? [NSString stringWithFormat:@"%@%ld", k, (long)v.integerValue] : [NSString stringWithFormat:@"%ld%%", (long)v.integerValue]];
            }
            NSString *title = lv.count ? [NSString stringWithFormat:@"%@   %@", p[0], [lv componentsJoinedByString:@" "]] : p[0];
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuToggleDevice:) keyEquivalent:@""];
            it.target = self;
            it.representedObject = p[1];
            it.state = [p[2] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
            it.enabled = ![_busyDevices containsObject:p[1]];
            [m addItem:it];
        }
    }

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *show = [[NSMenuItem alloc] initWithTitle:@"Show on Bar" action:nil keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@"Show on Bar"];
    sub.autoenablesItems = NO;
    FCBatteryField on = [self fields];
    for (NSString *fid in FCBatteryFieldIDs()) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:FCBatteryFieldTitle(fid) action:@selector(menuToggleField:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = fid;
        it.state = (on & FCBatteryFieldForID(fid)) ? NSControlStateValueOn : NSControlStateValueOff;
        [sub addItem:it];
    }
    show.submenu = sub;
    [m addItem:show];

    NSMenuItem *details = [[NSMenuItem alloc] initWithTitle:@"Details" action:nil keyEquivalent:@""];
    NSMenu *dsub = [[NSMenu alloc] initWithTitle:@"Details"];
    for (NSString *line in [self detailLines]) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:line action:nil keyEquivalent:@""];
        it.enabled = NO;
        [dsub addItem:it];
    }
    details.submenu = dsub;
    [m addItem:details];

    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Bluetooth Settings…" action:@selector(menuOpenSettings:) keyEquivalent:@""];
    settings.target = self;
    [m addItem:settings];
    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:@"Hide Power Rail" action:@selector(menuHide:) keyEquivalent:@""];
    hide.target = self;
    [m addItem:hide];
    return m;
}

- (void)menuTogglePower:(id)sender { [self setPower:@"toggle" source:@"menu"]; }
- (void)menuToggleDevice:(NSMenuItem *)sender { [self toggleDevice:sender.representedObject]; }

- (void)menuToggleField:(NSMenuItem *)sender {
    NSString *fid = sender.representedObject;
    FCBatteryField f = [self fields] ^ FCBatteryFieldForID(fid);
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *x in FCBatteryFieldIDs()) if (f & FCBatteryFieldForID(x)) [ids addObject:x];
    [[self d] setObject:ids forKey:@"PowerRailBatteryFields"];
    _renderKey = nil;
    [self refreshNow];
}

- (void)menuOpenSettings:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.BluetoothSettings"]];
}

- (void)menuHide:(id)sender {
    [[self d] setBool:NO forKey:@"PowerRailEnabled"];
    [self refresh];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || !_showing || FCClockUserHidden()) return;
    NSRect c = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf = s ? s.visibleFrame : c;
    // The audio bar, mic-mute and VPN banners sit below this rail and are not registered rails, so their
    // slots are counted here, exactly as the network rail counts them.
    CGFloat slot = 20.0 + 3.0;
    CGFloat offset = 0.0;
    if (self.audioIndicator && [self.audioIndicator isShowing]) offset += slot;
    if (self.micIndicator && [self.micIndicator isShowing]) offset += slot;
    if (self.vpnIndicator && [self.vpnIndicator isShowing]) offset += slot;
    offset += [[FCOverlayStack shared] offsetBelowOrder:FCStackOrderPower];
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kPwrHeight, offset, kPwrGap, agreed);
    if (!NSEqualRects(f, _rail.frame)) [_rail setFrame:f display:YES];
    if (!_rail.visible) [_rail orderFront:nil];
    [_rail orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _rail);
}

@end
