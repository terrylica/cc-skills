#import "LocationProvider.h"
#import <CoreLocation/CoreLocation.h>

@interface FCLocationProvider () <CLLocationManagerDelegate>
@property (strong) CLLocationManager *mgr;
@end

@implementation FCLocationProvider

+ (instancetype)shared {
    static FCLocationProvider *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[FCLocationProvider alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _mgr = [[CLLocationManager alloc] init];
    _mgr.delegate = self;
    // City-level accuracy is plenty for sunrise/sunset glyph (a 10km
    // shift moves dawn by ~30 seconds). Avoid the heavier "best"
    // accuracy which spins up GPS hardware.
    _mgr.desiredAccuracy = kCLLocationAccuracyKilometer;
    return self;
}

- (void)kickoff {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Skip the prompt + fetch if cache is fresh (< 24h). City-scale
    // location doesn't change often enough to justify daily re-fetch
    // for this use case.
    NSDate *fetchedAt = [d objectForKey:@"LocationFetchedAt"];
    if ([fetchedAt isKindOfClass:[NSDate class]] &&
        -[fetchedAt timeIntervalSinceNow] < 86400.0 &&
        [d doubleForKey:@"Latitude"] != 0.0) {
        return;
    }

    // macOS 11+: instance accessor (the class method was deprecated
    // in macOS 11 because authorization is per-app instance).
    CLAuthorizationStatus st = _mgr.authorizationStatus;
    [d setInteger:st forKey:@"LocationAuthStatus"];

    if (st == kCLAuthorizationStatusNotDetermined) {
        // Triggers system permission dialog. The didChangeAuthorization
        // callback fires once the user answers; we then request location.
        [_mgr requestWhenInUseAuthorization];
        return;
    }
    if (st == kCLAuthorizationStatusAuthorizedAlways
     || st == kCLAuthorizationStatusAuthorized) {
        [_mgr requestLocation];
    }
    // Denied / restricted: no fetch. SkyGlyph dispatcher falls back to
    // hard-coded hour buckets (iter-114 legacy path).
}

- (BOOL)hasLocation {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:@"LocationFetchedAt"] != nil
        && ([d doubleForKey:@"Latitude"] != 0.0 || [d doubleForKey:@"Longitude"] != 0.0);
}

- (double)latitude  { return [[NSUserDefaults standardUserDefaults] doubleForKey:@"Latitude"];  }
- (double)longitude { return [[NSUserDefaults standardUserDefaults] doubleForKey:@"Longitude"]; }

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)mgr
    didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:status forKey:@"LocationAuthStatus"];
    if (status == kCLAuthorizationStatusAuthorizedAlways
     || status == kCLAuthorizationStatusAuthorized) {
        [mgr requestLocation];
    }
}

- (void)locationManager:(CLLocationManager *)mgr
    didUpdateLocations:(NSArray<CLLocation *> *)locs {
    CLLocation *loc = locs.lastObject;
    if (!loc) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setDouble:loc.coordinate.latitude  forKey:@"Latitude"];
    [d setDouble:loc.coordinate.longitude forKey:@"Longitude"];
    [d setObject:[NSDate date] forKey:@"LocationFetchedAt"];
}

- (void)locationManager:(CLLocationManager *)mgr didFailWithError:(NSError *)err {
    // Silent — fall back to hour-bucket glyph dispatcher. Don't log
    // (LSUIElement app, no user-facing console).
    (void)err;
}

@end
