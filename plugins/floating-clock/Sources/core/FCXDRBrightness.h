// Display brightness engine — one continuous 0..140 % rail over TWO different
// mechanisms, with the hand-off at 100 % invisible to the caller.
//
//   0..100 %  macOS brightness slider, via the private DisplayServices SPI.
//             Exactly the value F1/F2 and Control Center move; shared system
//             state, so setting it here moves the slider everywhere.
//   >100 %    Extended Dynamic Range headroom plus a gamma ramp scaled above
//             1.0. This is the part macOS ships no GUI for.
//
// ─────────────────────────── CLEAN-ROOM NOTICE ───────────────────────────
// Independent implementation. Uses only public, documented Apple API for the
// boost (CAMetalLayer.wantsExtendedDynamicRangeContent, Metal, CGGet/
// SetDisplayTransferByTable, NSScreen's EDR properties) plus the private
// DisplayServices SPI for the ordinary slider, reached by dlopen/dlsym so a
// missing symbol degrades instead of breaking the build.
//
// It contains NO code, constants, per-model device table or response curve
// taken from niklasr22/BrightIntosh (GPL-3.0) or any other copyleft project;
// this repository is MIT and vendoring GPL source would relicense it. The
// mechanism is unprotectable public API — the expression here is our own, and
// our response curve (DisplayBrightnessHelpers.h) reads the panel at runtime
// instead of consulting a per-model table at all.
//
// CORRECTION, 2026-09-20. An earlier draft of this notice claimed that
// BrightIntosh's hardcoded referenceEDR of 2.66 for Mac15,11 "does not match
// this machine, which reports 2.0513 at slider maximum". That was wrong, and
// wrong in a self-flattering direction. The 2.0513 reading was taken ~1.2 s
// after changing the slider, i.e. DURING the EDR ramp — the same
// sample-before-settled mistake this file's own settle gate exists to
// prevent. Measured properly with the grant settled, this panel reports
// 2.6667 at slider maximum, which is exactly 1600/600 and exactly their
// constant. Their number was right.
//
// Runtime derivation is still the correct design here — it needs no device
// table, and it adapts to hardware that does not exist yet — but it is not
// more ACCURATE than theirs, and the record should not pretend otherwise.
// Credit to that project for demonstrating the technique is viable.
//
// ──────────────────── HOW THE BOOST WORKS (both halves) ───────────────────
//  1. EDR TRIGGER. A 1x1 borderless window hosting a CAMetalLayer with
//     wantsExtendedDynamicRangeContent = YES, MTLPixelFormatRGBA16Float and
//     the extendedLinearSRGB colour space, which RENDERS frames whose clear
//     colour exceeds 1.0. WindowServer responds by granting the panel EDR
//     headroom — measured ramping 1.0 -> 6.15 over roughly two seconds.
//
//     Configuring the layer is NOT enough. A layer that never presents a
//     frame leaves headroom pinned at exactly 1.0000 forever; this was
//     measured, and it is the trap that makes the feature look impossible.
//
//  2. GAMMA PUSH. CGSetDisplayTransferByTable accepts ramp entries above 1.0
//     and does not clamp them (requested 1.4500, read back 1.4500). Normally
//     1.0 is peak scanout so that would clip; with the panel in HDR mode 1.0
//     is no longer peak, so the excess maps into the unlocked headroom and
//     EVERY pixel on the desktop brightens. That is why a 1x1 trigger is
//     enough — the trigger unlocks, the gamma ramp spends.
//
// ───────────────────────── CONSTRAINTS THAT BIT ───────────────────────────
//  * The main runloop MUST turn over between configuring the layer and the
//    grant arriving; CoreAnimation commits at the end of a runloop iteration.
//    Engagement is therefore ASYNCHRONOUS and there is deliberately no
//    blocking "engage and wait" entry point — a nested -runUntilDate: spin
//    makes the trigger silently no-op (measured).
//  * NEVER re-capture a baseline ramp while a factor is applied. That squares
//    the factor on every capture (measured 1.2952 -> 1.6776 across one
//    sleep/wake) and blows the display out without bound. -captureBaseline
//    refuses any ramp failing FCGammaBaselineIsNeutral.
//  * Apply the factor only once headroom has SETTLED. The factor is larger at
//    lower headroom, so acting on the first crossing overshoots ~8 % and then
//    sags visibly.
//  * Releasing is not instant: headroom decays over roughly 15 s after the
//    trigger goes away. Callers must not claim "off" until -state says so.
//  * Never retain an NSScreen. A held instance reports frozen EDR values
//    forever; re-resolve from +[NSScreen screens] on every read.
//
// ─────────────────────────────── SAFETY ───────────────────────────────────
// A gamma override is owned by CoreGraphics per-process and reverts
// automatically when that process dies — verified under both exit() and
// SIGKILL. A crash therefore cannot strand a blown-out display, which is a
// stronger guarantee than any restore-on-quit handler could give. The
// corollary is that the app must HOLD the boost while it is on; there is no
// set-and-forget.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FCBrightnessBoostState) {
    FCBrightnessBoostOff = 0,   ///< no trigger, no gamma override
    FCBrightnessBoostEngaging,  ///< trigger up, headroom still ramping
    FCBrightnessBoostActive,    ///< headroom settled, factor applied
    FCBrightnessBoostReleasing, ///< gamma restored, headroom still decaying
};

@interface FCBrightnessEngine : NSObject

+ (instancetype)shared;

#pragma mark Capability

/// YES when the ordinary 0..100 % range can be driven on the built-in display.
/// NO on a machine where the DisplayServices SPI is missing or refuses.
@property(nonatomic, readonly) BOOL sliderAvailable;

/// YES when the built-in panel reports more POTENTIAL EDR headroom than it
/// grants at rest AND is not in a calibrated reference preset. NO on any
/// non-XDR Mac, which is what makes the rail collapse to 0..100 there.
@property(nonatomic, readonly) BOOL boostAvailable;

/// Why boostAvailable is NO, phrased for a menu item. nil when it is YES.
/// A greyed-out control that cannot say why it is greyed out is a bug report
/// waiting to happen.
@property(nonatomic, readonly, nullable) NSString *boostUnavailableReason;

/// Rail ceiling in percent: 140 when a boost is possible, else 100.
@property(nonatomic, readonly) NSInteger maximumLevel;

#pragma mark State

/// Current rail level in percent. Below 100 this tracks the hardware slider,
/// so pressing F1/F2 moves it. At or above 100 it is whatever was last
/// requested.
@property(nonatomic, readonly) NSInteger level;

/// The factor actually being applied right now (1.0 == none). Below the
/// requested level/100 when live headroom cannot support the request — the
/// UI uses the difference to show that it is clamped rather than hiding it.
@property(nonatomic, readonly) double appliedFactor;

@property(nonatomic, readonly) FCBrightnessBoostState boostState;

/// Live EDR headroom granted to the built-in panel (1.0 == none).
@property(nonatomic, readonly) double headroom;

/// YES when macOS auto-brightness is on, in which case the ambient sensor may
/// walk the slider back with no user action. Read-only on purpose: silently
/// disabling a system-wide display setting would be an undeclared mutation.
@property(nonatomic, readonly) BOOL ambientCompensationEnabled;

/// Fired on the main thread whenever level, factor or state changes.
@property(nonatomic, copy, nullable) void (^changeHandler)(void);

#pragma mark Actions

/// Set the rail. Clamped to 0...maximumLevel. At or below 100 this writes the
/// slider and releases any boost; above 100 it pins the slider to maximum and
/// engages the boost asynchronously. Returns the clamped level.
- (NSInteger)setLevel:(NSInteger)level;

/// Re-read hardware state. Call from the 1 Hz tick. Cheap: one dlsym'd SPI
/// call plus one NSScreen property read — comparable to the CoreAudio reads
/// the audio bar already does several times a second, so no decimation is
/// needed. Never spawns a subprocess.
- (void)poll;

/// Restore gamma and tear the trigger down now. Safe to call repeatedly and
/// from -applicationWillTerminate:.
- (void)releaseBoost;

/// Force the display back to its ColorSync ramp and discard all internal
/// state, unconditionally. This is the kill switch: it is what every internal
/// invariant failure calls, and it is safe to call at any time from any state.
/// `why` is a short diagnostic string, not shown to the user.
///
/// The engine calls this itself on: a failed gamma write, a ramp readback that
/// disagrees with what was written, and EDR headroom being withdrawn while a
/// boost is applied. The rule is that "I am unsure what state the gamma table
/// is in" always resolves to "put it back", never to "carry on".
- (void)panicRestore:(NSString *)why;

@end

NS_ASSUME_NONNULL_END
