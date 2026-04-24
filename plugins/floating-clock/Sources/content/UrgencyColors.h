// Shared urgency-tier color palette used by ACTIVE (time to close)
// and NEXT (time to open/resume) countdowns. Extracted v4 iter-73
// per user directive: magic-numberless + SSoT.
//
// Tiers:
//   secs >= kFCUrgencyAmberThresholdSecs   →  kFCUrgencyNormalColor (caller-provided default)
//   secs <  kFCUrgencyAmberThresholdSecs   →  kFCUrgencyAmberColor
//   secs <  kFCUrgencyRedThresholdSecs     →  kFCUrgencyRedColor
//
// Numeric thresholds and RGB values have single definitions here;
// both builders reference them via symbols so a tweak in one place
// updates both paths simultaneously.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Thresholds in seconds-until-event.
extern const long kFCUrgencyRedThresholdSecs;    // <30 min  — imminent
extern const long kFCUrgencyAmberThresholdSecs;  // <60 min  — approaching

// Palette. Callers pass `normalColor` (usually the segment's headerColor)
// since that's theme-dependent; amber/red are fixed.
NSColor *FCUrgencyAmberColor(void);
NSColor *FCUrgencyRedColor(void);

// Single entry point: returns the right color for the given delta.
// `normalColor` is used when secs >= kFCUrgencyAmberThresholdSecs.
NSColor *FCUrgencyColorForSecs(long secs, NSColor *normalColor);

// Shared background/empty color for progress-bar "unfilled" cells.
// Centralizes the one RGB that was duplicated in both builders.
NSColor *FCProgressEmptyColor(void);

// Shared horizontal-rule color. Used by SegmentHeaderRenderer's rules
// and by any caller that wants a consistent dim divider.
NSColor *FCDividerRuleColor(void);

NS_ASSUME_NONNULL_END
