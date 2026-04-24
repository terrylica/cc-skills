// 4-tier clock font resolution:
//   1. User override via NSUserDefaults "FontName" (PostScript name)
//   2. iTerm2 default profile's "Normal Font" (com.googlecode.iterm2.plist)
//   3. System monospaced (SF Mono on macOS 10.15+)
//   4. Menlo-Regular (pre-Catalina) or systemFontOfSize (last resort)
//
// All plist lookups are defensive (isKindOfClass: every step) — a malformed
// iTerm2 plist can't crash the clock.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSFont *resolveClockFont(CGFloat size);

NS_ASSUME_NONNULL_END
