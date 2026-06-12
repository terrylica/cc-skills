// Clock overlay child-window attachment — user directive 2026-06-12.
//
// THE single home for the parent/child window-welding concern. The clock's
// overlay panels (audio I/O bar, mic-mute banner, VPN banner) are separate
// NSPanels that used to CHASE the clock via windowDidMove → syncPosition —
// always one move-event behind, so fast drags visibly decoupled the bar
// from the clock (user-caught "elastic trail"). Attaching each overlay as a
// CHILD WINDOW makes the WindowServer move it atomically with the clock:
// zero lag, zero per-move follow code.
//
// Separation of concerns (explicit design contract):
//   · Each indicator OWNS its content, visibility policy, and RELATIVE
//     stacking layout (its syncPosition keeps computing frames — child
//     windows accept setFrame freely and keep the new offset thereafter).
//   · THIS module owns only the attachment semantics: idempotent attach,
//     and the detach-BEFORE-orderOut dance Apple requires (hiding an
//     attached child without detaching first is documented-fragile).
// New overlays get welding by calling these two functions at their
// show/hide points — nothing else to subclass or register.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Attach `overlay` as a child of `clock`, ordered above. Idempotent — safe
// to call on every sync pass; no-ops when already attached.
void FCAttachOverlayToClock(NSWindow *_Nullable clock, NSWindow *_Nullable overlay);

// Detach (idempotent) — MUST be called before orderOut:-hiding an overlay.
void FCDetachOverlayFromClock(NSWindow *_Nullable overlay);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
