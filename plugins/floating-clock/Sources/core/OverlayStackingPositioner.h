// Overlay stacking geometry — DRY extraction 2026-06-12.
//
// The three overlays carried verbatim copies of the place-above-or-flip-
// below frame math (prefer NSMaxY(clock)+gap+stackOffset; flip below when
// that would leave the visible frame; clamp x into the screen). This pure
// function is the single source of truth — AppKit-free arithmetic over
// rects, so it links into the unit-test harness and is locked by
// test_levers (the old triplicated math was untestable in-place).
//
// stackOffset: total height+gap of every overlay BELOW this one in the
// stack (each indicator sums its visible juniors — that policy stays with
// the indicators; only the geometry lives here).
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Full overlay frame: clock-width, overlayHeight tall, x clamped into the
// visible frame, y above the clock (or below when the screen top would
// clip it).
NSRect FCComputeOverlayFrame(NSRect clockFrame, NSRect visibleFrame,
                             double overlayHeight, double stackOffset,
                             double gap);

// Content-width variant (2026-06-14): the audio I/O bar must grow wider than
// the clock so a full device name ("Terry's AirPods Pro") never truncates.
// `desiredWidth` is the content's natural width; the result is floored at the
// clock width (never smaller — keeps the bar visually tied to the clock),
// capped at the visible-frame width, CENTERED on the clock, then x-clamped
// into the screen. Y is identical to FCComputeOverlayFrame (above, or flip
// below at the screen top). FCComputeOverlayFrame == this with
// desiredWidth = clockFrame width.
NSRect FCComputeOverlayFrameWithWidth(NSRect clockFrame, NSRect visibleFrame,
                                      double overlayHeight, double stackOffset,
                                      double gap, double desiredWidth);

#ifdef __cplusplus
}
#endif
