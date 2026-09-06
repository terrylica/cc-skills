#import "NetworkTelemetry.h"
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <CoreWLAN/CoreWLAN.h>

#pragma mark - Pure

double FCComputeByteRate(uint64_t now, uint64_t previous, NSTimeInterval seconds) {
    if (seconds <= 0.0) return 0.0;
    // Counter went backwards: interface reset or re-plug. Report no traffic
    // rather than a spike of the entire counter value.
    if (now < previous) return 0.0;
    return (double)(now - previous) / seconds;
}

NSString *FCFormatByteRate(double bytesPerSecond) {
    if (!(bytesPerSecond > 0.0) || !isfinite(bytesPerSecond)) return @"0";
    if (bytesPerSecond < 1000.0) return [NSString stringWithFormat:@"%.0f", bytesPerSecond];

    static const char *suffix[] = { "K", "M", "G", "T" };
    double v = bytesPerSecond / 1000.0;
    int tier = 0;
    while (v >= 1000.0 && tier < 3) { v /= 1000.0; tier++; }
    // One decimal below 10 keeps "1.2M" readable; above that the decimal is
    // noise and only makes the bar's width jitter.
    NSString *num = (v < 10.0) ? [NSString stringWithFormat:@"%.1f", v]
                               : [NSString stringWithFormat:@"%.0f", v];
    return [NSString stringWithFormat:@"%@%s", num, suffix[tier]];
}

const NSUInteger FCByteRateFieldWidth = 4;

NSString *FCPadLeft(NSString *s, NSUInteger width) {
    if (s == nil) s = @"";
    if (s.length >= width) return s;   // never truncate — a real value beats alignment
    return [[@"" stringByPaddingToLength:(width - s.length)
                             withString:@" "
                        startingAtIndex:0] stringByAppendingString:s];
}

NSInteger FCSignalQualityBucket(NSInteger rssiDbm) {
    if (rssiDbm >= -60) return 2;
    if (rssiDbm >= -72) return 1;
    return 0;
}

#pragma mark - Impure

BOOL FCReadInterfaceByteCounters(NSString *bsdDevice, uint64_t *rxBytes, uint64_t *txBytes) {
    if (bsdDevice.length == 0) return NO;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0 || !list) return NO;

    BOOL found = NO;
    const char *want = bsdDevice.UTF8String;
    for (struct ifaddrs *ifa = list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
        if (!ifa->ifa_name || strcmp(ifa->ifa_name, want) != 0) continue;
        const struct if_data *d = (const struct if_data *)ifa->ifa_data;
        if (!d) continue;
        if (rxBytes) *rxBytes = d->ifi_ibytes;
        if (txBytes) *txBytes = d->ifi_obytes;
        found = YES;
        break;
    }
    freeifaddrs(list);
    return found;
}

NSString *FCPrimaryIPv4ForDevice(NSString *bsdDevice) {
    if (bsdDevice.length == 0) return nil;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0 || !list) return nil;

    NSString *result = nil;
    const char *want = bsdDevice.UTF8String;
    for (struct ifaddrs *ifa = list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if (!ifa->ifa_name || strcmp(ifa->ifa_name, want) != 0) continue;
        char buf[INET_ADDRSTRLEN] = {0};
        const struct sockaddr_in *sin = (const struct sockaddr_in *)(void *)ifa->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) {
            result = [NSString stringWithUTF8String:buf];
        }
        break;
    }
    freeifaddrs(list);
    return result;
}

BOOL FCReadWiFiStats(NSString *bsdDevice, NSInteger *rssiDbm, NSInteger *noiseDbm,
                     double *txRateMbps) {
    if (bsdDevice.length == 0) return NO;
    CWInterface *itf = [[CWWiFiClient sharedWiFiClient] interfaceWithName:bsdDevice];
    if (!itf) return NO;

    NSInteger rssi = [itf rssiValue];
    // A powered-down or disassociated radio reports 0, which is not a valid
    // RSSI. Treat it as "no stats" so the bar omits the field instead of
    // claiming a perfect signal.
    if (rssi == 0) return NO;

    if (rssiDbm)    *rssiDbm    = rssi;
    if (noiseDbm)   *noiseDbm   = [itf noiseMeasurement];
    if (txRateMbps) *txRateMbps = [itf transmitRate];
    return YES;
}
