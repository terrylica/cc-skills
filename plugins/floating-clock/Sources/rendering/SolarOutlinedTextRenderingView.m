#import "SolarOutlinedTextRenderingView.h"
#import <CoreText/CoreText.h>

@implementation FCSolarOutlinedTextView

- (void)setText:(NSString *)text {
    if ([_text isEqualToString:text]) return;
    _text = [text copy];
    self.needsDisplay = YES;
}

- (void)setFont:(NSFont *)font {
    if ([_font isEqual:font]) return;
    _font = font;
    self.needsDisplay = YES;
}

- (void)setOutlineWidth:(CGFloat)outlineWidth {
    if (_outlineWidth == outlineWidth) return;
    _outlineWidth = outlineWidth;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.text.length == 0) return;
    NSFont *font = self.font
        ?: [NSFont monospacedSystemFontOfSize:24 weight:NSFontWeightMedium];

    // kCTForegroundColorFromContext is ESSENTIAL: without it CTLineDraw
    // fills with the run's own color (default BLACK), ignoring the
    // context fill color — both passes came out black ("total disaster",
    // user-caught 2026-06-11). With it, the context colors drive each pass.
    NSAttributedString *attr = [[NSAttributedString alloc]
        initWithString:self.text
            attributes:@{
                NSFontAttributeName: font,
                (__bridge id)kCTForegroundColorFromContextAttributeName: @YES,
            }];
    CTLineRef line = CTLineCreateWithAttributedString(
        (__bridge CFAttributedStringRef)attr);
    if (!line) return;

    CGFloat ascent = 0, descent = 0, leading = 0;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    NSRect b = self.bounds;
    // Horizontal optical centering (user-tuned 2026-06-11): geometric center
    // minus one device pixel — the trailing-space rhythm of the mono layout
    // reads slightly right-heavy otherwise.
    static const CGFloat kOpticalShiftLeftPoints = 2.0;   // user-tuned: 0.5 → 1.5 → 2.0
    CGFloat x = (b.size.width  - (CGFloat)width) / 2.0 - kOpticalShiftLeftPoints;
    // Optical lift (user-tuned 2026-06-11): the typographic ascent/descent
    // box centers the METRIC box, but cap-height glyphs (A, U, N, digits)
    // read slightly low to the eye — user measured 11px top / 12px bottom
    // padding and asked for one device pixel up. +0.5pt = 1px @2x Retina.
    static const CGFloat kOpticalLiftPoints = 1.5;   // user-tuned: 0.5 → 1.0 → 1.5
    CGFloat y = (b.size.height - (ascent + descent)) / 2.0 + descent
              + kOpticalLiftPoints;

    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
    CGContextSaveGState(ctx);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);   // the whole point: no miter spikes
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineWidth(ctx, self.outlineWidth * 2.0);
    CGContextSetStrokeColorWithColor(ctx, NSColor.blackColor.CGColor);
    CGContextSetTextDrawingMode(ctx, kCGTextStroke);
    CGContextSetTextPosition(ctx, x, y);
    CTLineDraw(line, ctx);

    CGContextSetFillColorWithColor(ctx, NSColor.whiteColor.CGColor);
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextSetTextPosition(ctx, x, y);
    CTLineDraw(line, ctx);
    CGContextRestoreGState(ctx);
    CFRelease(line);
}

@end
