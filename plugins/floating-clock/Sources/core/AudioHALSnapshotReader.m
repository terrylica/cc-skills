#import "AudioHALSnapshotReader.h"
#import "CoreAudioDeviceHALHelpers.h"

static NSArray<NSDictionary<NSString *, id> *> *FCNamedDevicesForScope(NSArray<NSNumber *> *all, BOOL input) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *n in FCDevicesForScopeAmong(all, input)) {
        NSString *name = FCAudioDeviceName((AudioObjectID)n.unsignedIntValue);
        if (name.length) [out addObject:@{ @"id": n, @"name": name }];
    }
    return out;
}

@implementation FCAudioHALSnapshot

- (instancetype)initWithInDevice:(AudioObjectID)inDevice outDevice:(AudioObjectID)outDevice
                        inVolume:(float)inVolume outVolume:(float)outVolume
                         inMuted:(BOOL)inMuted outMuted:(BOOL)outMuted
                          inName:(NSString *)inName outName:(NSString *)outName
                       inDevices:(NSArray *)inDevices outDevices:(NSArray *)outDevices
                    allDeviceIDs:(NSSet<NSNumber *> *)allDeviceIDs {
    if ((self = [super init])) {
        _inDevice = inDevice;     _outDevice = outDevice;
        _inVolume = inVolume;     _outVolume = outVolume;
        _inMuted = inMuted;       _outMuted = outMuted;
        _inName = [inName copy];  _outName = [outName copy];
        _inDevices = [inDevices copy];
        _outDevices = [outDevices copy];
        _allDeviceIDs = [allDeviceIDs copy];
    }
    return self;
}

+ (instancetype)readFromHAL {
    NSAssert(!NSThread.isMainThread, @"HAL snapshot read on the main thread (cc-skills#37)");
    AudioObjectID inDev = FCDefaultDevice(YES), outDev = FCDefaultDevice(NO);
    NSArray<NSNumber *> *all = FCAllDeviceIDs();   // the one device-list read for this snapshot
    return [[self alloc] initWithInDevice:inDev outDevice:outDev
                                 inVolume:FCReadVolume(inDev, YES) outVolume:FCReadVolume(outDev, NO)
                                  inMuted:FCReadInputMute(inDev) outMuted:FCReadOutputMute(outDev)
                                   inName:FCAudioDeviceName(inDev) outName:FCAudioDeviceName(outDev)
                                inDevices:FCNamedDevicesForScope(all, YES) outDevices:FCNamedDevicesForScope(all, NO)
                             allDeviceIDs:[NSSet setWithArray:all]];
}

- (instancetype)snapshotWithDefaultDevice:(AudioObjectID)device forInput:(BOOL)isInput {
    // The name of the new default, if the snapshot already knows it; volume/mute are unknown
    // until the confirming read, so they keep their previous values for at most one read.
    NSString *name = nil;
    for (NSDictionary *d in [self devicesForInput:isInput]) {
        if ([d[@"id"] unsignedIntValue] == device) { name = d[@"name"]; break; }
    }
    return [[FCAudioHALSnapshot alloc]
        initWithInDevice:(isInput ? device : _inDevice) outDevice:(isInput ? _outDevice : device)
                inVolume:_inVolume outVolume:_outVolume inMuted:_inMuted outMuted:_outMuted
                  inName:(isInput ? (name ?: _inName) : _inName)
                 outName:(isInput ? _outName : (name ?: _outName))
               inDevices:_inDevices outDevices:_outDevices allDeviceIDs:_allDeviceIDs];
}

- (AudioObjectID)defaultDeviceForInput:(BOOL)isInput { return isInput ? _inDevice : _outDevice; }
- (NSArray *)devicesForInput:(BOOL)isInput { return isInput ? _inDevices : _outDevices; }

@end

@implementation FCAudioHALReader {
    dispatch_queue_t       _queue;
    FCAudioHALReadBlock    _read;
    FCAudioHALDeliverBlock _deliver;
    // Main-thread state.
    BOOL                   _inFlight;
    BOOL                   _pending;
    CFAbsoluteTime         _inFlightSince;
    // Bumped by every write. A read that started before the latest write may deliver the pre-write
    // state AFTER an optimistic update, so its snapshot is dropped; the follow-up read is pending.
    uint64_t               _writeGeneration;
}

- (instancetype)initWithLabel:(NSString *)label readBlock:(FCAudioHALReadBlock)read
                 deliverBlock:(FCAudioHALDeliverBlock)deliver {
    if ((self = [super init])) {
        _queue = dispatch_queue_create(label.UTF8String,
                     dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        _read = [read copy];
        _deliver = [deliver copy];
    }
    return self;
}

- (void)requestRead {
    NSAssert(NSThread.isMainThread, @"FCAudioHALReader is main-thread only");
    if (_inFlight) { _pending = YES; return; }
    _inFlight = YES;
    _inFlightSince = CFAbsoluteTimeGetCurrent();
    FCAudioHALReadBlock read = _read;
    uint64_t generation = _writeGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        FCAudioHALSnapshot *snapshot = read();
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self_ = weakSelf;
            if (!self_) return;
            self_->_inFlight = NO;
            if (snapshot && generation == self_->_writeGeneration) self_->_deliver(snapshot);
            if (self_->_pending) {
                self_->_pending = NO;
                [self_ requestRead];
            }
        });
    });
}

- (void)performWrite:(dispatch_block_t)write {
    NSAssert(NSThread.isMainThread, @"FCAudioHALReader is main-thread only");
    // Enqueued before the read below (or before the pending follow-up read, when a read is
    // running), and the queue is serial, so the read that follows observes the write.
    _writeGeneration++;
    dispatch_async(_queue, write);
    if (_inFlight) _pending = YES; else [self requestRead];
}

- (CFTimeInterval)secondsInFlight {
    return _inFlight ? CFAbsoluteTimeGetCurrent() - _inFlightSince : 0;
}

@end
