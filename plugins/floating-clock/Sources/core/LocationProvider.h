// v4 iter-250: thin CLLocationManager wrapper. One-time permission
// request + opportunistic location fetch. Caches lat/lon to
// NSUserDefaults so subsequent launches don't need to re-prompt or
// re-query the provider.
//
// Pref keys written:
//   Latitude            (double, degrees, -90..90)
//   Longitude           (double, degrees, -180..180)
//   LocationFetchedAt   (NSDate)
//   LocationAuthStatus  (NSInteger, mirrors CLAuthorizationStatus)
//
// Touchpoints note: this is the FIRST CoreLocation usage in the app.
// Adds NSLocationWhenInUseUsageDescription Info.plist key + system
// permission prompt + LocationServices read on first launch only.
// All access guarded by user grant.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCLocationProvider : NSObject

+ (instancetype)shared;

// Call once at app launch. If permission is undetermined, prompts the
// user. If granted, requests a single location fix. No-op once cached
// coordinates are < 24h old.
- (void)kickoff;

// Returns cached lat/lon (0,0 sentinel if never fetched). Caller
// should check `hasLocation` first.
@property (nonatomic, readonly) BOOL hasLocation;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;

@end

NS_ASSUME_NONNULL_END
