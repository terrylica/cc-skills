#import "OverlayStackingPositioner.h"

NSRect FCComputeOverlayFrame(NSRect clockFrame, NSRect visibleFrame,
                             double overlayHeight, double stackOffset,
                             double gap) {
    CGFloat w = clockFrame.size.width;
    CGFloat x = clockFrame.origin.x;
    CGFloat aboveY = NSMaxY(clockFrame) + gap + stackOffset;
    CGFloat y;
    if (aboveY + overlayHeight <= NSMaxY(visibleFrame)) {
        y = aboveY;                                              // preferred: above the clock
    } else {
        y = clockFrame.origin.y - gap - overlayHeight - stackOffset;  // flip: below (clock at top edge)
    }
    if (x + w > NSMaxX(visibleFrame)) x = NSMaxX(visibleFrame) - w;
    if (x < visibleFrame.origin.x)    x = visibleFrame.origin.x;
    return NSMakeRect(x, y, w, overlayHeight);
}
