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
- (void)refreshMenuChecks:(NSMenu *)menu;
- (NSMenuItem *)submenuTitled:(NSString *)title action:(SEL)action pairs:(NSArray *)pairs defaultsKey:(NSString *)key;
- (NSMenuItem *)groupedSubmenuTitled:(NSString *)title action:(SEL)action groups:(NSArray *)groups defaultsKey:(NSString *)key;
- (BOOL)setChecksInMenu:(NSMenu *)menu forKey:(NSString *)key currentValue:(id)current;
- (BOOL)representedObject:(id)ro matchesValue:(id)v;
- (NSMenuItem *)buildProfileMenu;

@end

NS_ASSUME_NONNULL_END
