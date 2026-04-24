// 4-tier clock font resolution for the LOCAL primary label:
//   1. User override via NSUserDefaults "FontName" (PostScript name)
//   2. iTerm2 default profile's "Normal Font" (com.googlecode.iterm2.plist)
//   3. System monospaced (SF Mono on macOS 10.15+)
//   4. Menlo-Regular (pre-Catalina) or systemFontOfSize (last resort)
//
// Plus v4 iter-88 monospaced-system-font helpers used by ACTIVE / NEXT
// segment content builders. These paths do not consult the iTerm2
// plist — they want deterministic weight control.
//
// All plist lookups are defensive (isKindOfClass: every step) — a malformed
// iTerm2 plist can't crash the clock.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSFont *resolveClockFont(CGFloat size);

// v4 iter-88. Maps the "FontWeight" pref id to the matching NSFontWeight
// constant. Unknown/empty/nil → NSFontWeightMedium (current default).
// Accepted ids: "regular" / "medium" / "semibold" / "bold" / "heavy".
NSFontWeight FCParseFontWeight(NSString * _Nullable weightId);

// v4 iter-88. Single choke point for monospacedSystemFont construction
// so a future global override (e.g. per-segment FontWeight keys) has
// one call site to swap. Returns [NSFont monospacedSystemFontOfSize:size
// weight:weight] on macOS 10.15+, Menlo fallback otherwise.
NSFont *FCResolveMonoFont(CGFloat size, NSFontWeight weight);

// v4 iter-89. Per-segment weight lookup with fallback to the global
// "FontWeight" pref. segmentKey is an NSUserDefaults key such as
// "ActiveWeight" or "NextWeight". Lookup order:
//   1. NSUserDefaults[segmentKey] if non-empty
//   2. NSUserDefaults[@"FontWeight"] if non-empty
//   3. NSFontWeightMedium
NSFontWeight FCResolveSegmentWeight(NSString *segmentKey);

NS_ASSUME_NONNULL_END
