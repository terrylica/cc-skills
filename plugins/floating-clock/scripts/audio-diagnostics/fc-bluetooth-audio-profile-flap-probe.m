// Bluetooth audio profile-flap watcher: catches A2DP↔HFP/SCO transitions
// that cause playback hiccups. Polls (150ms) a named device's input+output
// endpoints for:
//   · input  DeviceIsRunningSomewhere  — is ANY process capturing the mic?
//     (arming the BT mic forces call-mode SCO → output quality drop/stutter)
//   · output DeviceIsRunningSomewhere  — playback active
//   · output nominal sample rate       — drops on profile renegotiation
//   · device id changes                — endpoint re-registration (reconnect)
// Prints a timestamped line on every change.
//
//   clang -framework CoreAudio -framework Foundation -fobjc-arc \
//         -o /tmp/fc-bluetooth-audio-profile-flap-probe \
//         /tmp/fc-bluetooth-audio-profile-flap-probe.m
//   /tmp/fc-bluetooth-audio-profile-flap-probe "AirPods" 240
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static NSString *devName(AudioObjectID dev) {
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; UInt32 sz = sizeof(cf);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &cf) != noErr || !cf) return nil;
    return (__bridge_transfer NSString *)cf;
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

static AudioObjectID findByName(NSString *needle, BOOL input) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr) return 0;
    UInt32 n = sz / sizeof(AudioObjectID);
    AudioObjectID ids[n];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, ids) != noErr) return 0;
    for (UInt32 i = 0; i < n; i++) {
        if (channels(ids[i], input) == 0) continue;
        NSString *nm = devName(ids[i]);
        if (nm && [nm rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return ids[i];
        }
    }
    return 0;
}

static int runningSomewhere(AudioObjectID dev) {
    if (!dev) return -1;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyDeviceIsRunningSomewhere,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    if (!AudioObjectHasProperty(dev, &a)) return -1;
    UInt32 v = 0, sz = sizeof(v);
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &v) != noErr) return -1;
    return v ? 1 : 0;
}

static double rate(AudioObjectID dev) {
    if (!dev) return 0;
    AudioObjectPropertyAddress a = { kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    Float64 r = 0; UInt32 sz = sizeof(r);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &r);
    return r;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *needle = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"AirPods";
        int secs = (argc > 2) ? atoi(argv[2]) : 240;

        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss.SSS";
        int li = -2, lo = -2; double lr = -1; AudioObjectID lid = 0, lod = 0;

        printf("watching '%s' for profile flaps (%ds, 150ms poll)…\n",
               needle.UTF8String, secs);
        for (int t = 0; t < secs * 1000 / 150; t++) {
            AudioObjectID inDev  = findByName(needle, YES);
            AudioObjectID outDev = findByName(needle, NO);
            int ri = runningSomewhere(inDev);
            int ro = runningSomewhere(outDev);
            double rr = rate(outDev);
            if (ri != li || ro != lo || rr != lr || inDev != lid || outDev != lod) {
                printf("[%s] mic-armed=%s  playback=%s  outRate=%.0f  (in=%u out=%u)\n",
                       [f stringFromDate:[NSDate date]].UTF8String,
                       ri == 1 ? "YES" : (ri == 0 ? "no" : "?"),
                       ro == 1 ? "YES" : (ro == 0 ? "no" : "?"),
                       rr, inDev, outDev);
                fflush(stdout);
                li = ri; lo = ro; lr = rr; lid = inDev; lod = outDev;
            }
            usleep(150000);
        }
        printf("done.\n");
    }
    return 0;
}
