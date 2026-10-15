#import "DeviceDockIndicator.h"
#import "DeviceRailModel.h"
#import "AudioStatusIndicator.h"
#include <errno.h>
#import "ClockVisibilityToggle.h"
#import "ClockChildWindowAttachment.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import <IOKit/IOKitLib.h>
#include <signal.h>
#include <sys/stat.h>

static const CGFloat kDevRailHeight = 20.0;
static const CGFloat kDevRailGap    = 3.0;
static const CGFloat kDevRailPadX   = 8.0;
// Text is laid out at this fixed height and centred in the rail, the same constant the network and
// audio rails use (see NetworkBarZoneView.m kLabelH): an NSTextField centres glyphs in its own frame
// using metrics that include leading, so a taller field parks the text above centre.
static const CGFloat kDevRailLabelH = 14.0;
static const double  kBlipWindow    = 10.0;   // gone-and-back within this = a re-attach blip
static const double  kBlipShow      = 5.0;

#pragma mark - IOKit (in-process registry reads)

static NSString *FCPortDescription(io_registry_entry_t e) {
    CFTypeRef v = IORegistryEntryCreateCFProperty(e, CFSTR("PortDescription"), kCFAllocatorDefault, 0);
    if (!v) return nil;
    NSString *s = [(__bridge id)v isKindOfClass:[NSString class]] ? [(__bridge NSString *)v copy] : nil;
    CFRelease(v);
    return s;
}

// Is the watched device enumerated? If so, which USB-C port (IOPort plane ancestor) carries it.
static BOOL FCFindDevice(int vid, int pid, NSString *_Nullable *_Nullable port) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) return NO;
    CFDictionarySetValue(match, CFSTR("idVendor"), (__bridge CFNumberRef)@(vid));
    CFDictionarySetValue(match, CFSTR("idProduct"), (__bridge CFNumberRef)@(pid));
    io_service_t dev = IOServiceGetMatchingService(kIOMainPortDefault, match);   // consumes `match`
    if (!dev) return NO;
    NSString *found = nil;
    io_registry_entry_t cur = dev; IOObjectRetain(cur);
    for (int depth = 0; depth < 12 && !found; depth++) {
        io_registry_entry_t parent = 0;
        if (IORegistryEntryGetParentEntry(cur, "IOPort", &parent) != KERN_SUCCESS) break;
        IOObjectRelease(cur);
        cur = parent;
        found = FCPortDescription(cur);
    }
    IOObjectRelease(cur);
    IOObjectRelease(dev);
    if (port) *port = found;
    return YES;
}

// ConnectionActive of the named port (NO if the port is not found).
static BOOL FCPortConnected(NSString *portDescription) {
    io_iterator_t it = 0;
    if (IORegistryCreateIterator(kIOMainPortDefault, "IOPort", kIORegistryIterateRecursively, &it) != KERN_SUCCESS) return NO;
    BOOL connected = NO, done = NO;
    io_registry_entry_t e;
    while (!done && (e = IOIteratorNext(it))) {
        if ([FCPortDescription(e) isEqualToString:portDescription]) {
            CFTypeRef v = IORegistryEntryCreateCFProperty(e, CFSTR("ConnectionActive"), kCFAllocatorDefault, 0);
            connected = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
            if (v) CFRelease(v);
            done = YES;
        }
        IOObjectRelease(e);
    }
    IOObjectRelease(it);
    return connected;
}

#pragma mark - Indicator

@implementation FCDeviceDockIndicator {
    __weak NSPanel      *_clock;
    NSPanel             *_rail;
    NSTextField         *_label;
    BOOL                 _showing;
    FCDockState          _state;
    NSDate              *_stateSince;
    NSDate              *_lostAt;        // device vanished while its port stayed connected
    NSDate              *_blipUntil;
    FCDeviceRailStatus  *_status;
    struct timespec      _statusMtime;
    NSUInteger           _spin;
    dispatch_source_t    _fast;          // 4 Hz while a job is running
    NSString            *_renderKey;
    CGFloat              _need;
    BOOL                 _firstReadDone;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _state = FCDockStateUnknown;
        [self buildRail];
        [[FCOverlayStack shared] registerRail:self order:FCStackOrderExternalStatus];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_fast) dispatch_source_cancel(_fast);
}

#pragma mark Defaults

- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }
- (BOOL)enabled { return [[self d] boolForKey:@"DeviceRailEnabled"]; }
- (int)vendorID { return (int)[[self d] integerForKey:@"DeviceRailVendorID"]; }
- (int)productID { return (int)[[self d] integerForKey:@"DeviceRailProductID"]; }
- (NSString *)label { NSString *s = [[self d] stringForKey:@"DeviceRailLabel"]; return s.length ? s : @"USB"; }
- (NSString *)name { return [[self d] stringForKey:@"DeviceRailName"]; }
- (NSString *)tag { return [[self d] stringForKey:@"DeviceRailTag"]; }
- (NSString *)statusPath {
    NSString *p = [[self d] stringForKey:@"DeviceRailStatusFile"];
    return p.length ? [p stringByExpandingTildeInPath] : nil;
}

#pragma mark Panel

- (void)buildRail {
    NSRect r = NSMakeRect(0, 0, 200, kDevRailHeight);
    _rail = FCCreateOverlayPanel(_clock, r.size, YES);
    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 7.0;
    bg.layer.masksToBounds = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth = 1.0;
    bg.layer.borderColor = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _rail.contentView = bg;

    NSTextField *l = [NSTextField labelWithString:@""];
    l.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.frame = NSMakeRect(kDevRailPadX, floor((kDevRailHeight - kDevRailLabelH) / 2.0), r.size.width - 2 * kDevRailPadX, kDevRailLabelH);
    l.autoresizingMask = NSViewWidthSizable;
    [bg addSubview:l];
    _label = l;
    [_rail orderOut:nil];
}

- (NSColor *)colorForRole:(FCRailRole)role {
    switch (role) {
        // Heading in violet: distinct from the rails around it (NET cyan above, IN green / OUT blue below).
        case FCRailRoleLabel:  return [NSColor colorWithSRGBRed:0.74 green:0.56 blue:1.00 alpha:1.0];
        case FCRailRoleName:   return [NSColor colorWithSRGBRed:0.88 green:0.82 blue:1.00 alpha:1.0];
        case FCRailRoleText:   return [NSColor colorWithWhite:1.0 alpha:0.86];
        case FCRailRoleDim:    return [NSColor colorWithWhite:1.0 alpha:0.50];
        case FCRailRoleOK:     return [NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0];
        case FCRailRoleActive: return [NSColor colorWithSRGBRed:0.38 green:0.78 blue:1.00 alpha:1.0];
        case FCRailRoleWarn:   return [NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0];
        case FCRailRoleError:  return [NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0];
    }
    return [NSColor whiteColor];
}

#pragma mark FCStackRail

- (BOOL)isShowing { return _showing; }
- (CGFloat)railHeight { return kDevRailHeight; }
- (CGFloat)railGap { return kDevRailGap; }

#pragma mark Refresh

- (void)readDock {
    int vid = [self vendorID], pid = [self productID];
    NSString *port = nil;
    BOOL present = (vid > 0 && pid > 0) && FCFindDevice(vid, pid, &port);
    NSString *dockPort = [[self d] stringForKey:@"DeviceRailDockPort"];
    if (present && port.length && ![port isEqualToString:dockPort]) {
        [[self d] setObject:port forKey:@"DeviceRailDockPort"];
        dockPort = port;
    }
    BOOL connected = dockPort.length ? FCPortConnected(dockPort) : NO;
    FCDockState s = FCDeriveDockState(present, dockPort.length > 0, connected);
    NSDate *now = [NSDate date];
    if (s != _state) {
        // The first reading after launch is not a transition we saw: show no age for it rather than
        // an age counted from the clock's own start.
        if (_state == FCDockStateUnknown && !_stateSince && !_firstReadDone) {
            _firstReadDone = YES;
            _state = s;
            return;
        }
        if (_state == FCDockStateAttached && s == FCDockStateEmpty) _lostAt = now;
        if (s == FCDockStateAttached && _lostAt && -[_lostAt timeIntervalSinceNow] < kBlipWindow) {
            _blipUntil = [now dateByAddingTimeInterval:kBlipShow];   // re-attached moments later
            // A blip is the same docking session: keep the original "docked since".
            _state = s; _lostAt = nil;
            return;
        }
        if (s != FCDockStateEmpty) _lostAt = nil;
        _state = s;
        _stateSince = now;
    }
}

- (void)readStatus {
    NSString *p = [self statusPath];
    if (!p) { _status = nil; return; }
    struct stat st;
    if (stat(p.fileSystemRepresentation, &st) != 0) { _status = nil; return; }
    if (_status && st.st_mtimespec.tv_sec == _statusMtime.tv_sec && st.st_mtimespec.tv_nsec == _statusMtime.tv_nsec) return;
    _statusMtime = st.st_mtimespec;
    NSData *data = [NSData dataWithContentsOfFile:p];
    _status = data ? [FCDeviceRailStatus statusFromJSONData:data] : nil;
}

- (BOOL)jobAlive {
    return _status && _status.pid > 0 && (kill(_status.pid, 0) == 0 || errno == EPERM);
}

- (void)render {
    double secs = _stateSince ? -[_stateSince timeIntervalSinceNow] : -1;
    BOOL blip = _blipUntil && [_blipUntil timeIntervalSinceNow] > 0;
    if (!_stateSince) secs = -1;
    BOOL alive = [self jobAlive];
    NSArray *segs = FCDeviceRailSegments([self label], [self name], [self tag], _state, _state == FCDockStateUnknown ? -1 : secs,
                                         blip, _status, alive, _spin);
    NSMutableString *key = [NSMutableString string];
    NSMutableAttributedString *as = [NSMutableAttributedString new];
    NSFont *f = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
    NSFont *fb = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightHeavy];
    for (NSArray *seg in segs) {
        FCRailRole role = (FCRailRole)[seg[1] integerValue];
        [key appendFormat:@"%@\x1f%ld\x1e", seg[0], (long)role];
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:seg[0] attributes:@{
            NSFontAttributeName: role == FCRailRoleLabel ? fb : f,
            NSForegroundColorAttributeName: [self colorForRole:role] }]];
    }
    if ([key isEqualToString:_renderKey]) return;   // nothing visible changed
    _renderKey = key;
    _label.attributedStringValue = as;
}

- (void)updateFastTimer {
    BOOL want = _showing && [self jobAlive] && [_status.tone isEqualToString:@"active"];
    if (want && !_fast) {
        _fast = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(_fast, DISPATCH_TIME_NOW, NSEC_PER_SEC / 4, NSEC_PER_MSEC * 20);
        __weak typeof(self) weak = self;
        dispatch_source_set_event_handler(_fast, ^{
            typeof(self) me = weak; if (!me) return;
            me->_spin++;
            [me readStatus];
            [me render];
            [me updateFastTimer];
        });
        dispatch_resume(_fast);
    } else if (!want && _fast) {
        dispatch_source_cancel(_fast);
        _fast = nil;
    }
}

- (void)refresh {
    BOOL want = [self enabled] && !FCClockUserHidden();
    if (want != _showing) {
        _showing = want;
        if (!want) {
            FCHideOverlay(_rail);
            [[FCOverlayWidthConsensus shared] clearOverlay:NSStringFromClass(self.class)];
        }
        [[FCOverlayStack shared] noteChanged];
    }
    [self updateFastTimer];
    if (!want) return;
    [self readDock];
    [self readStatus];
    [self render];
    [self publishNeed];
    [self syncPosition];
}

// One constant need, measured from the widest template line, so the stack never breathes with the text.
- (void)publishNeed {
    if (_need <= 0) {
        NSFont *f = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
        NSString *head = [self label];
        if ([self name].length) head = [head stringByAppendingFormat:@" %@", [self name]];
        if ([self tag].length) head = [head stringByAppendingFormat:@" %@", [self tag]];
        NSString *tpl = [NSString stringWithFormat:@"%@ ● docked 23h59m  │ ◐ ▰▰▰▰▰▰ upload 99/99 ██████████ 100%% · 999.9 MB/s", head];
        _need = ceil([tpl sizeWithAttributes:@{ NSFontAttributeName: f }].width) + 2 * kDevRailPadX + 4;
    }
    [[FCOverlayWidthConsensus shared] setNeed:_need forOverlay:NSStringFromClass(self.class)];
}

- (void)syncPosition {
    if (!_clock || !_showing || FCClockUserHidden()) return;
    NSRect c = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf = s ? s.visibleFrame : c;
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    // Audio bar sits below this rail; it is not a registered rail, so count its slot here.
    CGFloat offset = [[FCOverlayStack shared] offsetBelowOrder:FCStackOrderExternalStatus];
    if (self.audioIndicator && [self.audioIndicator isShowing]) offset += 20.0 + 3.0;
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kDevRailHeight, offset, kDevRailGap, agreed);
    if (!NSEqualRects(f, _rail.frame)) [_rail setFrame:f display:YES];
    if (!_rail.visible) [_rail orderFront:nil];
    [_rail orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _rail);
}

@end
