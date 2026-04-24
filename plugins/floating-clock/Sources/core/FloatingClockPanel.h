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
    NSDateFormatter *_utcFormatter;
    id _keyMonitor;
    LocalSegmentView *_localSeg;
    ActiveSegmentView *_activeSeg;
    NextSegmentView *_nextSeg;
}
// Menu builders + helpers → Sources/menu/FloatingClockPanel+MenuBuilder.{h,m}
// Layout methods            → Sources/core/FloatingClockPanel+Layout.{h,m}
// v4 iter-80: the methods clampFrameToVisibleScreen:/defaultFrame/tick/
// tickThreeSegment/tickLegacy moved to FloatingClockPanel+Runtime.h
// (they are implemented in the Runtime category). Declaring them in
// the primary @interface while categorically implementing them triggered
// -Wobjc-protocol-method-implementation. Now declared only once, in
// their implementing category.
// Profile management → Sources/preferences/FloatingClockPanel+ProfileManagement.{h,m}
- (void)setDateFormat:(NSMenuItem *)sender;
@end

NS_ASSUME_NONNULL_END
