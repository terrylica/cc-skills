#import "OverlayWidthConsensus.h"

NSString *const FCOverlayWidthConsensusDidChangeNotification =
    @"FCOverlayWidthConsensusDidChangeNotification";

// Sub-pixel churn must not spam the notification (and therefore a relayout of
// every overlay) on every tick. Text measurement wobbles well below this.
static const CGFloat kWidthEpsilon = 0.5;

@implementation FCOverlayWidthConsensus {
    NSMutableDictionary<NSString *, NSNumber *> *_needs;
    CGFloat _lastMax;
}

+ (instancetype)shared {
    static FCOverlayWidthConsensus *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[FCOverlayWidthConsensus alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _needs = [NSMutableDictionary dictionary];
        _lastMax = 0.0;
    }
    return self;
}

- (CGFloat)maxNeed {
    CGFloat m = 0.0;
    for (NSNumber *n in _needs.allValues) {
        CGFloat v = (CGFloat)n.doubleValue;
        if (v > m) m = v;
    }
    return m;
}

// Single mutation funnel, so the change notification cannot be forgotten on one
// path but not the other.
- (void)applyChange:(void (^)(void))mutation {
    mutation();
    CGFloat now = [self maxNeed];
    if (fabs(now - _lastMax) < kWidthEpsilon) return;
    _lastMax = now;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:FCOverlayWidthConsensusDidChangeNotification object:self];
}

- (void)setNeed:(CGFloat)width forOverlay:(NSString *)key {
    if (key.length == 0) return;
    [self applyChange:^{
        if (width > 0.0) {
            self->_needs[key] = @(width);
        } else {
            [self->_needs removeObjectForKey:key];   // <= 0 means "no claim"
        }
    }];
}

- (void)clearOverlay:(NSString *)key {
    if (key.length == 0) return;
    [self applyChange:^{ [self->_needs removeObjectForKey:key]; }];
}

- (CGFloat)widthForClockWidth:(CGFloat)clockWidth {
    CGFloat m = [self maxNeed];
    return m > clockWidth ? m : clockWidth;
}

- (void)reset {
    [self applyChange:^{ [self->_needs removeAllObjects]; }];
}

@end
