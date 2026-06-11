// Capture-path validation: record from the SYSTEM DEFAULT INPUT via
// AVAudioEngine and print per-500ms RMS levels with timestamps, plus the
// HAL default-input identity before/after. If scratching the AirPods stem
// spikes the RMS, capture is genuinely flowing through the AirPods mic.
//
//   clang -framework AVFoundation -framework CoreAudio -framework Foundation \
//         -fobjc-arc -o /tmp/fc-default-input-capture-rms-probe \
//         /tmp/fc-default-input-capture-rms-probe.m
//   /tmp/fc-default-input-capture-rms-probe <seconds>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>

static NSString *defaultInputName(double *rateOut) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID dev = 0; UInt32 sz = sizeof(dev);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev);
    if (!dev) return @"(none)";
    AudioObjectPropertyAddress n = { kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef cf = NULL; sz = sizeof(cf);
    AudioObjectGetPropertyData(dev, &n, 0, NULL, &sz, &cf);
    if (rateOut) {
        AudioObjectPropertyAddress r = { kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        Float64 rate = 0; UInt32 rsz = sizeof(rate);
        AudioObjectGetPropertyData(dev, &r, 0, NULL, &rsz, &rate);
        *rateOut = rate;
    }
    return cf ? (__bridge_transfer NSString *)cf : @"(?)";
}

int main(int argc, char **argv) {
    @autoreleasepool {
        int secs = (argc > 1) ? atoi(argv[1]) : 20;
        double rate = 0;
        printf("capture source (HAL default input): %s @ %.0f Hz\n",
               defaultInputName(&rate).UTF8String, rate);

        AVAudioEngine *engine = [AVAudioEngine new];
        AVAudioInputNode *input = engine.inputNode;   // binds to default input
        AVAudioFormat *fmt = [input inputFormatForBus:0];
        printf("engine input format: %.0f Hz, %u ch\n",
               fmt.sampleRate, fmt.channelCount);

        __block float windowPeakRMS = 0;
        __block long  frames = 0;
        [input installTapOnBus:0 bufferSize:1024 format:fmt
                         block:^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
            float *ch = buf.floatChannelData ? buf.floatChannelData[0] : NULL;
            if (!ch) return;
            double sum = 0;
            for (AVAudioFrameCount i = 0; i < buf.frameLength; i++) sum += ch[i] * ch[i];
            float rms = (buf.frameLength > 0) ? (float)sqrt(sum / buf.frameLength) : 0;
            if (rms > windowPeakRMS) windowPeakRMS = rms;
            frames += buf.frameLength;
        }];

        NSError *err = nil;
        if (![engine startAndReturnError:&err]) {
            printf("ENGINE START FAILED: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss.SSS";
        for (int i = 0; i < secs * 2; i++) {
            [NSThread sleepForTimeInterval:0.5];
            float rms = windowPeakRMS; windowPeakRMS = 0;
            int bars = (int)fminf(60.0f, rms * 400.0f);
            printf("[%s] rms=%.4f %.*s\n",
                   [f stringFromDate:[NSDate date]].UTF8String, rms, bars,
                   "############################################################");
            fflush(stdout);
        }
        [input removeTapOnBus:0];
        [engine stop];
        printf("frames captured: %ld\n", frames);
        printf("capture source at end: %s\n", defaultInputName(NULL).UTF8String);
    }
    return 0;
}
