#import "UrgencyColors.h"

const long kFCUrgencyRedThresholdSecs   = 30 * 60;   // 1800 s — last half-hour
const long kFCUrgencyAmberThresholdSecs = 60 * 60;   // 3600 s — last hour

NSColor *FCUrgencyAmberColor(void) {
    return [NSColor colorWithRed:0.95 green:0.75 blue:0.30 alpha:1.0];
}

NSColor *FCUrgencyRedColor(void) {
    return [NSColor colorWithRed:0.95 green:0.40 blue:0.40 alpha:1.0];
}

NSColor *FCUrgencyColorForSecs(long secs, NSColor *normalColor) {
    if (secs < kFCUrgencyRedThresholdSecs)   return FCUrgencyRedColor();
    if (secs < kFCUrgencyAmberThresholdSecs) return FCUrgencyAmberColor();
    return normalColor;
}

NSColor *FCProgressEmptyColor(void) {
    return [NSColor colorWithWhite:0.40 alpha:0.55];
}

NSColor *FCDividerRuleColor(void) {
    return [NSColor colorWithWhite:0.40 alpha:0.55];
}
