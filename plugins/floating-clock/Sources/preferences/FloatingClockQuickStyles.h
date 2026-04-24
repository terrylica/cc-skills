// v4 iter-104: extracted Quick Style bundle data from MenuBuilder.m
// to a testable module, parallel to FloatingClockStarterProfiles.
//
// Each Quick Style is a curated dictionary of aesthetic-lever
// NSUserDefaults keys → values. Picking a style writes the whole
// dictionary atomically via `applyQuickStyle:`, while leaving
// user-chosen scale/content prefs (FontSize, SelectedMarket,
// DisplayMode) untouched.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns an array of 2-element arrays:  @[displayName, bundleDict].
// Order is the stable menu-display order.
NSArray<NSArray *> *buildQuickStyles(void);

NS_ASSUME_NONNULL_END
