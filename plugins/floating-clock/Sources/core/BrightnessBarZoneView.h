// The interactive half of the brightness rail.
//
// Hit regions, left → right:
//   [☀][ track ..................][−][ 137% ][+]
//
//   · click the track  → jump to that position (slider affordance)
//   · drag on track    → scrub continuously
//   · −/+              → step by BrightnessBarStep
//   · the number       → top half nudges up, bottom half down
//   · scroll           → fine adjust
//   · right-click      → preset menu (also ctrl-click and two-finger tap)
//
// Unlike the audio and network zones this one DRAWS its track rather than
// composing it from label glyphs. A brightness rail has something those do
// not: a boundary at 100 % where the mechanism changes from the macOS slider
// to EDR headroom. A drawn tick at that point makes "you are now beyond the
// normal maximum" legible at a glance, which a run of block characters
// cannot do. Everything else follows the house pattern — a _renderKey
// composite so the 1 Hz tick allocates nothing at steady state, and
// -hitTest: routing every click here because NSTextField subviews would
// otherwise swallow them.
#import <Cocoa/Cocoa.h>

@class FCBrightnessStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCBrightnessZoneView : NSView

@property(nonatomic, weak) FCBrightnessStatusIndicator *owner;

- (instancetype)initWithFrame:(NSRect)frame
                        owner:(FCBrightnessStatusIndicator *)owner;

/// Apply fresh state. Internally cached — nothing redraws unless the visible
/// composite actually changed.
/// `level`   current rail level in percent (may exceed 100)
/// `maxLevel` rail ceiling (100 when the panel cannot boost)
/// `clamped` YES when the applied factor is below what `level` asked for,
///           so the bar can say so instead of silently under-delivering
/// `engaging` YES while EDR headroom is still ramping up
///
/// Returns YES when the composite CHANGED. The caller uses that to skip the
/// expensive width re-measurement on an unchanged tick — text measurement is
/// a full layout pass, and at 1 Hz on a bar whose number moves only when the
/// user touches it, doing it unconditionally is most of the rail's CPU cost.
- (BOOL)renderLevel:(NSInteger)level
           maxLevel:(NSInteger)maxLevel
            clamped:(BOOL)clamped
           engaging:(BOOL)engaging
          available:(BOOL)available;

/// Natural width of the drawn content, measured from what was actually
/// rendered — the width-consensus contract (see OverlayWidthConsensus.h).
- (CGFloat)naturalContentWidth;

@end

NS_ASSUME_NONNULL_END
