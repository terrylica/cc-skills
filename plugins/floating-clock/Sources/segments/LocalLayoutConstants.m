#import "LocalLayoutConstants.h"

// v4 iter-248: kFCLocalDebugStripH zeroed — [LOCAL]/[ACTIVE]/[NEXT]
// canonical corner overlays removed per user directive. Strip space
// reclaimed by the week-bar layer (cleaner LOCAL bottom edge).
const CGFloat kFCLocalDebugStripH      = 0.0;
const CGFloat kFCLocalWeekBarH         = 22.0;
const CGFloat kFCLocalDayLabelsH       = 14.0;
const CGFloat kFCLocalWeekNumH         = 14.0;
const CGFloat kFCLocalTopMargin        = 10.0;
const CGFloat kFCLocalBottomMargin     = 10.0;

const CGFloat kFCLocalWeekFeatureRowHeight =
    kFCLocalDebugStripH + kFCLocalWeekBarH + kFCLocalDayLabelsH +
    kFCLocalWeekNumH + kFCLocalTopMargin + kFCLocalBottomMargin;  // 70.0
