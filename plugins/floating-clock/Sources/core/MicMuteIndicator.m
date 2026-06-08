#import "MicMuteIndicator.h"
#import <CoreAudio/CoreAudio.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>

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
} FCMeter;

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
    _banner = [[NSPanel alloc] initWithContentRect:r
                                         styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _banner.level                  = (_clock ? _clock.level : NSFloatingWindowLevel) + 1;
    _banner.opaque                 = NO;
    _banner.backgroundColor        = [NSColor clearColor];
    _banner.hasShadow              = YES;
    _banner.ignoresMouseEvents     = YES;   // detection-only, no controls
    _banner.becomesKeyOnlyIfNeeded = YES;
    _banner.hidesOnDeactivate      = NO;
    _banner.collectionBehavior     = NSWindowCollectionBehaviorCanJoinAllSpaces
                                   | NSWindowCollectionBehaviorStationary
                                   | NSWindowCollectionBehaviorIgnoresCycle;

    NSView *bg = [[NSView alloc] initWithFrame:r];
    bg.wantsLayer            = YES;
    bg.layer.cornerRadius    = 7.0;
    bg.layer.masksToBounds   = YES;
    bg.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.86 green:0.12 blue:0.12 alpha:0.96] CGColor];
    bg.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _banner.contentView      = bg;

    CGFloat labelH = 16.0;
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, (kBannerHeight - labelH) / 2.0, r.size.width, labelH)];
    label.editable        = NO;
    label.selectable      = NO;
    label.bezeled         = NO;
    label.drawsBackground = NO;
    label.alignment       = NSTextAlignmentCenter;
    label.textColor       = [NSColor whiteColor];
    label.font            = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightBold];
    label.stringValue     = @"⊘ MIC MUTED";
    label.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [bg addSubview:label];
    _bannerLabel = label;

    [_banner orderOut:nil];   // hidden until muted
}

#pragma mark - Positioning / visibility

// 1Hz driver (called from the clock tick). Re-reads the live mute state — both
// the CoreAudio mute flag (software mutes) AND the audio-silence flag (the
// analog hardware button) — then repositions. Recovers the device if it was
// absent so a late plug-in / missed hotplug still works.
- (void)refresh {
    if (_device == kAudioObjectUnknown) {
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

    CGFloat w = c.size.width;
    CGFloat x = c.origin.x;
    CGFloat aboveY = NSMaxY(c) + kBannerGap;
    CGFloat y;
    if (aboveY + kBannerHeight <= NSMaxY(vf)) {
        y = aboveY;                                      // preferred: above the clock
    } else {
        y = c.origin.y - kBannerGap - kBannerHeight;     // fallback: below (clock at screen top)
    }
    if (x + w > NSMaxX(vf)) x = NSMaxX(vf) - w;
    if (x < vf.origin.x)    x = vf.origin.x;

    [_banner setFrame:NSMakeRect(x, y, w, kBannerHeight) display:YES];
    [_banner orderWindow:NSWindowAbove relativeTo:_clock.windowNumber];
}

- (void)applyMuted:(BOOL)muted {
    _muted = muted;
    if (muted) {
        [self syncPosition];
    } else {
        [_banner orderOut:nil];
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

// (Re)find the target device, (re)install its mute listener + metering, refresh.
// Called on launch and whenever the device list changes (unplug/replug).
- (void)rebindDevice {
    [self stopMetering];
    [self removeMuteListener];
    _device = [self findDeviceByName:_deviceName];
    if (_device == kAudioObjectUnknown) {
        // Named mic (the Antlion) is absent — fall back to the current default
        // input device so the banner still tracks whatever mic is live (e.g. the
        // built-in mic muted via F10 / system mute). This restores the overlay
        // when the Antlion is unplugged; we rebind again if it comes back.
        _device = [self defaultInputDevice];
    }
    if (_device != kAudioObjectUnknown) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                         kAudioObjectPropertyScopeInput,
                                         kAudioObjectPropertyElementMain };
        if (AudioObjectHasProperty(_device, &a)) {
            __weak typeof(self) ws = self;
            _muteBlock = ^(UInt32 n, const AudioObjectPropertyAddress *addrs) {
                (void)n; (void)addrs;
                [ws readMuteState];
            };
            AudioObjectAddPropertyListenerBlock(_device, &a, dispatch_get_main_queue(), _muteBlock);
            _muteListenerInstalled = YES;
        }
        [self startMetering];
    }
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

- (void)startMetering {
    if (_meteringStarted || !_micAuthorized || _device == kAudioObjectUnknown) return;

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
