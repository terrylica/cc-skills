// Round-join outlined text view — solar canvas legibility, 2026-06-11.
//
// Renders white-filled text wrapped in a SOLID black outline of arbitrary
// thickness with ROUND line joins. Replaces the NSTextField stroke-attribute
// approaches, both rejected on-screen:
//   · negative NSStrokeWidth (single field): centered stroke eats the fill
//     from inside (-6.0 left the white nearly invisible)
//   · positive NSStrokeWidth underlay (two fields): NSAttributedString
//     exposes NO line-join control, and the default MITER join spikes on
//     curved descenders (user-caught: a spur under the "y")
// Core Text + CGContext gives kCGLineJoinRound: clean dilation-style
// borders at any width. Two passes per draw: stroke (2× width, centered on
// the glyph path — outer half visible) then fill on top.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FCSolarOutlinedTextView : NSView

@property (nonatomic, copy, nullable) NSString *text;        // redraws on change
@property (nonatomic, strong, nullable) NSFont *font;
@property (nonatomic, assign) CGFloat outlineWidth;          // visible band, points

@end

NS_ASSUME_NONNULL_END
