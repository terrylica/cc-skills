// Segment hairline-border presets — user request 2026-06-11.
//
// The audio bar's research-converged "dual-layer" edge treatment (1pt
// hairline + elevated surface + shadow) promoted to the clock body: each
// segment pill gets a lightly painted border so it separates from
// pure-black (where shadows are invisible) and busy backgrounds alike.
//
// The spec carries only width + alpha; the COLOR is chosen by the caller
// per segment, luminance-adaptive against the segment's theme background
// (light hairline on dark fills, dark hairline on light fills) — unlike
// the always-dark audio bar, clock themes span the full range.
//
// Dispatcher pattern mirrors ShadowSpec / CornerRadius: id → spec catalog,
// locked by tests/test_levers.m. NSUserDefaults key: "BorderStyle".
//   none      — flat, no border
//   hairline  — 1.0pt @ 0.22 (DEFAULT; the audio-bar recipe)
//   frame     — 1.5pt @ 0.35 (stronger, deliberate framing)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct {
    BOOL    enabled;
    CGFloat width;   // border width in points
    CGFloat alpha;   // hairline alpha (caller picks black/white by luminance)
} FCSegmentBorderSpec;

#ifdef __cplusplus
extern "C" {
#endif

// nil / empty / unknown ids resolve to the DEFAULT preset ("hairline") —
// the border is on by default, like the audio bar's.
FCSegmentBorderSpec FCSegmentBorderSpecForId(NSString *_Nullable styleId);

#ifdef __cplusplus
}
#endif
