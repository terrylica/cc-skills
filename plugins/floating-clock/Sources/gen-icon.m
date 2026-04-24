#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreServices/CoreServices.h>
#import <math.h>

static void drawIcon(CGContextRef ctx, CGFloat s);

int main(int argc, const char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "usage: gen-icon <out.png> <size>\n");
        return 1;
    }

    const char *outPath = argv[1];
    int size = atoi(argv[2]);

    if (size <= 0 || size > 2048) {
        fprintf(stderr, "invalid size (must be 0 < size <= 2048)\n");
        return 1;
    }

    // Create SRGB color space and bitmap context
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!cs) {
        fprintf(stderr, "failed to create color space\n");
        return 1;
    }

    CGContextRef ctx = CGBitmapContextCreate(NULL, size, size, 8, size * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);

    if (!ctx) {
        fprintf(stderr, "failed to create bitmap context\n");
        return 1;
    }

    // Draw the icon
    drawIcon(ctx, size);

    // Extract image from context
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    if (!img) {
        fprintf(stderr, "failed to create image from context\n");
        CGContextRelease(ctx);
        return 1;
    }

    // Create URL from file path
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)outPath, strlen(outPath), false);
    if (!url) {
        fprintf(stderr, "failed to create URL for output path\n");
        CGImageRelease(img);
        CGContextRelease(ctx);
        return 1;
    }

    // Create image destination and write PNG
    CGImageDestinationRef dest = NULL;

    // macOS 11+ uses UTType, older versions use CFString
    if (@available(macOS 11.0, *)) {
        dest = CGImageDestinationCreateWithURL(url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    } else {
        dest = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    }

    if (!dest) {
        fprintf(stderr, "failed to create image destination\n");
        CFRelease(url);
        CGImageRelease(img);
        CGContextRelease(ctx);
        return 1;
    }

    CGImageDestinationAddImage(dest, img, NULL);
    if (!CGImageDestinationFinalize(dest)) {
        fprintf(stderr, "failed to finalize image destination\n");
        CFRelease(dest);
        CFRelease(url);
        CGImageRelease(img);
        CGContextRelease(ctx);
        return 1;
    }

    // Cleanup
    CFRelease(dest);
    CFRelease(url);
    CGImageRelease(img);
    CGContextRelease(ctx);

    return 0;
}

static void drawIcon(CGContextRef ctx, CGFloat s) {
    // Fill background with white first (clear background)
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, s, s));

    // Background: dark rounded square (inset to respect macOS icon padding)
    CGFloat inset = s * 0.10;
    CGRect bgRect = CGRectMake(inset, inset, s - 2*inset, s - 2*inset);
    CGFloat cornerRadius = s * 0.22;  // ~22% matches macOS Big Sur+ icon corner radius

    CGContextSaveGState(ctx);
    CGPathRef bgPath = CGPathCreateWithRoundedRect(bgRect, cornerRadius, cornerRadius, NULL);
    CGContextAddPath(ctx, bgPath);
    CGContextSetRGBFillColor(ctx, 0.12, 0.12, 0.14, 1.0);  // Dark charcoal
    CGContextFillPath(ctx);
    CGPathRelease(bgPath);
    CGContextRestoreGState(ctx);

    // Clock face circle (white)
    CGFloat faceInset = s * 0.22;
    CGRect faceRect = CGRectMake(faceInset, faceInset, s - 2*faceInset, s - 2*faceInset);
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.95);
    CGContextFillEllipseInRect(ctx, faceRect);

    // Center of clock
    CGFloat cx = s / 2.0;
    CGFloat cy = s / 2.0;
    CGFloat clockRadius = (s / 2.0) - faceInset;

    // Hour ticks at 12, 3, 6, 9 (dark color matching background)
    CGFloat rOut = clockRadius * 0.90;
    CGFloat rIn  = clockRadius * 0.75;
    CGFloat tickWidth = s * 0.015;

    CGContextSetRGBStrokeColor(ctx, 0.12, 0.12, 0.14, 1.0);
    CGContextSetLineWidth(ctx, tickWidth);
    CGContextSetLineCap(ctx, kCGLineCapRound);

    for (int i = 0; i < 4; i++) {
        double angle = i * M_PI_2 - M_PI_2;  // -π/2, 0, π/2, π (12, 3, 6, 9 positions)
        CGContextMoveToPoint(ctx, cx + cos(angle) * rIn, cy + sin(angle) * rIn);
        CGContextAddLineToPoint(ctx, cx + cos(angle) * rOut, cy + sin(angle) * rOut);
    }
    CGContextStrokePath(ctx);

    // Clock hands at 10:10 (classic watch-ad pose)
    CGFloat handWidth = s * 0.022;
    CGContextSetLineWidth(ctx, handWidth);
    CGContextSetRGBStrokeColor(ctx, 0.12, 0.12, 0.14, 1.0);

    // Hour hand: 10 o'clock
    // 12 o'clock is -π/2. Each hour is +π/6 (30 degrees).
    // 10 o'clock = -π/2 + (10/12)*2π = -π/2 + 5π/3 = 7π/6
    double hourAngle = -M_PI_2 + (10.0 / 12.0) * 2.0 * M_PI;
    CGFloat hourLen = clockRadius * 0.55;

    // Minute hand: 2 minutes (at :10 minutes, the minute hand is at 2)
    // 12 o'clock is -π/2. Each minute is +π/30 (6 degrees).
    // 2 minutes = -π/2 + (10/60)*2π = -π/2 + π/3 = -π/6
    double minuteAngle = -M_PI_2 + (10.0 / 60.0) * 2.0 * M_PI;
    CGFloat minuteLen = clockRadius * 0.80;

    // Draw hour hand
    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(ctx, cx + cos(hourAngle) * hourLen, cy + sin(hourAngle) * hourLen);
    CGContextStrokePath(ctx);

    // Draw minute hand
    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(ctx, cx + cos(minuteAngle) * minuteLen, cy + sin(minuteAngle) * minuteLen);
    CGContextStrokePath(ctx);

    // Center pin (dark circle)
    CGFloat pinR = s * 0.030;
    CGContextSetRGBFillColor(ctx, 0.12, 0.12, 0.14, 1.0);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - pinR, cy - pinR, 2*pinR, 2*pinR));
}
