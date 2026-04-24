// Category declaring the menu-building methods on FloatingClockPanel.
//
// Keeping these in a category (rather than the main @interface) lets clock.m's
// main @implementation not have to provide them — the compiler finds the
// implementations in Sources/menu/FloatingClockPanel+MenuBuilder.m without
// -Wincomplete-implementation warnings.
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (MenuBuilder)

- (NSMenu *)buildMenu;
- (NSMenuItem *)buildProfileMenu;

@end

NS_ASSUME_NONNULL_END
