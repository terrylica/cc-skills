// Public interface of the main NSPanel subclass. All public methods that
// other modules (menu builders, layout, etc.) invoke are declared here.
// The @implementation currently still lives in clock.m — subsequent
// iterations split it into core/FloatingClockPanel.m +
// core/FloatingClockPanel+Layout.m.
#import <Cocoa/Cocoa.h>
#import "../data/ThemeCatalog.h"
#import "../segments/FloatingClockSegmentViews.h"

@class FCMicMuteIndicator;     // mic-mute banner overlay (user directive 2026-06-01)
@class FCVPNStatusIndicator;   // generic state-file status banner (e.g. VPN/tunnel; 2026-06-07)
@class FCAudioStatusIndicator; // always-visible audio I/O device + level bar (2026-06-11)
@class FCSolarOutlinedTextView; // round-join outlined compact text (solar canvas, 2026-06-11)

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel : NSPanel {
    NSTextField *_label;
    FCSolarOutlinedTextView *_labelOutline; // 2026-06-11 solar canvas: round-join
                                            // Core Text outline+fill renderer that
                                            // REPLACES _label while solar is active
                                            // (_label stays populated for sizing)
    NSTextField *_sessionLabel;
    dispatch_source_t _timer;
    NSDateFormatter *_dateFormatter;
    NSDateFormatter *_utcFormatter;
    id _keyMonitor;
    LocalSegmentView *_localSeg;
    WeekSegmentView *_weekSeg;     // iter-251: 4-block layout — week as own segment
    ActiveSegmentView *_activeSeg;
    NextSegmentView *_nextSeg;
    // Mic-mute indicator: red "MIC MUTED" banner over the clock when the
    // Antlion USB Microphone is muted. Synced from tick + windowDidMove.
    FCMicMuteIndicator *_micMuteIndicator;
    // Generic external-state status banner (default violet); stacks above the
    // mic-mute bar. Driven by a state file; configured via NSUserDefaults
    // (VPNIndicator*). Disabled by default. Synced from tick + windowDidMove.
    FCVPNStatusIndicator *_vpnStatusIndicator;
    // Always-visible audio I/O status bar (2026-06-11): current default
    // input/output devices + numeric levels, click-to-toggle device cycling,
    // direct level adjustment. Bottom-most overlay in the indicator stack;
    // mic-mute and VPN bars stack above it. Synced from tick + windowDidMove.
    FCAudioStatusIndicator *_audioStatusIndicator;
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
