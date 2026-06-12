#import "ClockChildWindowAttachment.h"

void FCAttachOverlayToClock(NSWindow *clock, NSWindow *overlay) {
    if (!clock || !overlay) return;
    if (overlay.parentWindow == clock) return;       // already welded
    if (overlay.parentWindow) {
        [overlay.parentWindow removeChildWindow:overlay];
    }
    [clock addChildWindow:overlay ordered:NSWindowAbove];
}

void FCDetachOverlayFromClock(NSWindow *overlay) {
    if (!overlay) return;
    if (overlay.parentWindow) {
        [overlay.parentWindow removeChildWindow:overlay];
    }
}

void FCHideOverlay(NSWindow *overlay) {
    if (!overlay) return;
    FCDetachOverlayFromClock(overlay);
    [overlay orderOut:nil];
}
