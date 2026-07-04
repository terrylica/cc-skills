#import "MicMuteIndicator.h"
#import "AudioStatusIndicator.h"   // stack offset above the audio I/O bar (2026-06-11)
#import "ClockChildWindowAttachment.h"  // drag-welding (2026-06-12)
#import "OverlayPanelFactory.h"         // shared overlay construction (DRY 2026-06-12)
#import "OverlayStackingPositioner.h"   // shared stacking geometry (DRY 2026-06-12)
#import <CoreAudio/CoreAudio.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <stdlib.h>

// Banner geometry. Height is fixed; width tracks the clock each sync.
static const CGFloat kBannerHeight = 20.0;
static const CGFloat kBannerGap    = 3.0;   // gap between banner and clock edge

// Audio-silence detection. The Antlion's hardware mute button is a pure analog
// cut — it changes NO CoreAudio property; the only fingerprint is that the
// captured signal flatlines to digital silence (~-91 dB). So we meter the
// device's input level via an IOProc and flag "silent" when the RMS sits at the
// digital-zero floor for a sustained window. A live mic — even a quiet room —
// has a self-noise floor well above this, so quiet ≠ muted.
static const float  kSilenceRMS      = 8.0e-5f;  // ≈ -82 dB; muted ≈ 2.8e-5, live floor ≈ 4e-4
static const double kSilenceHoldSecs = 0.4;      // sustain before flagging muted

// RT-safe meter state shared with the IOProc (plain scalar writes only — no
// ObjC, locks, or allocation on the realtime audio thread).
typedef struct {
    volatile int32_t silent;          // 1 when sustained digital silence
    double           silentRunFrames;  // consecutive silent frames
    double           sampleRate;
    volatile double  lastRMS;         // DEBUG: most recent RMS from the IOProc
    volatile int64_t cbCount;         // DEBUG: total IOProc callbacks (liveness)
    volatile int64_t lastFrames;      // DEBUG: frames in the most recent buffer
} FCMeter;

#pragma mark - DEBUG instrumentation (FC_MIC_DEBUG=1) — data-flow tracing

static BOOL FCMicDebugOn(void) {
    static int v = -1;
    if (v < 0) v = (getenv("FC_MIC_DEBUG") != NULL) ? 1 : 0;
    return v;
}

// Human-readable name of a device id (for log correlation).
static NSString *FCDeviceName(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return @"(none)";
    AudioObjectPropertyAddress na = { kAudioObjectPropertyName,
                                      kAudioObjectPropertyScopeGlobal,
                                      kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; UInt32 sz = sizeof(cf);
    if (AudioObjectGetPropertyData(dev, &na, 0, NULL, &sz, &cf) == noErr && cf) {
        return (__bridge_transfer NSString *)cf;
    }
    return @"(unnamed)";
}

// Is this device running for ANY process system-wide (i.e. some app is actively
// recording it)? This is the signal that distinguishes "another app/call owns
// the mic" from "the mic is muted". (kAudioDevicePropertyDeviceIsRunningSomewhere)
static BOOL FCDeviceRunningSomewhere(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return NO;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyDeviceIsRunningSomewhere,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 v = 0, sz = sizeof(v);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) != noErr) return NO;
    return v != 0;
}

// Is this device hogged (exclusive access) by some process? pid -1 == not hogged.
static pid_t FCDeviceHogPID(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return -2;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyHogMode,
                                     kAudioObjectPropertyScopeInput,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return -2;
    pid_t pid = -1; UInt32 sz = sizeof(pid);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &pid) != noErr) return -2;
    return pid;
}

static void FCMicLog(NSString *fmt, ...) {
    if (!FCMicDebugOn()) return;
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    static dispatch_once_t once; static NSFileHandle *fh;
    dispatch_once(&once, ^{
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/FloatingClock-mic.log"];
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
    });
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n",
                      [[NSDate date] timeIntervalSince1970], msg];
    fputs(line.UTF8String, stderr);
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

static OSStatus FCMeterIOProc(AudioObjectID inDevice,
                              const AudioTimeStamp *inNow,
                              const AudioBufferList *inInputData,
                              const AudioTimeStamp *inInputTime,
                              AudioBufferList *outOutputData,
                              const AudioTimeStamp *inOutputTime,
                              void *inClientData) {
    (void)inDevice; (void)inNow; (void)inInputTime; (void)outOutputData; (void)inOutputTime;
    FCMeter *m = (FCMeter *)inClientData;
    if (!m || !inInputData || inInputData->mNumberBuffers == 0) return noErr;

    double sumSq = 0.0;
    UInt32 totalSamples = 0;
    UInt32 frames = 0;
    for (UInt32 b = 0; b < inInputData->mNumberBuffers; b++) {
        const AudioBuffer *buf = &inInputData->mBuffers[b];
        const float *s = (const float *)buf->mData;
        if (!s) continue;
        UInt32 samples = buf->mDataByteSize / (UInt32)sizeof(float);
        for (UInt32 i = 0; i < samples; i++) { double v = s[i]; sumSq += v * v; }
        totalSamples += samples;
        UInt32 ch = buf->mNumberChannels ? buf->mNumberChannels : 1;
        UInt32 f = samples / ch;
        if (f > frames) frames = f;
    }
    if (totalSamples == 0) return noErr;
    double rms = sqrt(sumSq / (double)totalSamples);

    // DEBUG: RT-safe scalar writes only (no ObjC/locks/alloc on the audio thread).
    m->lastRMS    = rms;
    m->lastFrames = frames;
    m->cbCount   += 1;

    if (rms < kSilenceRMS) {
        m->silentRunFrames += frames;
        if (m->silentRunFrames >= m->sampleRate * kSilenceHoldSecs) m->silent = 1;
    } else {
        m->silentRunFrames = 0;
        m->silent = 0;
    }
    return noErr;
}

@implementation FCMicMuteIndicator {
    __weak NSPanel *_clock;
    NSString       *_deviceName;
    NSPanel        *_banner;
    NSTextField    *_bannerLabel;
    AudioObjectID   _device;             // kAudioObjectUnknown when absent
    BOOL            _muted;
    AudioObjectPropertyListenerBlock _muteBlock;        // retained to remove later
    AudioObjectPropertyListenerBlock _devicesBlock;     // hotplug listener
    AudioObjectPropertyListenerBlock _defaultInputBlock; // default-input-change listener
    BOOL            _muteListenerInstalled;
    // Audio-level metering (catches the analog hardware-button mute).
    BOOL              _micAuthorized;
    BOOL              _meteringStarted;
    AudioDeviceIOProcID _ioProc;
    FCMeter           _meter;
}

- (instancetype)initWithClockPanel:(NSPanel *)clockPanel deviceName:(NSString *)deviceName {
    if ((self = [super init])) {
        _clock       = clockPanel;
        _deviceName  = [deviceName copy];
        _device      = kAudioObjectUnknown;
        _muted       = NO;
        [self buildBanner];
        [self requestMicAccess];     // gate audio metering on Microphone permission
        [self installDevicesListener];
        [self rebindDevice];         // find device → mute listener + metering → read state
    }
    return self;
}

- (void)dealloc {
    [self stopMetering];
    [self removeMuteListener];
    if (_devicesBlock) {
        AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &a,
                                               dispatch_get_main_queue(), _devicesBlock);
    }
    if (_defaultInputBlock) {
        AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultInputDevice,
                                         kAudioObjectPropertyScopeGlobal,
                                         kAudioObjectPropertyElementMain };
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &a,
                                               dispatch_get_main_queue(), _defaultInputBlock);
    }
}

#pragma mark - Banner window

- (void)buildBanner {
    NSRect r = NSMakeRect(0, 0, 160, kBannerHeight);
    _banner = FCCreateOverlayPanel(_clock, r.size, YES);   // detection-only

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.86 green:0.12 blue:0.12 alpha:0.96] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _banner.contentView      = bg;

    NSTextField *label = FCCreateBannerLabel(kBannerHeight, r.size.width, @"⊘ MIC MUTED");
    [bg addSubview:label];
    _bannerLabel = label;

    [_banner orderOut:nil];   // hidden until muted
}

#pragma mark - Positioning / visibility

// 1Hz driver (called from the clock tick). Re-reads the live mute state — both
// the CoreAudio mute flag (software mutes) AND the audio-silence flag (the
// analog hardware button) — then repositions. Recovers the device if it was
// absent, and rebinds if the default input drifted away from the bound device
// (backstop for missed/coalesced default-change notifications; one HAL
// property read per second).
- (void)refresh {
    AudioObjectID def = [self defaultInputDevice];
    if (_device == kAudioObjectUnknown ||
        (def != kAudioObjectUnknown && def != _device)) {
        [self rebindDevice];
    } else {
        [self readMuteState];
    }
}

- (void)syncPosition {
    if (!_clock || !_muted) return;   // nothing to place while hidden
    NSRect c    = _clock.frame;
    NSScreen *s = _clock.screen ?: [NSScreen mainScreen];
    NSRect vf   = s ? s.visibleFrame : c;

    // Stack above the audio bar when it's showing; geometry SSoT:
    // OverlayStackingPositioner. The stacking POLICY stays here.
    CGFloat audioOffset = (self.audioIndicator && [self.audioIndicator isShowing])
                          ? (kBannerHeight + kBannerGap) : 0.0;
    [_banner setFrame:FCComputeOverlayFrame(c, vf, kBannerHeight, audioOffset, kBannerGap)
              display:YES];
    [_banner orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
    FCAttachOverlayToClock(_clock, _banner);   // drag-welding (2026-06-12)
}

- (void)applyMuted:(BOOL)muted {
    if (muted != _muted) FCMicLog(@"  >> BANNER %@", muted ? @"SHOW (muted)" : @"hide (unmuted)");
    _muted = muted;
    if (muted) {
        [self syncPosition];
    } else {
        FCHideOverlay(_banner);   // detach-then-hide ceremony
    }
}

- (BOOL)isShowing { return _muted; }

#pragma mark - Mute state (flag OR audio-silence)

- (BOOL)readPropertyMute {
    if (_device == kAudioObjectUnknown) return NO;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                     kAudioObjectPropertyScopeInput,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(_device, &a)) return NO;
    UInt32 v = 0, sz = sizeof(v);
    if (AudioObjectGetPropertyData(_device, &a, 0, NULL, &sz, &v) != noErr) return NO;
    return v != 0;
}

- (void)readMuteState {
    BOOL propMuted  = [self readPropertyMute];
    // Only trust the audio-silence signal when metering is actually live and
    // permitted — otherwise the IOProc would deliver zeros and false-positive.
    BOOL audioMuted = (_micAuthorized && _meteringStarted && _meter.silent != 0);
    if (FCMicDebugOn()) {
        AudioObjectID def = [self defaultInputDevice];
        FCMicLog(@"read dev=%u(%@) prop=%d silent=%d rms=%.6f frames=%lld cb=%lld meter=%d auth=%d runSomewhere=%d hogPID=%d default=%u(%@) => MUTED=%d",
                 _device, FCDeviceName(_device), propMuted, _meter.silent,
                 _meter.lastRMS, (long long)_meter.lastFrames, (long long)_meter.cbCount,
                 _meteringStarted, _micAuthorized, FCDeviceRunningSomewhere(_device),
                 FCDeviceHogPID(_device), def, FCDeviceName(def),
                 (propMuted || audioMuted));
    }
    [self applyMuted:(propMuted || audioMuted)];
}

#pragma mark - Device binding

- (AudioObjectID)findDeviceByName:(NSString *)name {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr) {
        return kAudioObjectUnknown;
    }
    UInt32 count = sz / (UInt32)sizeof(AudioObjectID);
    if (count == 0) return kAudioObjectUnknown;
    AudioObjectID ids[count];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, ids) != noErr) {
        return kAudioObjectUnknown;
    }
    for (UInt32 i = 0; i < count; i++) {
        AudioObjectPropertyAddress na = { kAudioObjectPropertyName,
                                          kAudioObjectPropertyScopeGlobal,
                                          kAudioObjectPropertyElementMain };
        CFStringRef cfname = NULL;
        UInt32 nsz = sizeof(cfname);
        if (AudioObjectGetPropertyData(ids[i], &na, 0, NULL, &nsz, &cfname) == noErr && cfname) {
            NSString *dn = (__bridge_transfer NSString *)cfname;
            if ([dn isEqualToString:name]) return ids[i];
        }
    }
    return kAudioObjectUnknown;
}

// Current system default input device (kAudioObjectUnknown if none). Used as the
// fallback target when the named mic (the Antlion) isn't connected.
- (AudioObjectID)defaultInputDevice {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultInputDevice,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    AudioObjectID dev = kAudioObjectUnknown;
    UInt32 sz = sizeof(dev);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev) != noErr) {
        return kAudioObjectUnknown;
    }
    return dev;
}

// (Re)bind the watch target, (re)install its mute listener + metering, refresh.
// Called on launch and whenever the device list or default input changes.
//
// 2026-06-11 SEMANTICS FLIP (user bug report): this used to bind
// named-device-first, so while the Antlion was plugged in the banner metered
// the ANTLION even when the default input was AirPods — pressing the
// Antlion's hardware button then flagged the AirPods IN zone red, a false
// positive. The banner now tracks the CURRENT DEFAULT INPUT — the mic that
// would actually capture. A muted mic that is NOT the active input is
// irrelevant by definition. The named device (the Antlion) remains only as
// a last-resort fallback when the HAL reports no default input at all.
- (void)rebindDevice {
    [self stopMetering];
    [self removeMuteListener];
    AudioObjectID def = [self defaultInputDevice];
    _device = def;
    BOOL fellBack = NO;
    if (_device == kAudioObjectUnknown) {
        fellBack = YES;
        _device = [self findDeviceByName:_deviceName];
    }
    if (_device != kAudioObjectUnknown) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                         kAudioObjectPropertyScopeInput,
                                         kAudioObjectPropertyElementMain };
        if (AudioObjectHasProperty(_device, &a)) {
            __weak typeof(self) ws = self;
            _muteBlock = ^(UInt32 n, const AudioObjectPropertyAddress *addrs) {
                (void)n; (void)addrs;
                FCMicLog(@"EVT mute-property changed");
                [ws readMuteState];
            };
            AudioObjectAddPropertyListenerBlock(_device, &a, dispatch_get_main_queue(), _muteBlock);
            _muteListenerInstalled = YES;
        }
        [self startMetering];
    }
    FCMicLog(@"REBIND default=%u fellBackToNamed=%d dev=%u(%@) muteListener=%d metering=%d runSomewhere=%d hogPID=%d",
             def, fellBack, _device, FCDeviceName(_device),
             _muteListenerInstalled, _meteringStarted,
             FCDeviceRunningSomewhere(_device), FCDeviceHogPID(_device));
    [self readMuteState];
}

- (void)removeMuteListener {
    if (_muteListenerInstalled && _device != kAudioObjectUnknown && _muteBlock) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                         kAudioObjectPropertyScopeInput,
                                         kAudioObjectPropertyElementMain };
        AudioObjectRemovePropertyListenerBlock(_device, &a, dispatch_get_main_queue(), _muteBlock);
    }
    _muteListenerInstalled = NO;
    _muteBlock = nil;
}

- (void)installDevicesListener {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    __weak typeof(self) ws = self;
    _devicesBlock = ^(UInt32 n, const AudioObjectPropertyAddress *addrs) {
        (void)n; (void)addrs;
        FCMicLog(@"EVT device-list changed");
        [ws rebindDevice];
    };
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &a, dispatch_get_main_queue(), _devicesBlock);

    // Also rebind when the system default INPUT changes (e.g. the Antlion is
    // unplugged and macOS falls back to the built-in mic, or the user switches
    // the default in Sound settings). Without this the fallback target could go
    // stale while both devices are present.
    AudioObjectPropertyAddress da = { kAudioHardwarePropertyDefaultInputDevice,
                                      kAudioObjectPropertyScopeGlobal,
                                      kAudioObjectPropertyElementMain };
    _defaultInputBlock = ^(UInt32 n, const AudioObjectPropertyAddress *addrs) {
        (void)n; (void)addrs;
        FCMicLog(@"EVT default-input changed");
        [ws rebindDevice];
    };
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &da, dispatch_get_main_queue(), _defaultInputBlock);
}

#pragma mark - Audio metering (analog-button detection)

- (void)requestMicAccess {
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (st == AVAuthorizationStatusAuthorized) {
        _micAuthorized = YES;
        [self startMetering];
    } else if (st == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) ws = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                 completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                FCMicMuteIndicator *me = ws;
                if (!me) return;
                me->_micAuthorized = granted;
                if (granted) { [me startMetering]; [me readMuteState]; }
            });
        }];
    }
    // denied / restricted → leave metering off; software-mute detection still works.
}

// Bluetooth transports must NOT be metered: a persistent capture IOProc on a
// BT mic holds the headset in HFP/SCO call mode permanently — degraded output
// quality + battery drain (2026-06-11). Their mute is a software flag anyway;
// the analog-silence meter exists for the Antlion's analog button, which only
// matters when the Antlion IS the bound (default) device.
static BOOL FCDeviceIsBluetoothTransport(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyTransportType,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 t = 0, sz = sizeof(t);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &t) != noErr) return NO;
    return t == kAudioDeviceTransportTypeBluetooth
        || t == kAudioDeviceTransportTypeBluetoothLE;
}

- (void)startMetering {
    if (_meteringStarted || !_micAuthorized || _device == kAudioObjectUnknown) return;
    if (FCDeviceIsBluetoothTransport(_device)) {
        FCMicLog(@"metering skipped: bluetooth transport (HFP/SCO lock avoidance)");
        return;
    }

    Float64 sr = 48000.0;
    UInt32 sz = sizeof(sr);
    AudioObjectPropertyAddress sra = { kAudioDevicePropertyNominalSampleRate,
                                       kAudioObjectPropertyScopeInput,
                                       kAudioObjectPropertyElementMain };
    AudioObjectGetPropertyData(_device, &sra, 0, NULL, &sz, &sr);
    _meter.sampleRate      = (sr > 0) ? sr : 48000.0;
    _meter.silent          = 0;
    _meter.silentRunFrames = 0;

    if (AudioDeviceCreateIOProcID(_device, FCMeterIOProc, &_meter, &_ioProc) == noErr && _ioProc) {
        if (AudioDeviceStart(_device, _ioProc) == noErr) {
            _meteringStarted = YES;
        } else {
            AudioDeviceDestroyIOProcID(_device, _ioProc);
            _ioProc = NULL;
        }
    }
}

- (void)stopMetering {
    if (_ioProc && _device != kAudioObjectUnknown) {
        AudioDeviceStop(_device, _ioProc);
        AudioDeviceDestroyIOProcID(_device, _ioProc);
    }
    _ioProc          = NULL;
    _meteringStarted = NO;
    _meter.silent    = 0;
    _meter.silentRunFrames = 0;
}

@end
