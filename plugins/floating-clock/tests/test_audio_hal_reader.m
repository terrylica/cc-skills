// Audio HAL reader fixtures. See test_audio_hal_reader.h for scope.
#import "test_audio_hal_reader.h"
#import "../Sources/core/AudioHALSnapshotReader.h"
#include <stdatomic.h>

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

// A snapshot whose input volume carries `marker`, so a test can tell which read produced it.
static FCAudioHALSnapshot *FCFakeSnapshot(float marker) {
    return [[FCAudioHALSnapshot alloc]
        initWithInDevice:10 outDevice:20 inVolume:marker outVolume:0.5f inMuted:NO outMuted:NO
                  inName:@"Mic" outName:@"Speakers"
               inDevices:@[ @{ @"id": @10, @"name": @"Mic" }, @{ @"id": @11, @"name": @"Headset" } ]
              outDevices:@[ @{ @"id": @20, @"name": @"Speakers" }, @{ @"id": @21, @"name": @"AirPods" } ]
            allDeviceIDs:[NSSet setWithArray:@[ @10, @11, @20, @21, @99 ]]];
}

// Run the main run loop (which drains the main queue) until `done` or the deadline.
static BOOL FCSpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    return done();
}

void test_audio_hal_reader_coalesces_reads(void) {
    __block _Atomic int reads = 0;
    __block int deliveries = 0;
    FCAudioHALReader *r = [[FCAudioHALReader alloc] initWithLabel:@"test.coalesce"
        readBlock:^FCAudioHALSnapshot *{ atomic_fetch_add(&reads, 1); usleep(50000); return FCFakeSnapshot(0.1f); }
     deliverBlock:^(FCAudioHALSnapshot *s) { deliveries++; }];
    for (int i = 0; i < 10; i++) [r requestRead];
    FCSpinUntil(^BOOL { return deliveries >= 2 && r.secondsInFlight == 0; }, 2.0);
    FCSpinUntil(^BOOL { return NO; }, 0.15);   // give any extra (wrong) read time to show up
    CHECK(atomic_load(&reads) == 2, "10 requests during one read -> 2 reads, got %d", atomic_load(&reads));
    CHECK(deliveries == 2, "2 deliveries, got %d", deliveries);
}

void test_audio_hal_reader_write_then_read_order(void) {
    __block _Atomic int halValue = 1;   // stands in for a HAL property
    __block float lastSeen = -1;
    FCAudioHALReader *r = [[FCAudioHALReader alloc] initWithLabel:@"test.order"
        readBlock:^FCAudioHALSnapshot *{ return FCFakeSnapshot((float)atomic_load(&halValue)); }
     deliverBlock:^(FCAudioHALSnapshot *s) { lastSeen = s.inVolume; }];
    [r performWrite:^{ usleep(20000); atomic_store(&halValue, 5); }];
    FCSpinUntil(^BOOL { return lastSeen >= 0 && r.secondsInFlight == 0; }, 2.0);
    CHECK(lastSeen == 5.0f, "the read after a write must observe it, got %.1f", lastSeen);
}

void test_audio_hal_reader_drops_read_started_before_write(void) {
    __block _Atomic int halValue = 1;
    NSMutableArray<NSNumber *> *seen = [NSMutableArray array];
    FCAudioHALReader *r = [[FCAudioHALReader alloc] initWithLabel:@"test.generation"
        readBlock:^FCAudioHALSnapshot *{
            float v = (float)atomic_load(&halValue);
            usleep(60000);   // the write is requested while this read is running
            return FCFakeSnapshot(v);
        }
     deliverBlock:^(FCAudioHALSnapshot *s) { [seen addObject:@(s.inVolume)]; }];
    [r requestRead];
    FCSpinUntil(^BOOL { return NO; }, 0.02);   // the first read is now in flight with value 1
    [r performWrite:^{ atomic_store(&halValue, 7); }];
    FCSpinUntil(^BOOL { return seen.count >= 1 && r.secondsInFlight == 0; }, 2.0);
    FCSpinUntil(^BOOL { return NO; }, 0.1);
    CHECK(seen.count == 1 && seen[0].floatValue == 7.0f,
          "only the post-write snapshot may be delivered, got %@", seen);
}

void test_audio_hal_reader_seconds_in_flight(void) {
    __block BOOL delivered = NO;
    FCAudioHALReader *r = [[FCAudioHALReader alloc] initWithLabel:@"test.overdue"
        readBlock:^FCAudioHALSnapshot *{ usleep(120000); return FCFakeSnapshot(0); }
     deliverBlock:^(FCAudioHALSnapshot *s) { delivered = YES; }];
    CHECK(r.secondsInFlight == 0, "idle reader reports 0");
    [r requestRead];
    FCSpinUntil(^BOOL { return NO; }, 0.06);
    CHECK(r.secondsInFlight > 0.03, "a running read reports its age, got %.3f", r.secondsInFlight);
    FCSpinUntil(^BOOL { return delivered; }, 2.0);
    CHECK(r.secondsInFlight == 0, "back to 0 after delivery, got %.3f", r.secondsInFlight);
}

void test_audio_hal_snapshot_optimistic_default(void) {
    FCAudioHALSnapshot *s = FCFakeSnapshot(0.3f);
    FCAudioHALSnapshot *o = [s snapshotWithDefaultDevice:21 forInput:NO];
    CHECK([o defaultDeviceForInput:NO] == 21, "output default updated");
    CHECK([o.outName isEqualToString:@"AirPods"], "name taken from the device list, got %@", o.outName);
    CHECK([o defaultDeviceForInput:YES] == 10 && [o.inName isEqualToString:@"Mic"], "input scope untouched");
    CHECK(o.inVolume == 0.3f && [o.allDeviceIDs containsObject:@99], "everything else carried over");
    FCAudioHALSnapshot *unknown = [s snapshotWithDefaultDevice:99 forInput:YES];
    CHECK([unknown defaultDeviceForInput:YES] == 99 && [unknown.inName isEqualToString:@"Mic"],
          "a default outside the ring keeps the previous name until the confirming read");
}
