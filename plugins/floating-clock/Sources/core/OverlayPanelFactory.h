// Overlay panel + banner-label construction — DRY extraction 2026-06-12.
//
// The three clock overlays (audio I/O bar, mic-mute banner, VPN banner)
// carried verbatim copies of the borderless-NSPanel setup (11 property
// assignments) and two of them the banner-label setup (9 assignments).
// This factory is the single source of truth for overlay WIDGET
// CONSTRUCTION; positioning lives in OverlayStackingPositioner, and
// parent-child welding in ClockChildWindowAttachment — one concern per
// module, so a future fourth overlay composes all three with ~5 lines.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// A borderless, non-activating overlay panel one level above the clock:
// transparent background + shadow, joins all Spaces, stationary, excluded
// from window cycling, never hides on deactivate, never drag-movable.
// ignoresMouse: YES for detection-only banners (mic-mute, VPN); NO when the
// overlay carries controls (audio bar zones).
NSPanel *FCCreateOverlayPanel(NSPanel *_Nullable clockPanel, CGSize size,
                              BOOL ignoresMouse);

// The banners' centered monospaced label (white, 12pt bold, 16pt tall,
// vertically centered in `bannerHeight`, width-tracking).
NSTextField *FCCreateBannerLabel(CGFloat bannerHeight, CGFloat width,
                                 NSString *text);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
