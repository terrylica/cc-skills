// Shared NSMenu-building helpers for the full-prefs and segment-scoped
// menus.
//
// Extracted v4 iter-96 from FloatingClockPanel+MenuBuilder.m when it
// approached the 500-LoC cap (contract rule — split proactively, not
// after crossing). MenuBuilder.m retains buildMenu (the full prefs
// tree) + buildProfileMenu (profile state helper); SegmentMenus.m
// holds the 3 segment-scoped menu builders. Both depend on this
// header.
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (MenuHelpers)

// Builds a two-level menu item whose submenu contains leaf items with
// `representedObject = pair[1]` and title `pair[0]`. Tapping a leaf
// fires `action` on `self`. `defaultsKey` is currently informational
// (kept for refreshMenuChecks dispatch) — the actual persistence
// happens in the action handler.
- (NSMenuItem *)submenuTitled:(NSString *)title
                        action:(SEL)action
                         pairs:(NSArray *)pairs
                   defaultsKey:(NSString *)key;

// Like submenuTitled but with one extra layer of grouping. `groups`
// is an array of pairs [groupTitle, leafPairs] where leafPairs follows
// the same shape as submenuTitled's `pairs`.
- (NSMenuItem *)groupedSubmenuTitled:(NSString *)title
                                action:(SEL)action
                                groups:(NSArray *)groups
                          defaultsKey:(NSString *)key;

// Walks `menu` (recursive) and checks the leaf whose representedObject
// matches `current` for the supplied `key`. Parents get mixed-state
// when a descendant is checked. Returns YES if any descendant matched.
- (BOOL)setChecksInMenu:(NSMenu *)menu forKey:(NSString *)key currentValue:(id)current;

// Compares represented-object value to the NSUserDefaults value.
// Numeric values compared by doubleValue; everything else by isEqual:.
- (BOOL)representedObject:(id)ro matchesValue:(id)v;

// Applied as NSMenu delegate's menuNeedsUpdate: equivalent. Walks the
// full-prefs menu and refreshes checkbox / radio state from current
// NSUserDefaults before it pops up.
- (void)refreshMenuChecks:(NSMenu *)menu;

@end

NS_ASSUME_NONNULL_END
