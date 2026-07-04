// 2026-06 styling-lever fixtures — split from test_levers.m during the
// 2026-06-12 modularization (it had breached the 1000-LoC test-file cap;
// same precedent as the iter-118 / iter-176 / iter-193 fixture splits).
// Covers SegmentBorderSpec, SolarSkyColorRamp + FCSolarElevationDegrees,
// and OverlayStackingPositioner. Declarations stay in test_levers.h.
#import "test_levers.h"
#import "test_helpers.h"
#import "../Sources/core/SegmentBorderSpec.h"
#import "../Sources/core/SolarSkyColorRamp.h"
#import "../Sources/core/OverlayStackingPositioner.h"
#import "../Sources/core/CoreAudioDeviceHALHelpers.h"
#import "../Sources/data/SolarEvents.h"
#import <math.h>

void test_segment_border_spec_catalog(void) {
    // 2026-06-11: hairline segment border presets (audio-bar edge recipe
    // promoted to the clock). UNLIKE ShadowSpec, the DEFAULT is ON:
    // nil / empty / unknown all resolve to "hairline".
    struct { NSString *id; BOOL enabled; CGFloat width, alpha; } cases[] = {
        {@"none",     NO,  0.0, 0.0},
        {@"hairline", YES, 1.0, 0.22},
        {@"frame",    YES, 1.5, 0.35},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        FCSegmentBorderSpec b = FCSegmentBorderSpecForId(cases[i].id);
        BOOL ok = b.enabled == cases[i].enabled &&
                  fabs(b.width - cases[i].width) < 0.001 &&
                  fabs(b.alpha - cases[i].alpha) < 0.001;
        if (!ok) {
            fprintf(stderr, "FAIL %s: '%s' enabled=%d w=%.2f a=%.2f\n",
                    __func__, cases[i].id.UTF8String,
                    b.enabled, (double)b.width, (double)b.alpha);
            failures++;
        }
    }
    // Default-on semantics: nil / empty / unknown → hairline.
    FCSegmentBorderSpec defaults[] = {
        FCSegmentBorderSpecForId(nil),
        FCSegmentBorderSpecForId(@""),
        FCSegmentBorderSpecForId(@"chrome"),
    };
    for (size_t i = 0; i < 3; i++) {
        if (!defaults[i].enabled || fabs(defaults[i].width - 1.0) > 0.001 ||
            fabs(defaults[i].alpha - 0.22) > 0.001) {
            failures++;
            fprintf(stderr, "FAIL %s: default case %zu should be hairline\n", __func__, i);
        }
    }
}

void test_overlay_stacking_positioner(void) {
    // 2026-06-12 DRY extraction: the place-above-or-flip-below overlay
    // geometry was triplicated (audio/mic/VPN) and untestable in place.
    // Lock the invariants here.
    NSRect vf = NSMakeRect(0, 0, 1000, 800);

    // Mid-screen clock → overlay sits ABOVE: y = maxY(clock) + gap + stack.
    NSRect clock = NSMakeRect(100, 400, 320, 60);
    NSRect f = FCComputeOverlayFrame(clock, vf, 20, 0, 3);
    if (f.origin.y != 463 || f.origin.x != 100 || f.size.width != 320 || f.size.height != 20) {
        failures++; fprintf(stderr, "FAIL %s: above-placement wrong (%.0f,%.0f %.0fx%.0f)\n",
                            __func__, f.origin.x, f.origin.y, f.size.width, f.size.height);
    }

    // Stack offset shifts the slot up by exactly the offset.
    NSRect f2 = FCComputeOverlayFrame(clock, vf, 20, 23, 3);
    if (f2.origin.y != 486) {
        failures++; fprintf(stderr, "FAIL %s: stack offset wrong (y=%.0f)\n", __func__, f2.origin.y);
    }

    // Clock at the top edge → overlay FLIPS BELOW (incl. the stack slot).
    NSRect top = NSMakeRect(100, 730, 320, 60);   // maxY 790; 790+3+20 > 800
    NSRect f3 = FCComputeOverlayFrame(top, vf, 20, 0, 3);
    if (f3.origin.y != 707) {
        failures++; fprintf(stderr, "FAIL %s: below-flip wrong (y=%.0f)\n", __func__, f3.origin.y);
    }
    NSRect f4 = FCComputeOverlayFrame(top, vf, 20, 23, 3);
    if (f4.origin.y != 684) {
        failures++; fprintf(stderr, "FAIL %s: below-flip stack wrong (y=%.0f)\n", __func__, f4.origin.y);
    }

    // X clamping: clock hanging off the right and left screen edges.
    NSRect right = NSMakeRect(900, 400, 320, 60);
    if (FCComputeOverlayFrame(right, vf, 20, 0, 3).origin.x != 680) {
        failures++; fprintf(stderr, "FAIL %s: right clamp wrong\n", __func__);
    }
    NSRect left = NSMakeRect(-50, 400, 320, 60);
    if (FCComputeOverlayFrame(left, vf, 20, 0, 3).origin.x != 0) {
        failures++; fprintf(stderr, "FAIL %s: left clamp wrong\n", __func__);
    }
}

void test_overlay_frame_with_width(void) {
    // 2026-06-14: the audio bar grows wider than the clock to fit a full
    // device name. Lock the width-aware geometry: floor at clock width, center
    // on the clock, cap at screen width, x-clamp on-screen, and exact
    // equivalence with the legacy fn at desired == clock width.
    NSRect vf = NSMakeRect(0, 0, 1000, 800);
    NSRect clock = NSMakeRect(300, 400, 320, 60);   // midX 460

    // Desired < clock width → floored to clock width; centered == clock x.
    NSRect a = FCComputeOverlayFrameWithWidth(clock, vf, 20, 0, 3, 100);
    if (a.size.width != 320 || a.origin.x != 300) {
        failures++; fprintf(stderr, "FAIL %s: floor-at-clock-width (w=%.0f x=%.0f)\n",
                            __func__, a.size.width, a.origin.x);
    }

    // Desired > clock width → widens, centered on the clock's midX.
    NSRect b = FCComputeOverlayFrameWithWidth(clock, vf, 20, 0, 3, 500);
    if (b.size.width != 500 || b.origin.x != 210) {
        failures++; fprintf(stderr, "FAIL %s: widen+center (w=%.0f x=%.0f)\n",
                            __func__, b.size.width, b.origin.x);
    }

    // Desired > screen → capped at the visible width, clamped to the origin.
    NSRect c = FCComputeOverlayFrameWithWidth(clock, vf, 20, 0, 3, 5000);
    if (c.size.width != 1000 || c.origin.x != 0) {
        failures++; fprintf(stderr, "FAIL %s: screen-width cap (w=%.0f x=%.0f)\n",
                            __func__, c.size.width, c.origin.x);
    }

    // Wide bar over a narrow clock near the right edge → clamped on-screen.
    NSRect rclk = NSMakeRect(850, 400, 120, 60);    // midX 910
    NSRect d = FCComputeOverlayFrameWithWidth(rclk, vf, 20, 0, 3, 400);
    if (d.size.width != 400 || d.origin.x != 600) {
        failures++; fprintf(stderr, "FAIL %s: right-edge clamp (x=%.0f)\n",
                            __func__, d.origin.x);
    }

    // Equivalence: width-aware fn with desired == clock width == legacy fn.
    NSRect leg = FCComputeOverlayFrame(clock, vf, 20, 0, 3);
    NSRect eqv = FCComputeOverlayFrameWithWidth(clock, vf, 20, 0, 3, clock.size.width);
    if (!NSEqualRects(leg, eqv)) {
        failures++; fprintf(stderr, "FAIL %s: legacy-equivalence\n", __func__);
    }
}

void test_mute_readers_guard(void) {
    // 2026-06-14: output-mute detection (FCReadOutputMute) joins FCReadInputMute.
    // Real mute detection needs live hardware (verified by the on-device toggle
    // probe + on-screen check, not headless CI), so lock only what IS
    // deterministic here: both readers must return NO for an unknown device —
    // the nil-guard that keeps a 1Hz tick safe when no device is bound. This
    // also pins both symbols into the link so a signature/scope regression in
    // either reader fails the build.
    if (FCReadInputMute(kAudioObjectUnknown) != NO) {
        failures++; fprintf(stderr, "FAIL %s: input mute on unknown device should be NO\n", __func__);
    }
    if (FCReadOutputMute(kAudioObjectUnknown) != NO) {
        failures++; fprintf(stderr, "FAIL %s: output mute on unknown device should be NO\n", __func__);
    }
}

void test_solar_canvas_color_ramp(void) {
    // 2026-06-11: solar canvas — elevation→color ramp + elevation math.
    // Lock the qualitative invariants, not exact pixels: the ramp must be
    // warm at the horizon, blue in the day, violet at night (vivid), and
    // dark at night (atmospheric); all channels gamut-clamped.
    struct { double elev; } probes[] = {{-90},{-18},{-12},{-6},{-4},{0},{6},{20},{50},{90}};
    NSString *styles[] = { @"solar-vivid", @"solar-atmospheric" };
    for (int s = 0; s < 2; s++) {
        for (size_t i = 0; i < sizeof(probes)/sizeof(probes[0]); i++) {
            FCSolarCanvasColor c = FCSolarCanvasColorForElevation(probes[i].elev, styles[s]);
            if (c.r < 0 || c.r > 1 || c.g < 0 || c.g > 1 || c.b < 0 || c.b > 1) {
                failures++;
                fprintf(stderr, "FAIL %s: %s elev=%.0f out of gamut (%.3f,%.3f,%.3f)\n",
                        __func__, styles[s].UTF8String, probes[i].elev, c.r, c.g, c.b);
            }
        }
    }
    FCSolarCanvasColor horizonV = FCSolarCanvasColorForElevation(0, @"solar-vivid");
    if (!(horizonV.r > horizonV.b)) {
        failures++; fprintf(stderr, "FAIL %s: vivid horizon should be warm (r>b)\n", __func__);
    }
    FCSolarCanvasColor dayV = FCSolarCanvasColorForElevation(30, @"solar-vivid");
    if (!(dayV.b > dayV.r)) {
        failures++; fprintf(stderr, "FAIL %s: vivid day should be blue (b>r)\n", __func__);
    }
    FCSolarCanvasColor nightA = FCSolarCanvasColorForElevation(-30, @"solar-atmospheric");
    if (!(0.2126*nightA.r + 0.7152*nightA.g + 0.0722*nightA.b < 0.25)) {
        failures++; fprintf(stderr, "FAIL %s: atmospheric night should be dark\n", __func__);
    }
    FCSolarCanvasColor nightV = FCSolarCanvasColorForElevation(-30, @"solar-vivid");
    if (!(nightV.b > nightV.g && (nightV.r + nightV.b) > 0.3)) {
        failures++; fprintf(stderr, "FAIL %s: vivid night should be rich violet, not black\n", __func__);
    }
    // nil/unknown style → vivid.
    FCSolarCanvasColor d1 = FCSolarCanvasColorForElevation(10, nil);
    FCSolarCanvasColor d2 = FCSolarCanvasColorForElevation(10, @"solar-vivid");
    if (fabs(d1.r - d2.r) > 0.001 || fabs(d1.b - d2.b) > 0.001) {
        failures++; fprintf(stderr, "FAIL %s: nil style should dispatch to vivid\n", __func__);
    }
    // Elevation sanity: equator, equinox (2026-03-20), 12:00 UTC at (0,0)
    // → sun near zenith; 00:00 UTC → deep below horizon.
    NSDate *noonUTC = [NSDate dateWithTimeIntervalSince1970:1773748800]; // 2026-03-20 12:00:00Z (vernal equinox day)
    double eNoon = FCSolarElevationDegrees(noonUTC, 0.0, 0.0);
    if (eNoon < 70.0) {
        failures++; fprintf(stderr, "FAIL %s: equinox equator noon elevation %.1f < 70\n", __func__, eNoon);
    }
    NSDate *midnightUTC = [NSDate dateWithTimeIntervalSince1970:1773705600]; // 2026-03-20 00:00:00Z
    double eMid = FCSolarElevationDegrees(midnightUTC, 0.0, 0.0);
    if (eMid > -60.0) {
        failures++; fprintf(stderr, "FAIL %s: equinox equator midnight elevation %.1f > -60\n", __func__, eMid);
    }
}
