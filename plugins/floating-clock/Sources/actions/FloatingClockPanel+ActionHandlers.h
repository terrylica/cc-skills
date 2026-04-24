// Category: NSMenuItem action handlers for FloatingClockPanel.
//
// Thin wrappers around NSUserDefaults writes + applyDisplaySettings
// invocation. One handler per settable pref: toggles, string pickers,
// number pickers, plus resetPosition / showAbout / quit / applyTheme.
//
// applyTheme is here (not in +Layout) because it's a rendering helper
// dual-purposed as the apply-side of any theme-change action.
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (ActionHandlers)

- (void)toggleShowSeconds:(NSMenuItem *)sender;
- (void)toggleShowDate:(NSMenuItem *)sender;
- (void)setTimeFormat:(NSMenuItem *)sender;
- (void)setFontSize:(NSMenuItem *)sender;
- (void)setColorTheme:(NSMenuItem *)sender;
- (void)setLocalTheme:(NSMenuItem *)sender;
- (void)setActiveTheme:(NSMenuItem *)sender;
- (void)setNextTheme:(NSMenuItem *)sender;
- (void)setMarket:(NSMenuItem *)sender;
- (void)setDisplayMode:(NSMenuItem *)sender;
- (void)setCanvasOpacity:(NSMenuItem *)sender;
- (void)setActiveBarCells:(NSMenuItem *)sender;
- (void)setProgressBarStyle:(NSMenuItem *)sender;
- (void)setLayoutMode:(NSMenuItem *)sender;
- (void)setSegmentGap:(NSMenuItem *)sender;
- (void)setCornerStyle:(NSMenuItem *)sender;
- (void)setShadowStyle:(NSMenuItem *)sender;
- (void)setActiveFontSize:(NSMenuItem *)sender;
- (void)setNextFontSize:(NSMenuItem *)sender;
- (void)toggleShowFlags:(NSMenuItem *)sender;
- (void)setDensity:(NSMenuItem *)sender;
- (void)setNextItemCount:(NSMenuItem *)sender;
- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field;
- (void)resetPosition:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;

@end

NS_ASSUME_NONNULL_END
