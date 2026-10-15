#import "OverlayStack.h"
#import "OverlayWidthConsensus.h"

@implementation FCOverlayStack {
    NSPointerArray *_rails;   // weak
    NSMutableArray<NSNumber *> *_orders;
}

+ (instancetype)shared {
    static FCOverlayStack *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FCOverlayStack new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rails  = [NSPointerArray weakObjectsPointerArray];
        _orders = [NSMutableArray array];
    }
    return self;
}

- (void)registerRail:(id<FCStackRail>)rail order:(NSInteger)order {
    for (NSUInteger i = 0; i < _rails.count; i++) {
        if ([_rails pointerAtIndex:i] == (__bridge void *)rail) return;
    }
    [_rails addPointer:(__bridge void *)rail];
    [_orders addObject:@(order)];
}

- (CGFloat)offsetBelowOrder:(NSInteger)order {
    CGFloat sum = 0.0;
    for (NSUInteger i = 0; i < _rails.count; i++) {
        id<FCStackRail> r = (__bridge id<FCStackRail>)[_rails pointerAtIndex:i];
        if (!r || _orders[i].integerValue >= order) continue;
        if ([r isShowing]) sum += [r railHeight] + [r railGap];
    }
    return sum;
}

- (void)noteChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:FCOverlayWidthConsensusDidChangeNotification
                                                        object:self];
}

@end
