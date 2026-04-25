// v4 iter-242: SSoT for LocalSegmentView's 5-row layout constants
// when ShowWeekProgress=YES (iter-231..iter-239).
//
// Vertical zones (top → bottom):
//   topMargin              kFCLocalTopMargin       breathing room above timestamp
//   timeLabel              (computed)              primary timestamp (variable height)
//   bottomMargin           kFCLocalBottomMargin    breathing room below timestamp
//   weekNumberLabel        kFCLocalWeekNumH        W## ISO 8601 row
//   weekDayLabelsLabel     kFCLocalDayLabelsH      M T W T F S S row
//   weekBarLabel           kFCLocalWeekBarH        7 day-groups of dots
//   debugLabel             kFCLocalDebugStripH     [LOCAL] corner overlay strip
//
// Total LOCAL height = timeLabel.height + density-pad + (sum of all
// other constants below). Layout.m uses the sum via
// kFCLocalWeekFeatureRowHeight; LocalSegmentView.layout uses each
// individually for frame placement. Both reference these constants —
// editing any one updates both call sites simultaneously.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kFCLocalDebugStripH;       // 16pt — bottom strip for [LOCAL]
extern const CGFloat kFCLocalWeekBarH;          // 22pt — week-progress bar row
extern const CGFloat kFCLocalDayLabelsH;        // 14pt — M T W T F S S row
extern const CGFloat kFCLocalWeekNumH;          // 14pt — W## row
extern const CGFloat kFCLocalTopMargin;         // 10pt — between top brim and timestamp
extern const CGFloat kFCLocalBottomMargin;      // 10pt — between timestamp and W## (symmetric)

// Total vertical space added to LOCAL when week-progress is on
// (sum of all rows + margins above, NOT including timeLabel itself).
extern const CGFloat kFCLocalWeekFeatureRowHeight;

NS_ASSUME_NONNULL_END
