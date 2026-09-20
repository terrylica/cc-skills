// Attack-test harness for the brightness engine's SAFETY GUARDS.
//
// NOT part of `make test`, and deliberately NOT in tests/ — the Makefile
// globs tests/*.m wholesale, so a second main() there breaks the test link.
// It lives beside the audio diagnostics because that is what it is: a manual
// probe you run against real hardware, not an automated fixture.
//
// The unit suite covers the pure arithmetic; this drives the REAL
// FCXDRBrightness against a REAL display and tries to break it. It changes
// screen brightness visibly for about a minute and restores everything.
//
// Run from the plugin root, with FloatingClock QUIT — two processes writing
// the same gamma table will fight and the results are meaningless:
//
//   clang -fobjc-arc -framework Cocoa -framework Metal -framework QuartzCore \
//         -framework CoreGraphics -ISources -o /tmp/fcfail \
//         scripts/brightness-diagnostics/fc-brightness-failure-mode-harness.m \
//         Sources/core/FCXDRBrightness.m Sources/core/DisplayBrightnessHelpers.m
//   /tmp/fcfail
//
// Last run 2026-09-20 on Mac15,11 / macOS 15.8: 12 passed, 0 failed, 1 skipped
// (reference-preset refusal cannot be forced from code).
//
// WHY THIS EXISTS: five guards were added to the engine and none had been
// exercised against the condition it exists for. An untested safety guard is
// a guess wearing the costume of a protection — and this is display code on a
// machine that lost its display earlier the same day.
//
// The child-process mode (argv[1] == "--child-boost") engages a boost and
// then blocks forever, so the parent can SIGKILL it and verify that a hard
// kill really does revert the gamma table. That is the engine's PRIMARY
// safety property and the one everything else is allowed to lean on.

#import <Cocoa/Cocoa.h>
#import "core/FCXDRBrightness.h"
#import "core/DisplayBrightnessHelpers.h"
#import <signal.h>

static int gPass = 0, gFail = 0;

static void ok_(const char *name, const char *detail) {
    gPass++; printf("  \033[0;32mPASS\033[0m  %-46s %s\n", name, detail);
}
static void fail_(const char *name, const char *detail) {
    gFail++; printf("  \033[0;31mFAIL\033[0m  %-46s %s\n", name, detail);
}
static void skip_(const char *name, const char *why) {
    printf("  \033[0;33mSKIP\033[0m  %-46s %s\n", name, why);
}

// Top entry of the live gamma ramp. 1.0 == untouched.
static double RampTop(void) {
    CGGammaValue r[256], g[256], b[256];
    uint32_t n = 0;
    if (CGGetDisplayTransferByTable(CGMainDisplayID(), 256, r, g, b, &n) != kCGErrorSuccess || n == 0)
        return NAN;
    return (double)r[n - 1];
}

static NSScreen *Builtin(void) {
    for (NSScreen *s in [NSScreen screens]) {
        CGDirectDisplayID d = [[[s deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(d)) return s;
    }
    return [NSScreen mainScreen];
}
static double Headroom(void) {
    return Builtin().maximumExtendedDynamicRangeColorComponentValue;
}

// Pump the main runloop for `secs`. The EDR grant only arrives across runloop
// iterations — CoreAnimation commits its transaction at the END of one — so a
// blocking sleep here would make every boost silently no-op. This is itself a
// regression guard: if someone replaces this with sleep(), the tests go red.
static void Pump(NSTimeInterval secs) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:secs];
    while ([until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

// Drive the engine to an active boost. Returns NO if the panel cannot.
static BOOL EngageAndSettle(FCBrightnessEngine *e, NSInteger level) {
    [e setLevel:level];
    for (int i = 0; i < 60 && e.boostState != FCBrightnessBoostActive; i++) {
        Pump(0.25);
        [e poll];
    }
    return e.boostState == FCBrightnessBoostActive;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        FCBrightnessEngine *e = [FCBrightnessEngine shared];

        // ── child mode: boost, then block so the parent can SIGKILL us ──
        if (argc > 1 && strcmp(argv[1], "--child-boost") == 0) {
            if (!EngageAndSettle(e, 130)) { fprintf(stderr, "child: could not engage\n"); return 2; }
            printf("%.4f\n", RampTop()); fflush(stdout);
            for (;;) Pump(1.0);          // parent kills us here
        }

        printf("\n\033[1mBrightness engine — failure-mode attack tests\033[0m\n");
        printf("  built-in display : %s\n", [Builtin().localizedName UTF8String]);
        printf("  slider available : %s\n", e.sliderAvailable ? "yes" : "no");
        printf("  boost available  : %s%s\n", e.boostAvailable ? "yes" : "no",
               e.boostUnavailableReason ? [[NSString stringWithFormat:@" (%@)",
                                            e.boostUnavailableReason] UTF8String] : "");
        printf("  headroom now     : %.4f   potential %.4f   reference %.4f\n\n",
               Headroom(),
               Builtin().maximumPotentialExtendedDynamicRangeColorComponentValue,
               Builtin().maximumReferenceExtendedDynamicRangeColorComponentValue);

        NSInteger original = e.level;
        double baselineRamp = RampTop();

        // ─────────────────────────────────────────────────────────────────
        // 0. Precondition: we start from an untouched ramp.
        // ─────────────────────────────────────────────────────────────────
        if (fabs(baselineRamp - 1.0) < 0.02)
            ok_("precondition: ramp starts at identity", "");
        else
            fail_("precondition: ramp starts at identity",
                  [[NSString stringWithFormat:@"top=%.4f — something is already boosting", baselineRamp] UTF8String]);

        if (!e.boostAvailable) {
            skip_("all boost tests", "this display grants no EDR headroom");
            printf("\n  %d passed, %d failed\n\n", gPass, gFail);
            return gFail ? 1 : 0;
        }

        // ─────────────────────────────────────────────────────────────────
        // 1. Engage, then panicRestore. The kill switch must return the ramp
        //    to identity from an arbitrary boosted state.
        // ─────────────────────────────────────────────────────────────────
        if (EngageAndSettle(e, 130)) {
            double boosted = RampTop();
            if (boosted > 1.05)
                ok_("boost actually writes a >1.0 ramp",
                    [[NSString stringWithFormat:@"top=%.4f headroom=%.4f", boosted, Headroom()] UTF8String]);
            else
                fail_("boost actually writes a >1.0 ramp",
                      [[NSString stringWithFormat:@"top=%.4f — nothing was applied", boosted] UTF8String]);

            [e panicRestore:@"harness"];
            Pump(0.5);
            double after = RampTop();
            if (fabs(after - 1.0) < 0.02)
                ok_("panicRestore returns the ramp to identity",
                    [[NSString stringWithFormat:@"top=%.4f", after] UTF8String]);
            else
                fail_("panicRestore returns the ramp to identity",
                      [[NSString stringWithFormat:@"top=%.4f — STILL BOOSTED", after] UTF8String]);

            if (e.level <= 100)
                ok_("panicRestore drops the level out of boost range",
                    [[NSString stringWithFormat:@"level=%ld", (long)e.level] UTF8String]);
            else
                fail_("panicRestore drops the level out of boost range",
                      [[NSString stringWithFormat:@"level=%ld", (long)e.level] UTF8String]);
        } else {
            fail_("engage reaches Active state", "never settled — cannot run dependent tests");
        }

        // ─────────────────────────────────────────────────────────────────
        // 2. SIGKILL a boosted process. THE primary safety property: a crash
        //    must not be able to strand a blown-out panel.
        // ─────────────────────────────────────────────────────────────────
        {
            NSString *me = [[NSBundle mainBundle] executablePath] ?: @(argv[0]);
            NSTask *t = [[NSTask alloc] init];
            t.executableURL = [NSURL fileURLWithPath:me];
            t.arguments = @[ @"--child-boost" ];
            NSPipe *p = [NSPipe pipe];
            t.standardOutput = p;
            NSError *err = nil;
            if ([t launchAndReturnError:&err]) {
                // Wait for the child to report it is boosted.
                NSFileHandle *fh = p.fileHandleForReading;
                __block NSString *line = nil;
                double waited = 0;
                while (!line && waited < 25.0) {
                    NSData *d = [fh availableData];
                    if (d.length) line = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                    Pump(0.25); waited += 0.25;
                }
                if (line) {
                    double childRamp = RampTop();
                    if (childRamp > 1.05)
                        ok_("child process boosted the shared display",
                            [[NSString stringWithFormat:@"top=%.4f", childRamp] UTF8String]);
                    else
                        fail_("child process boosted the shared display",
                              [[NSString stringWithFormat:@"top=%.4f", childRamp] UTF8String]);

                    kill(t.processIdentifier, SIGKILL);
                    Pump(2.5);
                    double afterKill = RampTop();
                    if (fabs(afterKill - 1.0) < 0.02)
                        ok_("SIGKILL reverts the gamma ramp",
                            [[NSString stringWithFormat:@"top=%.4f — a crash cannot strand the panel", afterKill] UTF8String]);
                    else
                        fail_("SIGKILL reverts the gamma ramp",
                              [[NSString stringWithFormat:@"top=%.4f — PANEL LEFT BOOSTED", afterKill] UTF8String]);
                } else {
                    [t terminate];
                    skip_("SIGKILL reverts the gamma ramp", "child never reported a boost");
                }
            } else {
                skip_("SIGKILL reverts the gamma ramp",
                      [[NSString stringWithFormat:@"could not launch child: %@", err.localizedDescription] UTF8String]);
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // 3. Sleep/wake COMPOUNDING. Re-capturing an already-boosted ramp as
        //    the new baseline squares the factor on every wake — measured
        //    1.2952 -> 1.6776 in an earlier draft, unbounded. Post the real
        //    workspace notifications and confirm the factor does not grow.
        // ─────────────────────────────────────────────────────────────────
        if (EngageAndSettle(e, 130)) {
            double f0 = RampTop();
            NSNotificationCenter *wnc = [[NSWorkspace sharedWorkspace] notificationCenter];
            for (int cycle = 1; cycle <= 3; cycle++) {
                [wnc postNotificationName:NSWorkspaceWillSleepNotification object:nil];
                Pump(0.4);
                [wnc postNotificationName:NSWorkspaceDidWakeNotification object:nil];
                Pump(3.0);
                [e poll];
                for (int i = 0; i < 40 && e.boostState == FCBrightnessBoostEngaging; i++) { Pump(0.25); [e poll]; }
            }
            double f3 = RampTop();
            // f0 squared three times would be astronomically larger; even one
            // squaring is an obvious, visible blow-out.
            if (!isnan(f3) && f3 <= f0 + 0.05)
                ok_("3x sleep/wake does not compound the factor",
                    [[NSString stringWithFormat:@"before=%.4f after=%.4f", f0, f3] UTF8String]);
            else
                fail_("3x sleep/wake does not compound the factor",
                      [[NSString stringWithFormat:@"before=%.4f after=%.4f — COMPOUNDING", f0, f3] UTF8String]);

            if (f3 <= kFCAbsoluteFactorCap + 0.02)
                ok_("factor stays under the absolute cap after wake cycles",
                    [[NSString stringWithFormat:@"%.4f <= %.4f", f3, kFCAbsoluteFactorCap] UTF8String]);
            else
                fail_("factor stays under the absolute cap after wake cycles",
                      [[NSString stringWithFormat:@"%.4f > %.4f", f3, kFCAbsoluteFactorCap] UTF8String]);
        } else {
            skip_("3x sleep/wake does not compound the factor", "could not re-engage");
        }

        // ─────────────────────────────────────────────────────────────────
        // 4. Display reconfiguration while boosted. Posting the real screen-
        //    parameters notification must not leave a stale boost behind.
        // ─────────────────────────────────────────────────────────────────
        {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:NSApplicationDidChangeScreenParametersNotification object:nil];
            Pump(1.0);
            [e poll];
            double t = RampTop();
            if (!isnan(t) && t <= kFCAbsoluteFactorCap + 0.02)
                ok_("screen-reconfiguration leaves a sane ramp",
                    [[NSString stringWithFormat:@"top=%.4f", t] UTF8String]);
            else
                fail_("screen-reconfiguration leaves a sane ramp",
                      [[NSString stringWithFormat:@"top=%.4f", t] UTF8String]);
        }

        // ─────────────────────────────────────────────────────────────────
        // 5. Over-request must clamp, never clip.
        // ─────────────────────────────────────────────────────────────────
        {
            NSInteger got = [e setLevel:9999];
            if (got <= e.maximumLevel)
                ok_("absurd level request is clamped",
                    [[NSString stringWithFormat:@"asked 9999, got %ld (max %ld)", (long)got, (long)e.maximumLevel] UTF8String]);
            else
                fail_("absurd level request is clamped",
                      [[NSString stringWithFormat:@"got %ld > max %ld", (long)got, (long)e.maximumLevel] UTF8String]);
            for (int i = 0; i < 40 && e.boostState == FCBrightnessBoostEngaging; i++) { Pump(0.25); [e poll]; }
            double t = RampTop();
            if (!isnan(t) && t <= kFCAbsoluteFactorCap + 0.02)
                ok_("clamped request never exceeds the hardware cap",
                    [[NSString stringWithFormat:@"top=%.4f cap=%.4f", t, kFCAbsoluteFactorCap] UTF8String]);
            else
                fail_("clamped request never exceeds the hardware cap",
                      [[NSString stringWithFormat:@"top=%.4f cap=%.4f", t, kFCAbsoluteFactorCap] UTF8String]);
        }

        // ─────────────────────────────────────────────────────────────────
        // 6. Release, and confirm the ramp is clean afterwards.
        // ─────────────────────────────────────────────────────────────────
        [e releaseBoost];
        Pump(1.0);
        {
            double t = RampTop();
            if (fabs(t - 1.0) < 0.02)
                ok_("releaseBoost returns the ramp to identity",
                    [[NSString stringWithFormat:@"top=%.4f", t] UTF8String]);
            else
                fail_("releaseBoost returns the ramp to identity",
                      [[NSString stringWithFormat:@"top=%.4f", t] UTF8String]);
        }

        // ─────────────────────────────────────────────────────────────────
        // 7. Reference-preset refusal. Cannot be forced from code, so report
        //    honestly rather than claiming a pass we did not earn.
        // ─────────────────────────────────────────────────────────────────
        if (Builtin().maximumReferenceExtendedDynamicRangeColorComponentValue > 0.01)
            (e.boostAvailable ? fail_ : ok_)("refuses to boost in a reference preset",
                                             "display IS in a reference preset");
        else
            skip_("refuses to boost in a reference preset",
                  "not in one — set System Settings > Displays > Preset to test");

        // ── restore ──
        [e setLevel:original];
        Pump(0.5);
        [e releaseBoost];
        CGDisplayRestoreColorSyncSettings();
        Pump(0.5);
        printf("\n  restored: level=%ld  rampTop=%.4f\n", (long)e.level, RampTop());
        printf("\n  \033[1m%d passed, %d failed\033[0m\n\n", gPass, gFail);
        return gFail ? 1 : 0;
    }
}
