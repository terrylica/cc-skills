// Audio HAL snapshot + background reader (2026-10-21, cc-skills#37).
//
// Every CoreAudio HAL query is a synchronous IPC to coreaudiod, and a query on a device whose IO
// context is locked blocks until the lock is released. When those queries ran on the main thread, a
// stalled IO context froze the whole clock (cc-skills#25: the device menu hung forever). So the
// audio bar no longer queries the HAL from the main thread at all:
//
//   - FCAudioHALSnapshot is an immutable picture of everything the bar and its device menu show.
//   - FCAudioHALReader produces snapshots on one private serial queue and hands each one to the main
//     queue. Reads are coalesced: at most one runs, and requests made meanwhile collapse into one
//     follow-up read. Writes (set default device, change volume) run on the same queue, in order,
//     and are always followed by a read, so the next snapshot reflects them.
//   - If coreaudiod stalls, only the reader's queue waits; the main thread keeps rendering the last
//     snapshot and can show that the read is overdue (-secondsInFlight).
//
// Threading: every FCAudioHALReader method is main-thread only. The read block and write blocks run
// on the reader's queue and must not touch UI state.
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCAudioHALSnapshot : NSObject
@property (nonatomic, readonly) AudioObjectID inDevice;
@property (nonatomic, readonly) AudioObjectID outDevice;
@property (nonatomic, readonly) float inVolume;    // 0..1, or -1 when the device has no volume control
@property (nonatomic, readonly) float outVolume;
@property (nonatomic, readonly) BOOL inMuted;      // software mute flag only (see FCReadInputMute)
@property (nonatomic, readonly) BOOL outMuted;
@property (nonatomic, readonly, copy, nullable) NSString *inName;
@property (nonatomic, readonly, copy, nullable) NSString *outName;
// Real (non-virtual, non-aggregate) devices with channels in each scope, name-sorted, each
// @{ @"id": NSNumber(AudioObjectID), @"name": NSString } — the ring the bar cycles and the menu lists.
@property (nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *inDevices;
@property (nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *outDevices;
// Every device ID the HAL reported, virtual and aggregate included (restore targets may be virtual).
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *allDeviceIDs;

- (instancetype)initWithInDevice:(AudioObjectID)inDevice outDevice:(AudioObjectID)outDevice
                        inVolume:(float)inVolume outVolume:(float)outVolume
                         inMuted:(BOOL)inMuted outMuted:(BOOL)outMuted
                          inName:(nullable NSString *)inName outName:(nullable NSString *)outName
                       inDevices:(NSArray<NSDictionary<NSString *, id> *> *)inDevices
                      outDevices:(NSArray<NSDictionary<NSString *, id> *> *)outDevices
                    allDeviceIDs:(NSSet<NSNumber *> *)allDeviceIDs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Blocking read of the live HAL state. Never call it on the main thread.
+ (instancetype)readFromHAL;

// Copy with one scope's default changed — the optimistic view right after a write, so a caller
// that re-checks the default before the confirming read lands sees what it just asked for.
- (instancetype)snapshotWithDefaultDevice:(AudioObjectID)device forInput:(BOOL)isInput;

- (AudioObjectID)defaultDeviceForInput:(BOOL)isInput;
- (NSArray<NSDictionary<NSString *, id> *> *)devicesForInput:(BOOL)isInput;
@end

typedef FCAudioHALSnapshot *_Nullable (^FCAudioHALReadBlock)(void);
typedef void (^FCAudioHALDeliverBlock)(FCAudioHALSnapshot *snapshot);

@interface FCAudioHALReader : NSObject
// `read` runs on the reader's private queue; `deliver` runs on the main queue with each snapshot.
- (instancetype)initWithLabel:(NSString *)label
                    readBlock:(FCAudioHALReadBlock)read
                 deliverBlock:(FCAudioHALDeliverBlock)deliver NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Ask for a fresh snapshot. Coalesced: while a read is running, any number of requests produce
// exactly one follow-up read once it finishes.
- (void)requestRead;
// Run `write` on the reader's queue after everything already queued, then read.
- (void)performWrite:(dispatch_block_t)write;
// Seconds the current read has been running; 0 when no read is in flight.
@property (nonatomic, readonly) CFTimeInterval secondsInFlight;
@end

NS_ASSUME_NONNULL_END
