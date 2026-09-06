// Tests for the shared overlay width agreement and the network telemetry math.
// See test_overlay_width.h for rationale.
#import "test_overlay_width.h"
#import "../Sources/core/OverlayWidthConsensus.h"
#import "../Sources/core/NetworkTelemetry.h"

static void expectClose(const char *fn, NSString *what, double got, double want) {
    if (fabs(got - want) < 0.001) return;
    fprintf(stderr, "FAIL %s: %s expected %.4f got %.4f\n", fn, what.UTF8String, want, got);
    failures++;
}

static void expectStr(const char *fn, NSString *what, NSString *got, NSString *want) {
    if ([got isEqualToString:want]) return;
    fprintf(stderr, "FAIL %s: %s expected '%s' got '%s'\n", fn, what.UTF8String,
            want.UTF8String, got.UTF8String);
    failures++;
}

#pragma mark - Width consensus

void test_overlay_width_takes_widest_need(void) {
    FCOverlayWidthConsensus *c = [FCOverlayWidthConsensus shared];
    [c reset];
    [c setNeed:200.0 forOverlay:@"a"];
    [c setNeed:340.0 forOverlay:@"b"];
    [c setNeed:120.0 forOverlay:@"c"];
    // The whole point: every rail gets the WIDEST need, not its own.
    expectClose(__func__, @"widest wins", [c widthForClockWidth:0.0], 340.0);
}

void test_overlay_width_floors_at_clock_width(void) {
    FCOverlayWidthConsensus *c = [FCOverlayWidthConsensus shared];
    [c reset];
    [c setNeed:120.0 forOverlay:@"a"];
    // A bar narrower than the clock would break the visual tie to it.
    expectClose(__func__, @"floored", [c widthForClockWidth:500.0], 500.0);
    expectClose(__func__, @"not floored", [c widthForClockWidth:100.0], 120.0);
}

void test_overlay_width_hidden_overlay_stops_widening(void) {
    FCOverlayWidthConsensus *c = [FCOverlayWidthConsensus shared];
    [c reset];
    [c setNeed:200.0 forOverlay:@"a"];
    [c setNeed:900.0 forOverlay:@"wide"];
    expectClose(__func__, @"wide present", [c widthForClockWidth:0.0], 900.0);
    // When a bar hides it must withdraw its claim, or the rest stay padded out
    // to a width nothing is using any more.
    [c clearOverlay:@"wide"];
    expectClose(__func__, @"wide withdrawn", [c widthForClockWidth:0.0], 200.0);
    // A non-positive need means the same thing as clearing.
    [c setNeed:0.0 forOverlay:@"a"];
    expectClose(__func__, @"zero need clears", [c widthForClockWidth:0.0], 0.0);
}

void test_overlay_width_posts_change_notification(void) {
    FCOverlayWidthConsensus *c = [FCOverlayWidthConsensus shared];
    [c reset];
    __block NSInteger posts = 0;
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:FCOverlayWidthConsensusDidChangeNotification
                    object:nil queue:nil
                usingBlock:^(NSNotification *n) { (void)n; posts++; }];

    [c setNeed:200.0 forOverlay:@"a"];      // 0 -> 200, changes
    [c setNeed:100.0 forOverlay:@"b"];      // max still 200, no change
    [c setNeed:300.0 forOverlay:@"b"];      // 200 -> 300, changes
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    // Exactly the transitions that move the agreed width — no more. Posting on
    // every registration would relayout every overlay on every tick.
    if (posts != 2) {
        fprintf(stderr, "FAIL %s: expected 2 change posts, got %ld\n", __func__, (long)posts);
        failures++;
    }
    [c reset];
}

#pragma mark - Throughput arithmetic

void test_telemetry_rate_basic(void) {
    expectClose(__func__, @"1000 B over 1 s", FCComputeByteRate(2000, 1000, 1.0), 1000.0);
    expectClose(__func__, @"1000 B over 2 s", FCComputeByteRate(2000, 1000, 2.0), 500.0);
    expectClose(__func__, @"no movement",     FCComputeByteRate(1000, 1000, 1.0), 0.0);
}

void test_telemetry_rate_survives_counter_reset(void) {
    // Re-plugging an interface resets its counters. Differencing across that
    // would report the entire previous total as one second of traffic — a huge
    // bogus spike at exactly the moment the user is watching the link recover.
    expectClose(__func__, @"counter went backwards", FCComputeByteRate(50, 9000000, 1.0), 0.0);
    // A non-positive interval is not a rate at all.
    expectClose(__func__, @"zero interval",     FCComputeByteRate(2000, 1000, 0.0), 0.0);
    expectClose(__func__, @"negative interval", FCComputeByteRate(2000, 1000, -3.0), 0.0);
}

void test_telemetry_rate_formatting(void) {
    expectStr(__func__, @"idle",      FCFormatByteRate(0.0),        @"0");
    expectStr(__func__, @"sub-K",     FCFormatByteRate(940.0),      @"940");
    expectStr(__func__, @"K decimal", FCFormatByteRate(1200.0),     @"1.2K");
    expectStr(__func__, @"K whole",   FCFormatByteRate(45000.0),    @"45K");
    expectStr(__func__, @"M decimal", FCFormatByteRate(1200000.0),  @"1.2M");
    expectStr(__func__, @"G",         FCFormatByteRate(2.5e9),      @"2.5G");
    // Garbage in must not render as garbage out on a status rail.
    expectStr(__func__, @"negative",  FCFormatByteRate(-5.0),       @"0");
    expectStr(__func__, @"infinite",  FCFormatByteRate(INFINITY),   @"0");
    expectStr(__func__, @"nan",       FCFormatByteRate(NAN),        @"0");
}

void test_telemetry_signal_buckets(void) {
    // Boundaries are the interesting part: these decide the bar's colour.
    if (FCSignalQualityBucket(-45) != 2) { fprintf(stderr, "FAIL %s: -45 should be good\n", __func__); failures++; }
    if (FCSignalQualityBucket(-60) != 2) { fprintf(stderr, "FAIL %s: -60 is the good edge\n", __func__); failures++; }
    if (FCSignalQualityBucket(-61) != 1) { fprintf(stderr, "FAIL %s: -61 should be fair\n", __func__); failures++; }
    if (FCSignalQualityBucket(-72) != 1) { fprintf(stderr, "FAIL %s: -72 is the fair edge\n", __func__); failures++; }
    if (FCSignalQualityBucket(-73) != 0) { fprintf(stderr, "FAIL %s: -73 should be poor\n", __func__); failures++; }
}

// The anti-jitter guarantee: because the telemetry group is right-aligned, a
// numeric field that changes width drags its left-hand neighbours sideways.
// Padding every field to a constant character count is what pins them.
void test_telemetry_padding_stabilises_field_width(void) {
    expectStr(__func__, @"pad short", FCPadLeft(@"0", 4),    @"   0");
    expectStr(__func__, @"pad 3",     FCPadLeft(@"37K", 4),  @" 37K");
    expectStr(__func__, @"exact",     FCPadLeft(@"108K", 4), @"108K");
    // Never truncate: a real value is worth more than perfect alignment.
    expectStr(__func__, @"overlong",  FCPadLeft(@"12345", 4), @"12345");
    expectStr(__func__, @"nil",       FCPadLeft(nil, 3),      @"   ");

    // The actual invariant the bar depends on: every value this formatter can
    // produce pads to the SAME length, so the field never changes pixel width.
    double samples[] = { 0.0, 940.0, 1200.0, 45000.0, 1200000.0, 2.5e9, 9.9e11 };
    NSUInteger want = FCByteRateFieldWidth;
    for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
        NSString *p = FCPadLeft(FCFormatByteRate(samples[i]), FCByteRateFieldWidth);
        if (p.length != want) {
            fprintf(stderr, "FAIL %s: rate %.1f padded to %lu chars, expected %lu ('%s')\n",
                    __func__, samples[i], (unsigned long)p.length, (unsigned long)want,
                    p.UTF8String);
            failures++;
        }
    }
}
