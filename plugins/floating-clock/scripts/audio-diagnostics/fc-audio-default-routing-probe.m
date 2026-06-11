// Diagnostic: snapshot + watch macOS default audio input/output routing.
// Proves whether default-in and default-out are independently held by the
// HAL (they are separate properties) and catches auto-route hijacks live.
//
//   clang -framework CoreAudio -framework Foundation -fobjc-arc \
//         -o /tmp/fc-audio-default-routing-probe /tmp/fc-audio-default-routing-probe.m
//   /tmp/fc-audio-default-routing-probe            # one snapshot
//   /tmp/fc-audio-default-routing-probe watch      # 200ms change log
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static AudioObjectID defDev(BOOL input) {
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID dev = 0; UInt32 sz = sizeof(dev);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev);
    return dev;
}

static NSString *devName(AudioObjectID dev) {
    if (!dev) return @"(none)";
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; UInt32 sz = sizeof(cf);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &cf) != noErr || !cf) return @"(?)";
    return (__bridge_transfer NSString *)cf;
}

static double rate(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    Float64 r = 0; UInt32 sz = sizeof(r);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &r);
    return r;
}

static NSString *transport(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 t = 0; UInt32 sz = sizeof(t);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &t) != noErr) return @"?";
    char c[5] = { (char)(t>>24), (char)(t>>16), (char)(t>>8), (char)t, 0 };
    return [NSString stringWithFormat:@"%s", c];
}

static UInt32 channels(AudioObjectID dev, BOOL input) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
        input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &sz) != noErr || !sz) return 0;
    UInt8 buf[sz];
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, buf) != noErr) return 0;
    const AudioBufferList *abl = (const AudioBufferList *)buf;
    UInt32 ch = 0;
    for (UInt32 i = 0; i < abl->mNumberBuffers; i++) ch += abl->mBuffers[i].mNumberChannels;
    return ch;
}

static void snapshot(void) {
    AudioObjectID di = defDev(YES), doo = defDev(NO);
    printf("DEFAULT INPUT : id=%u  name=%s  rate=%.0f  transport=%s\n",
           di, devName(di).UTF8String, rate(di), transport(di).UTF8String);
    printf("DEFAULT OUTPUT: id=%u  name=%s  rate=%.0f  transport=%s\n",
           doo, devName(doo).UTF8String, rate(doo), transport(doo).UTF8String);
    // All devices with channel counts — shows whether AirPods are one
    // AudioObject with both scopes or split objects.
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz);
    UInt32 n = sz / sizeof(AudioObjectID);
    AudioObjectID ids[n];
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, ids);
    printf("ALL DEVICES:\n");
    for (UInt32 i = 0; i < n; i++) {
        printf("  id=%-4u in=%u out=%u rate=%-6.0f tr=%s  %s\n",
               ids[i], channels(ids[i], YES), channels(ids[i], NO),
               rate(ids[i]), transport(ids[i]).UTF8String,
               devName(ids[i]).UTF8String);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "watch") == 0) {
            AudioObjectID li = 0, lo = 0;
            NSDateFormatter *f = [NSDateFormatter new];
            f.dateFormat = @"HH:mm:ss.SSS";
            printf("watching default-device changes (200ms poll)…\n");
            for (;;) {
                AudioObjectID di = defDev(YES), doo = defDev(NO);
                if (di != li || doo != lo) {
                    printf("[%s] IN: %s (%u)  |  OUT: %s (%u)\n",
                           [f stringFromDate:[NSDate date]].UTF8String,
                           devName(di).UTF8String, di, devName(doo).UTF8String, doo);
                    fflush(stdout);
                    li = di; lo = doo;
                }
                usleep(200000);
            }
        }
        snapshot();
    }
    return 0;
}
