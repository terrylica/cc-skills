#import "LevelMeterIndicator.h"
#import "AudioStatusIndicator.h"
#import "MicMuteIndicator.h"
#import "OutputLevelTap.h"
#import "LevelMeterMath.h"
#import "ClockVisibilityToggle.h"
#import "ClockChildWindowAttachment.h"
#import "OverlayPanelFactory.h"
#import "OverlayStackingPositioner.h"
#import "OverlayWidthConsensus.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMeterRailHeight = 9.0;
static const CGFloat kMeterRailGap    = 3.0;
static const CGFloat kMeterInsetX     = 7.0;
static const CGFloat kCellW           = 2.0;
static const CGFloat kCellPitch       = 3.0;   // 2 pt cell + 1 pt gap
static const CGFloat kCellH           = 4.0;
static const double  kFrameHz         = 24.0;   // film rate: smooth for a meter, ~20% cheaper than 30

// One meter half: dim track cells, lit gradient cells clipped to the level, and a peak tick.
@interface FCMeterBar : NSObject
@property (nonatomic, readonly) CALayer *root;
- (instancetype)initWithColors:(NSArray *)gradientColors;
- (void)layoutInRect:(CGRect)r;
- (void)showFraction:(double)level peak:(double)peak available:(BOOL)available;
@end

@implementation FCMeterBar {
    CAReplicatorLayer *_track;
    CALayer           *_trackCell;
    CALayer           *_clip;
    CAGradientLayer   *_fill;
    CAReplicatorLayer *_fillMask;
    CALayer           *_fillCell;
    CALayer           *_peak;
    CGRect             _rect;
    NSInteger          _cells;
    NSInteger          _shownLit, _shownPeak;   // what is on screen; frames that change nothing skip Core Animation
    BOOL               _shownAvail;
}

- (instancetype)initWithColors:(NSArray *)gradientColors {
    if ((self = [super init])) {
        _root = [CALayer layer];
        _track = [CAReplicatorLayer layer];
        _trackCell = [CALayer layer];
        _trackCell.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.10] CGColor];
        _trackCell.cornerRadius = 0.5;
        [_track addSublayer:_trackCell];
        [_root addSublayer:_track];

        _clip = [CALayer layer];
        _clip.masksToBounds = YES;
        _clip.anchorPoint = CGPointZero;
        _fill = [CAGradientLayer layer];
        _fill.startPoint = CGPointMake(0, 0.5);
        _fill.endPoint = CGPointMake(1, 0.5);
        _fill.colors = gradientColors;
        // Green/blue body, amber from -12 dBFS (0.8 of -60..0), red from -3 dBFS (0.95).
        _fill.locations = @[ @0.0, @0.78, @0.80, @0.93, @0.95, @1.0 ];
        _fillMask = [CAReplicatorLayer layer];
        _fillCell = [CALayer layer];
        _fillCell.backgroundColor = [[NSColor whiteColor] CGColor];
        _fillCell.cornerRadius = 0.5;
        [_fillMask addSublayer:_fillCell];
        _fill.mask = _fillMask;
        [_clip addSublayer:_fill];
        [_root addSublayer:_clip];

        _peak = [CALayer layer];
        _peak.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.85] CGColor];
        [_root addSublayer:_peak];
    }
    return self;
}

- (void)layoutInRect:(CGRect)r {
    _rect = r;
    _cells = MAX(1, (NSInteger)floor((r.size.width + (kCellPitch - kCellW)) / kCellPitch));
    CGFloat w = _cells * kCellPitch - (kCellPitch - kCellW);
    CGRect inner = CGRectMake(0, 0, w, kCellH);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _root.frame = CGRectMake(r.origin.x, r.origin.y + (r.size.height - kCellH) / 2.0, w, kCellH);
    for (CAReplicatorLayer *rep in @[ _track, _fillMask ]) {
        rep.frame = inner;
        rep.instanceCount = _cells;
        rep.instanceTransform = CATransform3DMakeTranslation(kCellPitch, 0, 0);
    }
    _trackCell.frame = CGRectMake(0, 0, kCellW, kCellH);
    _fillCell.frame  = CGRectMake(0, 0, kCellW, kCellH);
    _fill.frame = inner;
    _clip.frame = CGRectMake(0, 0, 0, kCellH);
    _peak.frame = CGRectMake(0, -0.5, 1.0, kCellH + 1.0);
    _peak.hidden = YES;
    [CATransaction commit];
    _shownLit = -1; _shownPeak = -2;
}

- (void)showFraction:(double)level peak:(double)peak available:(BOOL)available {
    // Cells are discrete, so most 24 Hz frames change nothing visible: compare cell indices first.
    NSInteger litCells = (NSInteger)llround(level * (double)_cells);
    NSInteger peakCell = (peak > 0.02 && available) ? MIN(_cells - 1, (NSInteger)llround(peak * (double)_cells) - 1) : -1;
    if (litCells == _shownLit && peakCell == _shownPeak && available == _shownAvail) return;
    _shownLit = litCells; _shownPeak = peakCell; _shownAvail = available;
    CGFloat w = _root.bounds.size.width;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _root.opacity = available ? 1.0f : 0.45f;
    // Snap the lit width to whole cells so a cell is either on or off (LED look, no half cells).
    NSInteger lit = (NSInteger)llround(level * (double)_cells);
    _clip.frame = CGRectMake(0, 0, lit > 0 ? (lit * kCellPitch - (kCellPitch - kCellW)) : 0, kCellH);
    if (peak > 0.02 && available) {
        NSInteger pc = MIN(_cells - 1, (NSInteger)llround(peak * (double)_cells) - 1);
        _peak.hidden = NO;
        _peak.frame = CGRectMake(MAX(0, pc) * kCellPitch + (kCellW - 1.0) / 2.0, -0.5, 1.0, kCellH + 1.0);
    } else {
        _peak.hidden = YES;
    }
    (void)w;
    [CATransaction commit];
}

@end

@implementation FCLevelMeterIndicator {
    __weak NSPanel     *_clock;
    NSPanel            *_rail;
    NSView             *_bg;
    FCMeterBar         *_in;
    FCMeterBar         *_out;
    FCOutputLevelTap   *_tap;
    FCMeterState        _inState;
    FCMeterState        _outState;
    dispatch_source_t   _timer;
    CFTimeInterval      _lastFrame;
    BOOL                _showing;
    int                 _quietFrames;
    CGFloat             _lastW, _lastSplit;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel {
    if ((self = [super init])) {
        _clock = clockPanel;
        _tap = [FCOutputLevelTap new];
        FCMeterReset(&_inState);
        FCMeterReset(&_outState);
        _lastW = _lastSplit = -1;
        [self buildRail];
        [[FCOverlayStack shared] registerRail:self order:FCStackOrderLevelMeter];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncPosition)
                                                     name:FCOverlayWidthConsensusDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopTimer];
    [_tap stop];
}

- (BOOL)enabled { return [[NSUserDefaults standardUserDefaults] boolForKey:@"LevelMeterEnabled"]; }
- (BOOL)outputEnabled {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"LevelMeterOutputEnabled"];
    return v ? [v boolValue] : YES;
}

- (void)buildRail {
    NSRect r = NSMakeRect(0, 0, 200, kMeterRailHeight);
    _rail = FCCreateOverlayPanel(_clock, r.size, YES);
    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 4.5;
    bg.layer.masksToBounds = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.16 green:0.16 blue:0.18 alpha:0.95] CGColor];
    bg.layer.borderWidth = 1.0;
    bg.layer.borderColor = [[NSColor colorWithWhite:1.0 alpha:0.22] CGColor];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _rail.contentView = bg;
    _bg = bg;

    CGColorRef amber = [[NSColor colorWithSRGBRed:1.00 green:0.78 blue:0.16 alpha:1.0] CGColor];
    CGColorRef red   = [[NSColor colorWithSRGBRed:0.96 green:0.26 blue:0.21 alpha:1.0] CGColor];
    CGColorRef green = [[NSColor colorWithSRGBRed:0.34 green:0.95 blue:0.46 alpha:1.0] CGColor];
    CGColorRef blue  = [[NSColor colorWithSRGBRed:0.38 green:0.78 blue:1.00 alpha:1.0] CGColor];
    _in  = [[FCMeterBar alloc] initWithColors:@[ (__bridge id)green, (__bridge id)green, (__bridge id)amber,
                                                  (__bridge id)amber, (__bridge id)red, (__bridge id)red ]];
    _out = [[FCMeterBar alloc] initWithColors:@[ (__bridge id)blue, (__bridge id)blue, (__bridge id)amber,
                                                  (__bridge id)amber, (__bridge id)red, (__bridge id)red ]];
    [bg.layer addSublayer:_in.root];
    [bg.layer addSublayer:_out.root];
    [_rail orderOut:nil];
}

#pragma mark FCStackRail

- (BOOL)isShowing { return _showing; }
- (CGFloat)railHeight { return kMeterRailHeight; }
- (CGFloat)railGap { return kMeterRailGap; }

#pragma mark Refresh

- (void)refresh {
    BOOL want = [self enabled] && !FCClockUserHidden()
             && (!self.audioIndicator || [self.audioIndicator isShowing]);
    _tap.enabled = want && [self outputEnabled];
    if (want) [_tap tick];
    if (want != _showing) {
        _showing = want;
        if (!want) {
            [self stopTimer];
            FCHideOverlay(_rail);
        }
        [[FCOverlayStack shared] noteChanged];
    }
    if (!want) return;
    [self syncPosition];
    if (_timer) return;   // animating; the frame loop stops itself after ~1 s at the floor
    // Idle: peek once a second; wake the 30 Hz loop only when there is signal to show.
    float ip = 0, ir = 0, op = 0, orms = 0;
    if ([self.micIndicator inputMeterAvailable]) [self.micIndicator readInputPeak:&ip rms:&ir];
    if (_tap.running) [_tap readPeak:&op rms:&orms];
    if (FCLinearToDb(ip) > FCMeterFloorDb || FCLinearToDb(op) > FCMeterFloorDb) {
        _quietFrames = 0;
        [self startTimer];
    } else {
        [self drawFrameWithDt:1.0];   // settle to the resting state (and the right availability dimming)
    }
}

- (void)syncPosition {
    if (!_clock || !_showing || FCClockUserHidden()) return;
    NSRect c = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf = s ? s.visibleFrame : c;
    CGFloat agreed = [[FCOverlayWidthConsensus shared] widthForClockWidth:NSWidth(c)];
    NSRect f = FCComputeOverlayFrameWithWidth(c, vf, kMeterRailHeight,
                                              [[FCOverlayStack shared] offsetBelowOrder:FCStackOrderLevelMeter],
                                              kMeterRailGap, agreed);
    if (!NSEqualRects(f, _rail.frame)) [_rail setFrame:f display:YES];
    CGFloat split = [self.audioIndicator inputZoneWidth];
    if (split <= 1.0 || split >= f.size.width) split = floor((f.size.width - 1.0) / 2.0);
    if (fabs(f.size.width - _lastW) >= 0.5 || fabs(split - _lastSplit) >= 0.5) {
        _lastW = f.size.width; _lastSplit = split;
        CGFloat h = kMeterRailHeight;
        [_in  layoutInRect:CGRectMake(kMeterInsetX, 0, split - 2 * kMeterInsetX, h)];
        [_out layoutInRect:CGRectMake(split + 1 + kMeterInsetX, 0, f.size.width - split - 1 - 2 * kMeterInsetX, h)];
    }
    if (!_rail.visible) [_rail orderFront:nil];
    [_rail orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _rail);
}

#pragma mark Animation

- (void)startTimer {
    if (_timer) return;
    _lastFrame = CACurrentMediaTime();
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, (uint64_t)(NSEC_PER_SEC / kFrameHz), NSEC_PER_MSEC * 5);
    __weak typeof(self) weak = self;
    dispatch_source_set_event_handler(_timer, ^{
        typeof(self) me = weak; if (!me) return;
        CFTimeInterval now = CACurrentMediaTime();
        [me drawFrameWithDt:now - me->_lastFrame];
        me->_lastFrame = now;
    });
    dispatch_resume(_timer);
}

- (void)stopTimer {
    if (!_timer) return;
    dispatch_source_cancel(_timer);
    _timer = nil;
}

- (void)drawFrameWithDt:(double)dt {
    float ip = 0, ir = 0, op = 0, orms = 0;
    BOOL inAvail = [self.micIndicator inputMeterAvailable];
    if (inAvail) [self.micIndicator readInputPeak:&ip rms:&ir];
    BOOL outAvail = [self outputEnabled];
    if (_tap.running) [_tap readPeak:&op rms:&orms];
    FCMeterStep(&_inState,  FCLinearToDb(ip), dt);
    FCMeterStep(&_outState, FCLinearToDb(op), dt);
    [_in  showFraction:FCDbToFraction(_inState.levelDb)  peak:FCDbToFraction(_inState.peakDb)  available:inAvail];
    [_out showFraction:FCDbToFraction(_outState.levelDb) peak:FCDbToFraction(_outState.peakDb) available:outAvail];
    BOOL quiet = _inState.peakDb <= FCMeterFloorDb && _outState.peakDb <= FCMeterFloorDb;
    if (_timer && quiet && ++_quietFrames > (int)kFrameHz) [self stopTimer];
    else if (!quiet) _quietFrames = 0;
}

@end
