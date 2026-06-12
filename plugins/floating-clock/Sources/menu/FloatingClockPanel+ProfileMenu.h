// Category: the Profile submenu (profile list + save / delete).
// Split from FloatingClockPanel+MenuBuilder (2026-06-12 modularization).
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (ProfileMenu)
- (NSMenuItem *)buildProfileMenu;
@end

NS_ASSUME_NONNULL_END
