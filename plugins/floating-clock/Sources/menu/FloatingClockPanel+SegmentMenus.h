// Category hosting the segment-scoped context menus (right-click on
// LOCAL / ACTIVE / NEXT) plus the 'Full Preferences…' escape hatch
// that pops the full menu from any segment.
//
// Extracted v4 iter-87 from FloatingClockPanel+MenuBuilder.m when it
// crossed the 500-LoC hard cap (contract rule). MenuBuilder.m keeps
// buildMenu + submenu helpers + refreshMenuChecks + buildProfileMenu.
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (SegmentMenus)

- (NSMenu *)buildLocalSegmentMenu;
- (NSMenu *)buildActiveSegmentMenu;
- (NSMenu *)buildNextSegmentMenu;
- (void)showFullPreferences:(id)sender;

@end

NS_ASSUME_NONNULL_END
