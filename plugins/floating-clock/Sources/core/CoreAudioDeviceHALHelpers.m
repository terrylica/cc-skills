#import "CoreAudioDeviceHALHelpers.h"

AudioObjectID FCDefaultDevice(BOOL input) {
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID dev = kAudioObjectUnknown;
    UInt32 sz = sizeof(dev);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev) != noErr) {
        return kAudioObjectUnknown;
    }
    return dev;
}

void FCSetDefaultDevice(AudioObjectID dev, BOOL input) {
    if (dev == kAudioObjectUnknown) return;
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL,
                               sizeof(dev), &dev);
}

NSString *FCAudioDeviceName(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return nil;
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; UInt32 sz = sizeof(cf);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &cf) != noErr || !cf) return nil;
    return (__bridge_transfer NSString *)cf;
}

BOOL FCDeviceHasChannels(AudioObjectID dev, BOOL input) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
                                     input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &sz) != noErr || sz == 0) return NO;
    // Stack buffer — AudioBufferList for a handful of streams is tiny.
    UInt8 buf[sz];
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, buf) != noErr) return NO;
    const AudioBufferList *abl = (const AudioBufferList *)buf;
    if (abl->mNumberBuffers == 0) return NO;
    UInt32 ch = 0;
    for (UInt32 i = 0; i < abl->mNumberBuffers; i++) ch += abl->mBuffers[i].mNumberChannels;
    return ch > 0;
}

// Software mute flag on the device's input scope (the analog hardware-button
// mute on the Antlion is invisible here — FCMicMuteIndicator's silence meter
// covers that path; the IN zone ORs both signals).
BOOL FCReadInputMute(AudioObjectID dev) {
    if (dev == kAudioObjectUnknown) return NO;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyMute,
                                     kAudioDevicePropertyScopeInput,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 v = 0, sz = sizeof(v);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) != noErr) return NO;
    return v != 0;
}

// Volume as 0.0–1.0, or -1 when the device exposes no volume control
// (e.g. HDMI/DisplayPort sinks). Tries the virtual main element first,
// then channel 1 (left) — the common pattern for BT and USB devices.
float FCReadVolume(AudioObjectID dev, BOOL input) {
    if (dev == kAudioObjectUnknown) return -1.0f;
    AudioObjectPropertyScope scope = input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput;
    const UInt32 elements[2] = { kAudioObjectPropertyElementMain, 1 };
    for (int i = 0; i < 2; i++) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyVolumeScalar, scope, elements[i] };
        if (!AudioObjectHasProperty(dev, &a)) continue;
        Float32 v = 0; UInt32 sz = sizeof(v);
        if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) == noErr) return v;
    }
    return -1.0f;
}

// Write volume to the main element when available, else to channels 1+2.
// Returns YES if at least one element accepted the write.
BOOL FCWriteVolume(AudioObjectID dev, BOOL input, float v) {
    if (dev == kAudioObjectUnknown) return NO;
    if (v < 0.0f) v = 0.0f;
    if (v > 1.0f) v = 1.0f;
    AudioObjectPropertyScope scope = input ? kAudioDevicePropertyScopeInput
                                           : kAudioDevicePropertyScopeOutput;
    Float32 vol = v;
    // Main element governs all channels — prefer it.
    AudioObjectPropertyAddress main = { kAudioDevicePropertyVolumeScalar, scope,
                                        kAudioObjectPropertyElementMain };
    Boolean settable = false;
    if (AudioObjectHasProperty(dev, &main) &&
        AudioObjectIsPropertySettable(dev, &main, &settable) == noErr && settable) {
        return AudioObjectSetPropertyData(dev, &main, 0, NULL, sizeof(vol), &vol) == noErr;
    }
    BOOL ok = NO;
    for (UInt32 ch = 1; ch <= 2; ch++) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyVolumeScalar, scope, ch };
        settable = false;
        if (AudioObjectHasProperty(dev, &a) &&
            AudioObjectIsPropertySettable(dev, &a, &settable) == noErr && settable &&
            AudioObjectSetPropertyData(dev, &a, 0, NULL, sizeof(vol), &vol) == noErr) {
            ok = YES;
        }
    }
    return ok;
}

// Virtual / aggregate transports are routing constructs (BackgroundMusic,
// Lark loopback, multi-output sets), not devices a human toggles between.
// Verified 2026-06-11: with them in the ring, cycling wedged on
// "Background Music" — its UI-Sounds sibling refuses main-default, so the
// ring never visibly advanced. The bar still DISPLAYS a virtual default
// truthfully; it just won't cycle INTO one.
BOOL FCDeviceIsVirtual(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyTransportType,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return NO;
    UInt32 t = 0, sz = sizeof(t);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &t) != noErr) return NO;
    return t == kAudioDeviceTransportTypeVirtual
        || t == kAudioDeviceTransportTypeAggregate;
}

// All REAL devices with channels in the given scope (virtual/aggregate
// excluded — see FCDeviceIsVirtual), name-sorted for a stable, predictable
// cycling order. Returns AudioObjectID values boxed as NSNumber.
NSArray<NSNumber *> *FCDevicesForScope(BOOL input) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr || sz == 0) {
        return @[];
    }
    UInt32 count = sz / (UInt32)sizeof(AudioObjectID);
    AudioObjectID ids[count];   // stack allocation — device lists are small
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, ids) != noErr) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *named = [NSMutableArray arrayWithCapacity:count];
    for (UInt32 i = 0; i < count; i++) {
        if (!FCDeviceHasChannels(ids[i], input)) continue;
        if (FCDeviceIsVirtual(ids[i])) continue;
        NSString *name = FCAudioDeviceName(ids[i]);
        if (!name.length) continue;
        [named addObject:@{ @"id": @(ids[i]), @"name": name }];
    }
    [named sortUsingComparator:^NSComparisonResult(NSDictionary *l, NSDictionary *r) {
        return [l[@"name"] localizedCaseInsensitiveCompare:r[@"name"]];
    }];
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:named.count];
    for (NSDictionary *d in named) [out addObject:d[@"id"]];
    return out;
}
