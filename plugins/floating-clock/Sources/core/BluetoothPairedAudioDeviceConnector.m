#import "BluetoothPairedAudioDeviceConnector.h"
#import <IOBluetooth/IOBluetooth.h>

@implementation FCBluetoothAudioDevice
@end

#pragma mark - Async connect attempt

// IOBluetooth's -openConnection:(id)target delivers the result via
// -connectionComplete:status: on the target. One attempt object per call;
// it retains itself in a static set for the duration (IOBluetooth does NOT
// retain the target), guards against double-fire (callback vs timeout race),
// and always completes on the main queue.
@interface FCBluetoothConnectAttempt : NSObject
@property (nonatomic, strong) IOBluetoothDevice *device;
@property (nonatomic, copy)   FCBluetoothConnectCompletion completion;
@property (nonatomic, assign) BOOL finished;
- (void)startWithTimeout:(NSTimeInterval)timeoutSeconds;
@end

// Live attempts — keeps targets alive until IOBluetooth calls back.
// Main-queue confined (all entry points run on main), so no locking.
static NSMutableSet<FCBluetoothConnectAttempt *> *FCLiveAttempts(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

@implementation FCBluetoothConnectAttempt

- (void)startWithTimeout:(NSTimeInterval)timeoutSeconds {
    [FCLiveAttempts() addObject:self];

    IOReturn rc = [self.device openConnection:self];
    if (rc != kIOReturnSuccess) {
        // Immediate refusal (Bluetooth off, bad state) — no callback coming.
        [self finishSuccess:NO
                     reason:[NSString stringWithFormat:@"open failed (0x%x)", rc]];
        return;
    }
    // Backstop: some devices never call back when unreachable (powered off,
    // in a bag, owner walked away). Verified FOSS-canon pattern: bound the
    // wait, report honestly.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(timeoutSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf finishSuccess:NO reason:@"no response (off / out of range?)"];
    });
}

// IOBluetooth async callback (informal protocol).
- (void)connectionComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    if (status == kIOReturnSuccess) {
        [self finishSuccess:YES reason:nil];
    } else {
        [self finishSuccess:NO
                     reason:[NSString stringWithFormat:@"connect failed (0x%x)", status]];
    }
}

- (void)finishSuccess:(BOOL)success reason:(NSString *)reason {
    if (self.finished) return;   // callback vs timeout — first one wins
    self.finished = YES;
    FCBluetoothConnectCompletion completion = self.completion;
    self.completion = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(success, reason);
    });
    [FCLiveAttempts() removeObject:self];
}

@end

#pragma mark - Connector

@implementation FCBluetoothPairedAudioDeviceConnector

+ (NSArray<FCBluetoothAudioDevice *> *)pairedAudioDevices {
    NSArray *paired = [IOBluetoothDevice pairedDevices];
    if (paired.count == 0) return @[];

    NSMutableArray<FCBluetoothAudioDevice *> *out =
        [NSMutableArray arrayWithCapacity:paired.count];
    for (IOBluetoothDevice *dev in paired) {
        // Audio/Video major class = headphones, headsets, speakers. Filters
        // out keyboards, mice, game controllers — they have no business in
        // an audio-device menu.
        if (dev.deviceClassMajor != kBluetoothDeviceClassMajorAudio) continue;
        NSString *name = dev.name;
        NSString *addr = dev.addressString;
        if (!name.length || !addr.length) continue;

        FCBluetoothAudioDevice *d = [[FCBluetoothAudioDevice alloc] init];
        d.name               = name;
        d.addressString      = addr;
        d.connectedToThisMac = dev.isConnected;
        [out addObject:d];
    }
    [out sortUsingComparator:^NSComparisonResult(FCBluetoothAudioDevice *l,
                                                 FCBluetoothAudioDevice *r) {
        return [l.name localizedCaseInsensitiveCompare:r.name];
    }];
    return out;
}

+ (void)connectDeviceWithAddress:(NSString *)addressString
                         timeout:(NSTimeInterval)timeoutSeconds
                      completion:(FCBluetoothConnectCompletion)completion {
    IOBluetoothDevice *dev = [IOBluetoothDevice deviceWithAddressString:addressString];
    if (!dev) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"unknown device address");
        });
        return;
    }
    if (dev.isConnected) {
        // Already linked to this Mac — nothing to open. (CoreAudio endpoint
        // may still be settling; callers poll the HAL regardless.)
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
        return;
    }
    FCBluetoothConnectAttempt *attempt = [[FCBluetoothConnectAttempt alloc] init];
    attempt.device     = dev;
    attempt.completion = completion;
    [attempt startWithTimeout:(timeoutSeconds > 0 ? timeoutSeconds : 10.0)];
}

@end
