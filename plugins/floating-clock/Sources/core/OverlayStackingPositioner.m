#import "OverlayStackingPositioner.h"

NSRect FCComputeOverlayFrameWithWidth(NSRect clockFrame, NSRect visibleFrame,
                                      double overlayHeight, double stackOffset,
                                      double gap, double desiredWidth) {
    // Width: never narrower than the clock (keeps the bar tied to it), never
    // wider than the screen.
    CGFloat clockW = clockFrame.size.width;
    CGFloat w = desiredWidth < clockW ? clockW : desiredWidth;
    if (w > visibleFrame.size.width) w = visibleFrame.size.width;

    // Center the (possibly wider) overlay on the clock, then clamp x so it
    // stays fully on-screen.
    CGFloat x = (clockFrame.origin.x + clockW / 2.0) - w / 2.0;
    if (x + w > NSMaxX(visibleFrame)) x = NSMaxX(visibleFrame) - w;
    if (x < visibleFrame.origin.x)    x = visibleFrame.origin.x;

    // Y: preferred above the clock; flip below when the screen top clips it.
    CGFloat aboveY = NSMaxY(clockFrame) + gap + stackOffset;
    CGFloat y = (aboveY + overlayHeight <= NSMaxY(visibleFrame))
                  ? aboveY
                  : clockFrame.origin.y - gap - overlayHeight - stackOffset;
    return NSMakeRect(x, y, w, overlayHeight);
}

NSRect FCComputeOverlayFrame(NSRect clockFrame, NSRect visibleFrame,
                             double overlayHeight, double stackOffset,
                             double gap) {
    // Clock-width overlay: the width-aware variant with desired == clock width
    // (centering clock-width on the clock reproduces the old left-aligned x).
    return FCComputeOverlayFrameWithWidth(clockFrame, visibleFrame, overlayHeight,
                                          stackOffset, gap, clockFrame.size.width);
}
