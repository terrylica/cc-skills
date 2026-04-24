// Public interface of the main NSPanel subclass. All public methods that
// other modules (menu builders, layout, etc.) invoke are declared here.
// The @implementation currently still lives in clock.m — subsequent
// iterations split it into core/FloatingClockPanel.m +
// core/FloatingClockPanel+Layout.m.
#import <Cocoa/Cocoa.h>
#import "../data/ThemeCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel : NSPanel {
    NSTextField *_label;
    NSTextField *_sessionLabel;
    dispatch_source_t _timer;
    NSDateFormatter *_dateFormatter;
    id _keyMonitor;
    LocalSegmentView *_localSeg;
    ActiveSegmentView *_activeSeg;
    NextSegmentView *_nextSeg;
}
// Menu builders + helpers live in Sources/menu/FloatingClockPanel+MenuBuilder.{h,m}
- (void)applyDisplaySettings;
- (NSRect)clampFrameToVisibleScreen:(NSRect)proposed;
- (void)applyThreeSegmentLayout;
- (void)relayoutThreeSegmentIfNeeded;
- (void)applySingleMarketLayout;
- (void)applyLocalOnlyLayout;
- (void)tickThreeSegment;
- (void)tickLegacy;
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
- (void)setActiveBarCells:(NSMenuItem *)sender;
- (void)setNextItemCount:(NSMenuItem *)sender;
- (void)setCanvasOpacity:(NSMenuItem *)sender;
- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field;
- (void)resetPosition:(id)sender;
- (void)showAbout:(id)sender;
- (void)quit:(id)sender;
- (void)activateProfile:(NSString *)name;
- (void)saveCurrentProfileAs:(id)sender;
- (void)quickSaveCurrentProfile:(id)sender;
- (void)setDateFormat:(NSMenuItem *)sender;
- (void)deleteProfile:(NSMenuItem *)sender;
- (void)switchToProfile:(NSMenuItem *)sender;
- (void)recordProfileActivationInCCMemory:(NSString *)profileName;
@end

NS_ASSUME_NONNULL_END
