// Window placement + persistence — split from FloatingClockPanel+Runtime
// during the 2026-06-12 modularization (Runtime.m had breached the
// 500-line cap). Owns screen selection, the default frame, visible-frame
// clamping, frame persistence on user drags, and hot-unplug re-homing.
#import "FloatingClockPanel+WindowPlacement.h"
#import "FloatingClockPanel+Layout.h"      // applyDisplaySettings (re-home)
#import "MicMuteIndicator.h"               // overlay re-sync on moves
#import "VPNStatusIndicator.h"
#import "AudioStatusIndicator.h"

@implementation FloatingClockPanel (WindowPlacement)

// Primary display = screens[0] (with menu bar at origin). mainScreen is
// indeterminate for LSUIElement apps before a window is key.
- (NSScreen *)primaryScreen {
    NSArray<NSScreen *> *all = [NSScreen screens];
    if (all.count > 0) return all.firstObject;
    return [NSScreen mainScreen];
}

- (NSRect)defaultFrame {
    NSScreen *s = [self primaryScreen];
    NSRect vf = s.visibleFrame;
    NSRect f = self.frame;
    CGFloat x = vf.origin.x + (vf.size.width - f.size.width) / 2.0;
    CGFloat y = vf.origin.y + 24;
    return NSMakeRect(x, y, f.size.width, f.size.height);
}

- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed {
    NSScreen *s = self.screen ?: [self primaryScreen];
    NSRect vf = s.visibleFrame;
    NSRect r = proposed;
    if (r.size.width > vf.size.width)  r.size.width  = vf.size.width;
    if (r.size.height > vf.size.height) r.size.height = vf.size.height;
    if (NSMaxX(r) > NSMaxX(vf)) r.origin.x = NSMaxX(vf) - r.size.width;
    if (NSMaxY(r) > NSMaxY(vf)) r.origin.y = NSMaxY(vf) - r.size.height;
    if (r.origin.x < vf.origin.x) r.origin.x = vf.origin.x;
    if (r.origin.y < vf.origin.y) r.origin.y = vf.origin.y;
    return r;
}

- (void)windowDidMove:(NSNotification *)n {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:NSStringFromRect(self.frame) forKey:@"FloatingClockWindowFrame"];
    NSNumber *sn = self.screen.deviceDescription[@"NSScreenNumber"];
    if ([sn isKindOfClass:[NSNumber class]]) {
        [d setObject:sn forKey:@"FloatingClockScreenNumber"];
    }
    // Keep the indicator stack glued to the clock while the user drags it.
    [_micMuteIndicator syncPosition];
    [_vpnStatusIndicator syncPosition];
    [_audioStatusIndicator syncPosition];
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
                    if (NSIntersectsRect(r, s.frame)) {
                        [self setFrame:r display:NO];
                        return;
                    }
                    NSRect vf = s.visibleFrame;
                    NSRect clamped = r;
                    clamped.origin.x = MAX(vf.origin.x, MIN(r.origin.x, NSMaxX(vf) - r.size.width));
                    clamped.origin.y = MAX(vf.origin.y, MIN(r.origin.y, NSMaxY(vf) - r.size.height));
                    [self setFrame:clamped display:NO];
                    return;
                }
            }
        }
    }
    [self setFrame:[self defaultFrame] display:NO];
}

- (void)screensChanged:(NSNotification *)n {
    BOOL onLiveScreen = NO;
    for (NSScreen *s in [NSScreen screens]) {
        if (NSIntersectsRect(self.frame, s.frame)) { onLiveScreen = YES; break; }
    }
    if (!onLiveScreen) {
        [self setFrame:[self defaultFrame] display:YES animate:YES];
        NSNumber *sn = [self primaryScreen].deviceDescription[@"NSScreenNumber"];
        if ([sn isKindOfClass:[NSNumber class]]) {
            [[NSUserDefaults standardUserDefaults] setObject:sn forKey:@"FloatingClockScreenNumber"];
        }
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(self.frame)
                                                  forKey:@"FloatingClockWindowFrame"];
    }
}

@end
