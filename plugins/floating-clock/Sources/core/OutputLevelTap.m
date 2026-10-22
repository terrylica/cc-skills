#import "OutputLevelTap.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <math.h>
#include <unistd.h>

static const double kIdleStopSecs = 3.0;

// Shared with the IOProc: running max of |x| and sum of squares since the last UI read.
typedef struct {
    _Atomic uint32_t peakBits;   // float bits; monotonic max until read
    _Atomic uint64_t sumSqMicro; // sum of squares * 1e6 (fixed point)
    _Atomic uint64_t samples;
} FCTapMeter;

// Lock-free "store max": retry the compare-and-swap until our value is in or a larger one is.
static void FCAtomicMaxFloat(_Atomic uint32_t *slot, float v) {
    uint32_t cur = atomic_load_explicit(slot, memory_order_relaxed);
    bool done = false;
    while (!done) {
        float f; memcpy(&f, &cur, sizeof f);
        if (v <= f) { done = true; continue; }
        uint32_t nv; memcpy(&nv, &v, sizeof nv);
        done = atomic_compare_exchange_weak_explicit(slot, &cur, nv, memory_order_relaxed, memory_order_relaxed);
    }
}

static AudioObjectID FCDefaultOutputDevice(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultOutputDevice,
                                     kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID dev = kAudioObjectUnknown; UInt32 sz = sizeof dev;
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev);
    return dev;
}

static NSString *FCDeviceUID(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyDeviceUID,
                                     kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef uid = NULL; UInt32 sz = sizeof uid;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &uid) != noErr || !uid) return nil;
    return CFBridgingRelease(uid);
}

static Float64 FCNominalRate(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyNominalSampleRate,
                                     kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    Float64 r = 0; UInt32 sz = sizeof r;
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &r);
    return r;
}

// YES when any process other than this one is currently producing audio output.
static BOOL FCOtherProcessIsPlaying(void) {
    if (@available(macOS 14.2, *)) {
        AudioObjectPropertyAddress la = { kAudioHardwarePropertyProcessObjectList,
                                          kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        UInt32 sz = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &la, 0, NULL, &sz) != noErr || sz == 0) return NO;
        UInt32 n = sz / sizeof(AudioObjectID);
        AudioObjectID *procs = calloc(n, sizeof(AudioObjectID));
        if (!procs) return NO;
        BOOL playing = NO;
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &la, 0, NULL, &sz, procs) == noErr) {
            pid_t me = getpid();
            for (UInt32 i = 0; i < n && !playing; i++) {
                AudioObjectPropertyAddress ra = { kAudioProcessPropertyIsRunningOutput,
                                                  kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
                UInt32 running = 0, rs = sizeof running;
                if (AudioObjectGetPropertyData(procs[i], &ra, 0, NULL, &rs, &running) != noErr || !running) continue;
                AudioObjectPropertyAddress pa = { kAudioProcessPropertyPID,
                                                  kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
                pid_t pid = 0; UInt32 ps = sizeof pid;
                AudioObjectGetPropertyData(procs[i], &pa, 0, NULL, &ps, &pid);
                if (pid != me) playing = YES;
            }
        }
        free(procs);
        return playing;
    }
    return NO;
}

@implementation FCOutputLevelTap {
    FCTapMeter          _meter;
    AudioObjectID       _tapID;
    AudioObjectID       _aggID;
    AudioDeviceIOProcID _procID;
    AudioObjectID       _builtForDevice;
    Float64             _builtForRate;
    NSDate             *_lastPlaying;
    // Two queues, never one. AudioDeviceCreateIOProcIDWithBlock dispatches the IOProc onto
    // _ioQueue *synchronously* from the HAL IO thread, which holds the IOContext mutex while it
    // waits; AudioDeviceStop needs that same mutex. Stopping from _ioQueue therefore deadlocks the
    // device for the life of the process (sampled 2026-10-21: every later HAL query on the
    // aggregate, including the device menu on the main thread, hung forever). Start, stop and
    // teardown run on _ctlQueue instead. _ioQueue stays non-NULL rather than NULL ("directly
    // invoked") because a NULL queue is reported not to register the block on macOS 26.
    dispatch_queue_t    _ioQueue;
    dispatch_queue_t    _ctlQueue;
    // Thread model (2026-10-21, cc-skills#37): every HAL call and every ivar above is touched only on
    // _ctlQueue, so the main thread never waits on coreaudiod. The main thread sees three atomics:
    // the enabled switch, the running flag, and whether a tick is already queued (ticks coalesce, so
    // a stalled HAL cannot pile up one queued tick per second).
    _Atomic bool        _enabledFlag;
    _Atomic bool        _runningFlag;
    _Atomic bool        _tickQueued;
}

- (instancetype)init {
    if ((self = [super init])) {
        _tapID = _aggID = kAudioObjectUnknown;
        _ioQueue  = dispatch_queue_create("com.cc-skills.floating-clock.output-tap-io",
                        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _ctlQueue = dispatch_queue_create("com.cc-skills.floating-clock.output-tap-control", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_enabledFlag, true);
        atomic_init(&_runningFlag, false);
        atomic_init(&_tickQueued, false);
    }
    return self;
}

// No queued block can be pending here (each one retains self), so tear down inline.
- (void)dealloc { [self teardownOnControlQueue]; }

- (BOOL)running { return atomic_load(&_runningFlag); }
- (BOOL)enabled { return atomic_load(&_enabledFlag); }

- (void)setEnabled:(BOOL)enabled {
    bool was = atomic_exchange(&_enabledFlag, (bool)enabled);
    if (was && !enabled) [self stop];   // only on the transition; the meter sets this every tick
}

- (void)tick {
    if (!atomic_load(&_enabledFlag)) return;
    if (atomic_exchange(&_tickQueued, true)) return;   // previous tick still queued or running
    dispatch_async(_ctlQueue, ^{
        [self tickOnControlQueue];
        atomic_store(&self->_tickQueued, false);
    });
}

- (void)tickOnControlQueue {
    if (!atomic_load(&_enabledFlag)) return;
    if (@available(macOS 14.2, *)) {
        BOOL playing = FCOtherProcessIsPlaying();
        if (playing) _lastPlaying = [NSDate date];
        if (atomic_load(&_runningFlag)) {
            AudioObjectID out = FCDefaultOutputDevice();
            BOOL moved = (out != _builtForDevice) || (fabs(FCNominalRate(out) - _builtForRate) > 0.5);
            BOOL idle  = !playing && (!_lastPlaying || -[_lastPlaying timeIntervalSinceNow] > kIdleStopSecs);
            if (idle) { [self teardownOnControlQueue]; return; }
            if (moved) { [self teardownOnControlQueue]; [self start]; }
        } else if (playing) {
            [self start];
        }
    }
}

- (void)start API_AVAILABLE(macos(14.2)) {
    AudioObjectID out = FCDefaultOutputDevice();
    NSString *outUID = FCDeviceUID(out);
    if (out == kAudioObjectUnknown || !outUID) return;

    CATapDescription *desc = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
    desc.privateTap   = YES;
    desc.muteBehavior = CATapUnmuted;
    desc.name         = @"FloatingClock output level";
    AudioObjectID tap = kAudioObjectUnknown;
    if (AudioHardwareCreateProcessTap(desc, &tap) != noErr || tap == kAudioObjectUnknown) return;

    NSDictionary *agg = @{
        @kAudioAggregateDeviceNameKey:          @"FloatingClock output level",
        @kAudioAggregateDeviceUIDKey:           [NSString stringWithFormat:@"com.cc-skills.floating-clock.level.%@", NSUUID.UUID.UUIDString],
        @kAudioAggregateDeviceMainSubDeviceKey: outUID,
        @kAudioAggregateDeviceIsPrivateKey:     @YES,
        @kAudioAggregateDeviceIsStackedKey:     @NO,
        @kAudioAggregateDeviceTapAutoStartKey:  @YES,
        @kAudioAggregateDeviceSubDeviceListKey: @[ @{ @kAudioSubDeviceUIDKey: outUID } ],
        @kAudioAggregateDeviceTapListKey:       @[ @{ @kAudioSubTapDriftCompensationKey: @YES,
                                                      @kAudioSubTapUIDKey: desc.UUID.UUIDString } ],
    };
    AudioObjectID aggID = kAudioObjectUnknown;
    if (AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)agg, &aggID) != noErr || aggID == kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(tap);
        return;
    }

    FCTapMeter *m = &_meter;
    AudioDeviceIOProcID proc = NULL;
    OSStatus st = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, _ioQueue,
        ^(const AudioTimeStamp *now, const AudioBufferList *in, const AudioTimeStamp *inTime,
          AudioBufferList *outData, const AudioTimeStamp *outTime) {
            float peak = 0.0f; double sumSq = 0.0; uint64_t count = 0;
            for (UInt32 b = 0; in && b < in->mNumberBuffers; b++) {
                const float *x = (const float *)in->mBuffers[b].mData;
                UInt32 n = in->mBuffers[b].mDataByteSize / sizeof(float);
                if (!x) continue;
                for (UInt32 i = 0; i < n; i++) {
                    float a = fabsf(x[i]);
                    if (a > peak) peak = a;
                    sumSq += (double)x[i] * (double)x[i];
                }
                count += n;
            }
            if (count) {
                FCAtomicMaxFloat(&m->peakBits, peak);
                atomic_fetch_add_explicit(&m->sumSqMicro, (uint64_t)(sumSq * 1e6), memory_order_relaxed);
                atomic_fetch_add_explicit(&m->samples, count, memory_order_relaxed);
            }
        });
    if (st != noErr || !proc) {
        AudioHardwareDestroyAggregateDevice(aggID);
        AudioHardwareDestroyProcessTap(tap);
        return;
    }
    _tapID = tap; _aggID = aggID; _procID = proc;
    _builtForDevice = out; _builtForRate = FCNominalRate(out);
    atomic_store(&_runningFlag, true);
    // AudioDeviceStart can block (permission prompt, or a tap leaked by a killed process); this
    // runs on _ctlQueue, never on main and never on _ioQueue.
    AudioDeviceStart(aggID, proc);
}

- (void)stop {
    dispatch_async(_ctlQueue, ^{ [self teardownOnControlQueue]; });
}

// Stop the IOProc and destroy the aggregate and the tap. _ctlQueue only (or dealloc). Never on
// _ioQueue: see the two-queue note on the ivars.
- (void)teardownOnControlQueue {
    if (!atomic_exchange(&_runningFlag, false)) return;
    AudioObjectID tap = _tapID, agg = _aggID; AudioDeviceIOProcID proc = _procID;
    _tapID = _aggID = kAudioObjectUnknown; _procID = NULL;
    if (proc) { AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc); }
    if (agg != kAudioObjectUnknown) AudioHardwareDestroyAggregateDevice(agg);
    if (@available(macOS 14.2, *)) { if (tap != kAudioObjectUnknown) AudioHardwareDestroyProcessTap(tap); }
    atomic_store(&_meter.peakBits, 0);
    atomic_store(&_meter.sumSqMicro, 0);
    atomic_store(&_meter.samples, 0);
}

- (BOOL)readPeak:(float *)peak rms:(float *)rms {
    uint64_t n = atomic_exchange_explicit(&_meter.samples, 0, memory_order_relaxed);
    uint64_t s = atomic_exchange_explicit(&_meter.sumSqMicro, 0, memory_order_relaxed);
    uint32_t pb = atomic_exchange_explicit(&_meter.peakBits, 0, memory_order_relaxed);
    if (!n) { *peak = 0; *rms = 0; return NO; }
    float pf; memcpy(&pf, &pb, sizeof pf);
    *peak = pf;
    *rms = (float)sqrt(((double)s / 1e6) / (double)n);
    return YES;
}

@end
