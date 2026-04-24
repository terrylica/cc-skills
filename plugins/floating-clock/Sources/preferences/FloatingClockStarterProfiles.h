// Starter profile bundles + the list of NSUserDefaults keys that
// participate in save/load cycles. Window-position keys are intentionally
// excluded (they're per-machine ergonomics, not part of the profile).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 5 bundled starters: Default, Day Trader, Night Owl, Minimalist, Watch Party.
NSDictionary *buildStarterProfiles(void);

// Keys snapshotted into and restored from every profile. Keep in sync with
// registerDefaults: in clock.m — each key here should have a default value
// registered so unset slots don't bleed across profile switches.
NSArray<NSString *> *profileManagedKeys(void);

NS_ASSUME_NONNULL_END
