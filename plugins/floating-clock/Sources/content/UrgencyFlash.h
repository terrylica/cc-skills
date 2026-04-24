// v4 iter-219: dispatcher for the 1Hz pulse intensity used by
// FCUrgencyFlashAlpha (iter-212).
//
// iter-212 hardcoded the dim-half alpha at kFCUrgencyFlashDimAlpha
// (0.45) — a single fixed pulse strength. Users vary in how
// distracting they find the pulse: some want it OFF entirely (the
// flashing is more annoying than informative when their workflow
// already attends to the gradient color), some want a subtle hint,
// some want maximum attention-grab.
//
// Pattern matches iter-126 (SessionSignalWindow) + iter-215
// (UrgencyHorizon): preset id (NSString) → numeric value (CGFloat),
// tested via fixture, runtime entry point reads NSUserDefaults +
// falls back to the iter-212 SSoT default for unset/empty/unknown.
//
// Presets map to dim-half alpha (the alpha during the dim half of
// the 1Hz pulse — 1.0 means no perceptible pulse, 0.0 means the
// dim half is invisible):
//   "off"     → 1.0   pulse disabled (always full alpha)
//   "subtle"  → 0.80  gentle hint, ~20% drop on dim half
//   "normal"  → 0.45  default — matches iter-212 kFCUrgencyFlashDimAlpha
//   "intense" → 0.15  strong attention-grab, deep dim
//
// Unknown / nil / empty → 0.45 (default fallback, preserves iter-212
// behavior for installs that never set the pref).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

CGFloat FCUrgencyFlashDimAlphaForId(NSString * _Nullable presetId);

// Convenience: read pref from NSUserDefaults @"UrgencyFlash". Used by
// FCUrgencyFlashAlpha at runtime so a single menu pick re-tunes the
// pulse on the next tick.
CGFloat FCUrgencyFlashDimAlphaCurrent(void);

// Convenience: returns YES when preset == "off" so callers can
// short-circuit the pulse entirely without computing the modulo.
BOOL FCUrgencyFlashIsDisabled(void);

NS_ASSUME_NONNULL_END
