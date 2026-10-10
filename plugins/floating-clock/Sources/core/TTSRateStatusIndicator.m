#import "TTSRateStatusIndicator.h"
#import "ClockVisibilityToggle.h"   // FCClockUserHidden(): whole-clock hide (2026-10-10)
#import "TTSRateBarZoneView.h"
#import "TTSRateHelpers.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import "ClockChildWindowAttachment.h"
#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "VPNStatusIndicator.h"
#import "NetworkStatusIndicator.h"
#import "BrightnessStatusIndicator.h"
#include <sys/stat.h>

static const CGFloat kTTSBarHeight = 20.0;   // matches the other rails
static const CGFloat kTTSBarGap    = 3.0;
static const CGFloat kMinBarW      = 160.0;

@implementation FCTTSRateStatusIndicator {
    __weak NSPanel     *_clock;
    NSPanel            *_bar;
    FCTTSRateZoneView  *_zone;
    CGFloat             _contentNeed;
    CGFloat             _lastBarW;
    double              _rate;
    struct timespec     _fileMtime;
    BOOL                _haveMtime;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _lastBarW = -1.0;
        _rate = FCTTSRateMin;
        [self buildBar];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification
                                                   object:nil];
        [self refresh];
    }
    return self;
}

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"TTSBarEnabled"];
}

- (BOOL)isShowing { return [self enabled]; }

- (void)buildBar {
    NSRect r = NSMakeRect(0, 0, 200, kTTSBarHeight);
    _bar = FCCreateOverlayPanel(_clock, r.size, NO);   // interactive
    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth     = 1.0;
    bg.layer.borderColor     = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _bar.contentView         = bg;
    _zone = [[FCTTSRateZoneView alloc] initWithFrame:r owner:self];
    _zone.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [bg addSubview:_zone];
    [_bar orderOut:nil];
}

#pragma mark Refresh

// Re-read the rate file only when its modification time moved: one stat(2) a
// second at steady state.
- (void)pollFile {
    NSString *path = FCTTSRateFilePath();
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) {
        _haveMtime = NO;
        _rate = FCTTSRateMin;   // no file = the reader's normal speed
        return;
    }
    if (_haveMtime && st.st_mtimespec.tv_sec == _fileMtime.tv_sec &&
        st.st_mtimespec.tv_nsec == _fileMtime.tv_nsec) return;
    _fileMtime = st.st_mtimespec;
    _haveMtime = YES;
    double r = FCTTSReadRateFile(path);
    _rate = isnan(r) ? FCTTSRateMin : r;
}

- (void)refresh {
    if (![self enabled] || FCClockUserHidden()) {
        FCHideOverlay(_bar);
        [[FCOverlayWidthConsensus shared] clearOverlay:NSStringFromClass(self.class)];
        return;
    }
    [self pollFile];
    [self render];
}

- (void)render {
    if (![self enabled]) return;
    BOOL changed = [_zone renderRate:_rate];
    if (changed || _contentNeed <= 0.0) {
        _contentNeed = [_zone naturalContentWidth];
        if (_contentNeed < kMinBarW) _contentNeed = kMinBarW;
        [[FCOverlayWidthConsensus shared] setNeed:_contentNeed forOverlay:NSStringFromClass(self.class)];
    }
    [self syncPosition];
}

#pragma mark Positioning

- (void)syncPosition {
    if (!_clock || ![self enabled] || FCClockUserHidden()) return;
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;
    // TOP of the stack, above the brightness rail: one slot per visible junior.
    CGFloat slot = kTTSBarHeight + kTTSBarGap;
    CGFloat offset = 0.0;
    if (self.audioIndicator      && [self.audioIndicator      isShowing]) offset += slot;
    if (self.micIndicator        && [self.micIndicator        isShowing]) offset += slot;
    if (self.vpnIndicator        && [self.vpnIndicator        isShowing]) offset += slot;
    if (self.networkIndicator    && [self.networkIndicator    isShowing]) offset += slot;
    if (self.brightnessIndicator && [self.brightnessIndicator isShowing]) offset += slot;
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kTTSBarHeight, offset, kTTSBarGap, agreed);
    if (!NSEqualRects(f, _bar.frame)) [_bar setFrame:f display:YES];
    if (fabs(f.size.width - _lastBarW) >= 0.5) {
        _lastBarW = f.size.width;
        _zone.frame = NSMakeRect(0, 0, f.size.width, kTTSBarHeight);
        _zone.needsLayout = YES;
        _zone.needsDisplay = YES;
    }
    if (!_bar.visible) [_bar orderFront:nil];
    [_bar orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _bar);
}

#pragma mark User actions

- (void)setRate:(double)rate {
    double r = FCTTSRateClamp(rate);
    if (fabs(r - _rate) < 1e-6) return;   // no file churn on a drag held on one detent
    if (!FCTTSWriteRateFile(FCTTSRateFilePath(), r)) {
        NSLog(@"[tts-rate] could not write %@", FCTTSRateFilePath());
        return;
    }
    _rate = r;   // the next tick sees the new mtime and re-reads the same value
    [self render];
}

- (void)adjustRateBy:(double)delta {
    [self setRate:FCTTSRateApplyDelta(_rate, delta)];
}

- (NSMenu *)presetMenu {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Speech speed"];
    NSMenuItem *hdr = [[NSMenuItem alloc] initWithTitle:@"TEXT-TO-SPEECH SPEED" action:NULL keyEquivalent:@""];
    hdr.enabled = NO;
    [m addItem:hdr];
    NSUInteger n = 0;
    const double *d = FCTTSRateDetents(&n);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *title = (i == 0) ? [NSString stringWithFormat:@"%@  (normal)", FCTTSRateLabel(d[i])]
                                   : FCTTSRateLabel(d[i]);
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuPickRate:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = @(d[i]);
        it.state = fabs(_rate - d[i]) < 0.001 ? NSControlStateValueOn : NSControlStateValueOff;
        [m addItem:it];
    }
    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *f = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Rate file: %@",
                        [FCTTSRateFilePath() stringByAbbreviatingWithTildeInPath]] action:NULL keyEquivalent:@""];
    f.enabled = NO;
    [m addItem:f];
    NSMenuItem *why = [[NSMenuItem alloc] initWithTitle:@"Applies live, mid-sentence, to a reader following this file"
                                                 action:NULL keyEquivalent:@""];
    why.enabled = NO;
    [m addItem:why];
    return m;
}

- (void)menuPickRate:(NSMenuItem *)sender {
    if (![sender.representedObject isKindOfClass:[NSNumber class]]) return;
    [self setRate:[(NSNumber *)sender.representedObject doubleValue]];
}

@end
