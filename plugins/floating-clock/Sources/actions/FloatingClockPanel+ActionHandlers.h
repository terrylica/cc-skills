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
- (void)setFontWeight:(NSMenuItem *)sender;
- (void)setActiveWeight:(NSMenuItem *)sender;
- (void)setNextWeight:(NSMenuItem *)sender;
- (void)setLetterSpacing:(NSMenuItem *)sender;
- (void)setLineSpacing:(NSMenuItem *)sender;
- (void)setTimeSeparator:(NSMenuItem *)sender;
- (void)setSessionSignalWindow:(NSMenuItem *)sender;
- (void)applyQuickStyle:(NSMenuItem *)sender;
- (void)toggleShowFlags:(NSMenuItem *)sender;
- (void)toggleShowUTCReference:(NSMenuItem *)sender;
- (void)toggleShowSkyState:(NSMenuItem *)sender;
- (void)toggleShowProgressPercent:(NSMenuItem *)sender;
- (void)copyStateToClipboard:(id)sender;
- (void)setDensity:(NSMenuItem *)sender;
- (void)setNextItemCount:(NSMenuItem *)sender;
- (void)applyTheme:(const ClockTheme *)theme
     toSegmentView:(NSView *)seg
         textField:(NSTextField *)field
       opacityKey:(NSString *)opacityKey;
- (void)setLocalOpacity:(NSMenuItem *)sender;
- (void)setActiveOpacity:(NSMenuItem *)sender;
- (void)setNextOpacity:(NSMenuItem *)sender;
- (void)resetPosition:(id)sender;
- (void)resetVisualStyle:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;

@end

NS_ASSUME_NONNULL_END
