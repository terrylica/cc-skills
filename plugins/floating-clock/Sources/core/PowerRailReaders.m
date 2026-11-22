#import "PowerRailReaders.h"
#import <IOBluetooth/IOBluetooth.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <dlfcn.h>
#include <objc/message.h>

// Private, exported by IOBluetooth (blueutil.m declares the same pair).
extern int IOBluetoothPreferenceGetControllerPowerState(void) __attribute__((weak_import));
extern void IOBluetoothPreferenceSetControllerPowerState(int state) __attribute__((weak_import));

static const int kFCPowerSourceForAccessories = 4;   // kIOPSSourceForAccessories, IOPowerSourcesPrivate.h

#pragma mark - Battery

static NSDictionary *FCSmartBatteryProperties(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!svc) return nil;
    CFMutableDictionaryRef props = NULL;
    NSDictionary *out = nil;
    if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
        out = CFBridgingRelease(props);
    }
    IOObjectRelease(svc);
    return out;
}

FCBatterySnapshot *FCReadBatterySnapshot(void) {
    NSDictionary *internal = nil;
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    CFArrayRef list = blob ? IOPSCopyPowerSourcesList(blob) : NULL;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, i));
        if ([d[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) { internal = [d copy]; break; }
    }
    if (list) CFRelease(list);
    if (blob) CFRelease(blob);
    NSDictionary *adapter = CFBridgingRelease(IOPSCopyExternalPowerAdapterDetails());
    NSDictionary *sb = FCSmartBatteryProperties();
    return [FCBatterySnapshot snapshotFromPowerSource:internal smartBattery:sb adapter:adapter];
}

#pragma mark - Accessories

NSArray<FCAccessoryPart *> *FCReadAccessoryParts(void) {
    static CFTypeRef (*byType)(int);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ byType = (CFTypeRef (*)(int))dlsym(RTLD_DEFAULT, "IOPSCopyPowerSourcesByType"); });
    if (!byType) return @[];
    CFTypeRef blob = byType(kFCPowerSourceForAccessories);
    if (!blob) return @[];
    NSMutableArray *descs = [NSMutableArray array];
    CFArrayRef list = IOPSCopyPowerSourcesList(blob);
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, i));
        if (d) [descs addObject:[d copy]];
    }
    if (list) CFRelease(list);
    CFRelease(blob);
    return [FCAccessoryPart partsFromDescriptions:descs];
}

NSDictionary<NSString *, NSNumber *> *FCReadHIDBatteryLevels(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &it) != KERN_SUCCESS) return out;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        CFTypeRef pct = IORegistryEntryCreateCFProperty(s, CFSTR("BatteryPercent"), kCFAllocatorDefault, 0);
        CFTypeRef name = IORegistryEntryCreateCFProperty(s, CFSTR("Product"), kCFAllocatorDefault, 0);
        if (pct && name && CFGetTypeID(pct) == CFNumberGetTypeID() && CFGetTypeID(name) == CFStringGetTypeID()) {
            out[(__bridge NSString *)name] = (__bridge NSNumber *)pct;
        }
        if (pct) CFRelease(pct);
        if (name) CFRelease(name);
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return out;
}

#pragma mark - Bluetooth

static NSInteger FCPrivateBatteryPercent(IOBluetoothDevice *dev, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![dev respondsToSelector:sel]) return 0;
    return ((unsigned char (*)(id, SEL))objc_msgSend)(dev, sel);
}

NSArray<NSArray *> *FCReadPairedBluetoothDevices(NSMutableArray<FCAccessoryPart *> *parts) {
    NSMutableArray *out = [NSMutableArray array];
    for (id x in [IOBluetoothDevice pairedDevices] ?: @[]) {
        if (![x isKindOfClass:[IOBluetoothDevice class]]) continue;
        IOBluetoothDevice *dev = x;
        NSString *name = dev.name ?: dev.nameOrAddress;
        NSString *addr = dev.addressString;
        if (!name.length || !addr.length) continue;
        BOOL connected = dev.isConnected;
        [out addObject:@[ name, addr, @(connected) ]];
        if (!connected) continue;
        // 0 means "not reported"; the AirPods case often reads 0 because it sleeps (Hammerspoon's note).
        NSDictionary *sels = @{ @"Left": @"batteryPercentLeft", @"Right": @"batteryPercentRight",
                                @"Case": @"batteryPercentCase", @"Single": @"batteryPercentSingle" };
        for (NSString *part in sels) {
            NSInteger pct = FCPrivateBatteryPercent(dev, sels[part]);
            if (pct <= 0 || pct > 100) continue;
            FCAccessoryPart *p = [FCAccessoryPart new];
            p.name = name; p.group = addr; p.part = part; p.percent = pct;
            [parts addObject:p];
        }
    }
    return out;
}

int FCReadBluetoothPower(void) {
    if (!IOBluetoothPreferenceGetControllerPowerState) return -1;
    return IOBluetoothPreferenceGetControllerPowerState() ? 1 : 0;
}

void FCSetBluetoothPower(BOOL on, void (^completion)(BOOL reached)) {
    if (!IOBluetoothPreferenceSetControllerPowerState || !IOBluetoothPreferenceGetControllerPowerState) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int want = on ? 1 : 0;
        IOBluetoothPreferenceSetControllerPowerState(want);
        BOOL reached = NO;
        for (int i = 0; i <= 100 && !reached; i++) {   // blueutil: poll every 100 ms for up to 10 s
            if (i) usleep(100000);
            reached = (IOBluetoothPreferenceGetControllerPowerState() ? 1 : 0) == want;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(reached); });
    });
}

BOOL FCDisconnectBluetoothDevice(NSString *address) {
    IOBluetoothDevice *dev = [IOBluetoothDevice deviceWithAddressString:address];
    // blueutil 2.14: a disconnect sent to a device that is not connected can hang, so check first.
    if (!dev || !dev.isConnected) return NO;
    return [dev closeConnection] == kIOReturnSuccess;
}

#pragma mark - Change notifications

@implementation FCPowerChangeObserver {
    void (^_onChange)(void);
    CFRunLoopSourceRef _battery;
    CFRunLoopSourceRef _accessories;
}

static void FCPowerSourcesChanged(void *context) {
    FCPowerChangeObserver *me = (__bridge FCPowerChangeObserver *)context;
    if (me->_onChange) me->_onChange();
}

- (instancetype)initWithHandler:(void (^)(void))onChange {
    if ((self = [super init])) {
        _onChange = [onChange copy];
        _battery = IOPSNotificationCreateRunLoopSource(FCPowerSourcesChanged, (__bridge void *)self);
        if (_battery) CFRunLoopAddSource(CFRunLoopGetMain(), _battery, kCFRunLoopDefaultMode);
        CFRunLoopSourceRef (*acc)(IOPowerSourceCallbackType, void *) =
            (CFRunLoopSourceRef (*)(IOPowerSourceCallbackType, void *))dlsym(RTLD_DEFAULT, "IOPSAccNotificationCreateRunLoopSource");
        if (acc) _accessories = acc(FCPowerSourcesChanged, (__bridge void *)self);
        if (_accessories) CFRunLoopAddSource(CFRunLoopGetMain(), _accessories, kCFRunLoopDefaultMode);
    }
    return self;
}

- (void)dealloc {
    if (_battery) { CFRunLoopRemoveSource(CFRunLoopGetMain(), _battery, kCFRunLoopDefaultMode); CFRelease(_battery); }
    if (_accessories) { CFRunLoopRemoveSource(CFRunLoopGetMain(), _accessories, kCFRunLoopDefaultMode); CFRelease(_accessories); }
}

@end
