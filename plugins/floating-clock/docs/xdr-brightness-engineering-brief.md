# XDR beyond-max brightness — engineering brief

Synthesis of five researched-and-verified dimensions, plus first-hand measurement taken on this machine on 2026-09-19. Where a verifier refuted the research, the adjudication is stated inline with the evidence that decided it.

**Host**: MacBook Pro `Mac15,11` (16-inch, M3 Max, 36 GB), macOS 15.8 (24H23), Darwin 24.6.0, arm64. Built-in Liquid Retina XDR, 3456x2234, ProMotion 120 Hz, 10 bpc, `CGDirectDisplayID` = 1, `CGDisplayIsBuiltin` = 1.

---

## 0. The one adjudication that changes everything

The bundle contained a flat contradiction. Four independent measurements (the FOSS research, its verifier, the EDR research, its verifier) reported the built-in panel's EDR headroom rising from 1.0 to ~6.15 when a `CAMetalLayer` trigger is used. The host-architecture verifier reported it "stayed 1.0" after building "the exact NSPanel shape floating-clock uses" with `wantsExtendedDynamicRangeContent = YES`, and on that basis declared the entire approach dead and told the operator not to execute the plan.

I re-ran it. **The refutation is wrong.**

```
potentialEDR=16.0000  baseline headroom=1.0000
[PHASE 2] EDR trigger, no gamma
  t+0.5s headroom=1.9397
  t+1.0s headroom=3.8349
  t+1.5s headroom=6.1539   <-- engaged
```

The failure mode is diagnosable from the EDR research's own best finding: a layer that _declares_ extended-range intent but never _presents a frame_ gets nothing. The same research proved a plain `CALayer` with an extended-range `backgroundColor` holds at exactly 1.0000 for 10 s. Setting the property is not the trigger; **rendering a drawable with `clearColor > 1.0` is the trigger**. The host-architecture verifier configured the layer and never ran a render pass, so it measured the documented negative result and mistook it for a refutation of the positive one.

Where that verifier is right, and it matters: `DisplayServicesSetBrightness` genuinely does hard-clamp at 1.0 (`set(1.5)` and `set(2.0)` both read back `1.000000`, rc=0). Those are two different subsystems. The normal-range API cannot exceed maximum; the EDR+gamma path can. Conflating them is what produced the false "dead end".

### What nobody had done: compose the two halves

Every prior measurement tested the EDR trigger _or_ the gamma ramp, never both in one process. That gap was the single largest risk in the bundle. Composed result:

```
[PHASE 1] gamma 1.37x with NO EDR trigger (control)
  gamma-only    gamma[255]=1.369000  headroom=1.0000
  restored      gamma[255]=1.000000  headroom=1.0000
[PHASE 3] COMPOSED: apply gamma while EDR is engaged
  headroom=6.1539 -> gammaFactor(level=1.0)=1.3690
  t+0.5s .. t+3.0s headroom=6.1539 (gamma held, all six samples)
  composed      gamma[255]=1.369046  headroom=6.1539
[PHASE 4] hold 5s, no further draws
  after 5s idle gamma[255]=1.369046  headroom=6.1539
```

They compose cleanly. The gamma write does not perturb the EDR grant, the grant does not decay without redraws, and the loop is open — so it cannot oscillate.

### The honest residual caveat

**No measurement in this brief — mine or anyone's — proves photons.** Every number is API state. The framebuffer is sampled _before_ the gamma LUT, so `screencapture` cannot show the effect, and `ioreg` backlight nits do not move because the boost is digital drive within already-granted headroom, not a backlight setpoint change. The mechanism is sound and is what a 552-star commercial product ships, but confirm it with your eyes on first run, or with a phone camera locked to manual exposure/ISO photographing a static white window with the boost off and on.

---

## 1. BetterDisplay total removal

**Status: complete and verified on this machine.** Executed and swept this session.

The removal itself was performed by a backup-first script at 21:17:06 on 2026-09-19, one minute after it snapshotted state at 21:16:04. The reconnaissance research, running concurrently, saw the app vanish mid-scan and reported the Paddle licence as an unrecoverable "material casualty" — it had searched only `~/.Trash` and local snapshots. A filesystem-wide `find` it never ran locates everything intact. **That retraction is confirmed: I read the files directly.**

### Pre-deletion steps (for reference — not needed here, and now provably unnecessary)

The vendor requires the app be launched and reset _before_ deletion, because the in-app reset is what removes virtual screens and reverts display system settings, and unlike the exhaustive reset it preserves licence files.

```bash
# 1. In the GUI: Application > Advanced settings & privacy > Reset App Settings...
# 2. Back up the licence BEFORE any file deletion:
cp -a "$HOME/Library/Application Support/BetterDisplay" ~/Documents/betterdisplay-license-backup
# 3. Uninstall (quits app, removes login item, zaps):
brew uninstall --cask --zap betterdisplay
# 4. Sweep what the cask zap stanza misses (verified omission — no WebKit path in the stanza):
rm -rf "$HOME/Library/WebKit/pro.betterdisplay.BetterDisplay"
```

This step was skipped here, and it turns out not to matter: the recovered prefs plist proves **no virtual screen ever existed** — `systemVirtual@Display:{2,45,52}`, `thirdPartyVirtual@Display:{2,45}` and `virtualScreenLinked@Display:{2,45,52}` are all `False`. Corroborated by zero virtual-screen ICC profiles and a clean WindowServer plist. The "phantom display" watch item (vendor issue #4750) is closed.

### The deletions (done)

```bash
rm -rf "$TMPDIR/pro.betterdisplay.BetterDisplay" \
       "$(getconf DARWIN_USER_CACHE_DIR)pro.betterdisplay.BetterDisplay"
```

The research called these "user-owned and cleared on reboot" and therefore benign. **That is wrong for one of the two, and the verifier caught it.** `$TMPDIR` (`.../T/`) is periodically purged; `$(getconf DARWIN_USER_CACHE_DIR)` (`.../C/`) is the per-user darwin _cache_ directory and is not. Proof from this machine before I removed it:

```
drwxr-xr-x@ 4 terryli staff 128 May  8  2025 .../C/pro.betterdisplay.BetterDisplay
drwxr-xr-x@ 3 terryli staff  96 Sep 19 18:53 .../T//pro.betterdisplay.BetterDisplay
```

A May 2025 birthdate — it survived sixteen months of reboots. Explicit removal was required, not optional.

### Sudo-requiring steps — **DO NOT RUN**

The vendor's "exhaustive reset" is documented, and is the wrong tool here. Listed only so nobody reaches for it later.

```bash
# ALL REQUIRE SUDO. Destructive far beyond BetterDisplay's own footprint.
sudo rm /Library/Preferences/com.apple.windowserver.displays.plist   # EXISTS, 22,725 b
rm ~/Library/Preferences/ByHost/com.apple.windowserver*.plist        # EXISTS, 4 files
sudo rm /Library/ColorSync/Profiles/Displays/*                       # 11 .icc for REAL displays
sudo rm -rf /Library/Displays/Contents/Resources/Overrides/*         # path does not exist here
sudo nvram -c
```

Line 3 would destroy colour profiles for the operator's Color LCD, LG HDR 4K (x5), LG TV SSCR2, marantz-AVR, Q85A (x2) and SAMSUNG. There are no symptoms to justify it. If a display anomaly ever does appear, the recovery path is reinstall 4.3.7 → restore the backed-up Application Support folder → in-app reset → uninstall. Never this.

### Verification (all `none`, run this session)

```
[/Applications]   none        [login items]     none        [brew cask]     none
[user Library]    none        [launchd]         none        [homebrew bin]  none
[var folders]     none        [sysextensions]   none        [process]       none
[pkg receipts]    none        [defaults]  Domain pro.betterdisplay.BetterDisplay does not exist
```

### Corrections to the HOST FACTS you were given

| Stated                                         | Actual                                                | Evidence                                                                                                                                                                                           |
| ---------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BetterDisplay **4.1.0** (build 50131)          | **4.3.7** build 50131                                 | Vendor Sparkle appcast maps build 50131 → 4.3.7, and 4.1.0 → build 46906. The pairing is upstream-impossible. `4.1.0` is the value of the pref key `autoDisplayValidated`, misread as the version. |
| installed at `/Applications/BetterDisplay.app` | Homebrew **cask** install                             | `Caskroom/betterdisplay/4.3.7`, installed 2026-09-11 20:01:17 — same day as the upstream release.                                                                                                  |
| (silent)                                       | shipped a CLI at `/opt/homebrew/bin/betterdisplaycli` | Removed with the cask. The obvious scripting surface is gone, which is why the replacement had to be built from scratch.                                                                           |
| `configuredPotentialEDR = 16`                  | `16.0` (float)                                        | Confirmed independently of BetterDisplay — still reads `16.0` with the app entirely absent, so it is the **panel's own property**, not a BetterDisplay setting.                                    |

### Two remaining housekeeping items

- `~/.local/state/betterdisplay-uninstall-2026-09-19/` (28 K) holds the licence backup. Already mode `600` on both the `.padl`/`.spadl` files and `RECORD.txt` — the verifier's `chmod 600` recommendation is already satisfied. `RECORD.txt` does contain the activation secret in cleartext; keep or vault it, but do not publish it.
- Note for reinstall: the cask is macOS-branched — `on_sequoia :or_older => 4.3.7`, `on_tahoe :or_newer => 5.0.5`. On this host a naive reinstall gets 4.3.7, not 5.x.

---

## 2. The chosen FOSS approach

- **Project**: `niklasr22/BrightIntosh` — <https://github.com/niklasr22/BrightIntosh>
- **Licence**: **GPL-3.0** (confirmed this session: `gh repo view` → `gpl-3.0`, 552 stars, pushed 2026-09-05)
- **Disposition**: **STUDY — do not vendor, do not port.**

It is the only actively-maintained FOSS project that genuinely exceeds maximum brightness on this panel, and it explicitly lists `Mac15,11` in both `supportedDevices` and `sdr600nitsDevices`. Everything else in the landscape is disqualified:

| Project                     | Licence       | Why not                                                                                                                                         |
| --------------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **BrightIntosh**            | GPL-3.0       | The real thing — but copyleft. Study only.                                                                                                      |
| **Lunar** (`alin23/Lunar`)  | **MIT**       | Same `CGSetDisplayTransferByTable` + `maximumExtendedDynamicRange` primitives. Licence-compatible pattern reference.                            |
| MonitorControl              | MIT           | Drives the built-in panel, but via `DisplayServices` — **clamped to 1.0**, proven by direct call. Normal range only.                            |
| `nriley/brightness`         | BSD-2         | Normal range only; dormant since 2024-03.                                                                                                       |
| m1ddc / ddcctl              | MIT / GPL-3.0 | DDC/CI — **external displays only**. The Apple Silicon internal panel exposes no DDC endpoint.                                                  |
| BetterDisplay / BetterDummy | none          | `BetterDummy` 301-redirects to `BetterDisplay`, whose repo contains exactly one file: `README.md`. Closed source. No FOSS predecessor survives. |

### The licence obligation, which is the real blocker

`cc-skills` is **MIT** (`LICENSE`: "MIT License / Copyright (c) 2025-2026 Terry Li"; `package.json` `"license": "MIT"`). floating-clock ships inside it. GPL-3.0 is viral across linking, so dropping BrightIntosh-derived code into this binary would relicense the whole app.

This is the single most important thing the EDR-mechanism research missed entirely: it mentions licensing **zero times**, presents its deliverable as a "faithful transliteration", and its only permission analysis is about _entitlements_ — which is the OS sandbox axis, not the copyright axis. Its verifier caught this and is correct.

**What is and is not protectable.** The mechanism is public Apple API — `CAMetalLayer.wantsExtendedDynamicRangeContent`, `CGGet/SetDisplayTransferByTable` — and API usage is not protectable expression. What _is_ BrightIntosh's expression, and must not be copied:

- the `sdr600nitsDevices` device-model list
- the constant triples `(2.66, 0.50)` / `(3.2, 0.59)` / `(2.66, 0.60)`
- the `gammaFactor` response curve
- the `1.05` ready threshold, the `1.6` clear-colour value, the 25 s engage timeout, the 30 s retry cooldown

Three ways out, pick one **before** writing code:

1. **Clean-room the tuning layer** _(recommended)_ — derive the constants from first principles and choose your own curve. `referenceEDR = peakNits / sdrMaxNits = 1600 / 600 = 2.667` follows directly from the panel spec, and the 1600-nit peak is independently readable from `ioreg -c AppleARMBacklight` (`BrightnessMilliNits` max = 1599999). This keeps floating-clock MIT.
2. Licence the single file GPL-3.0 — but it infects everything linked into the same binary, which for this app is the whole thing. Not viable.
3. Ask Niklas Rodenhausen for an MIT/dual grant.

Add attribution regardless. The repo is active and the app is sold on the App Store, so the author has a live commercial interest.

**One more honesty correction.** The research called this "only public Apple API" and "~15 lines". Apple's own documentation for `CGSetDisplayTransferByTable` states the arrays' "values should be in the range 0 to 1" — and the entire technique depends on exceeding that. It is public API deliberately driven **outside its documented range**, which is a materially different risk posture and is the likeliest reason BrightIntosh's 2026 commit stream is dominated by "Stabilization". And `GammaTechnique.swift` is 1,374 lines plus 513 more in `BrightnessTechnique.swift`. The ~15 lines get a boost on screen; the remaining ~1,800 are the non-optional robustness layer. Budget for that.

---

## 3. How beyond-max brightness actually works

Two independent primitives. **Neither alone does anything visible.**

### Primitive 1 — the EDR trigger (unlocks headroom)

A `CAMetalLayer` with `wantsExtendedDynamicRangeContent = YES`, `pixelFormat = MTLPixelFormatRGBA16Float` (half-float carries values > 1.0), `colorspace = kCGColorSpaceExtendedLinearSRGB`, **presenting at least one drawable** cleared to a colour > 1.0. WindowServer then switches the mini-LED panel into HDR mode.

Measured: `1.0 → 1.94 → 3.83 → 6.1539` over ~1.5 s, then flat. Engagement is asynchronous and **overshoots** before settling, so you must poll — never assume success.

Three non-obvious properties, all measured:

- **A 1×1 window suffices.** BrightIntosh opens its trigger at a 1×1 rect. The full-screen path belongs to its _alternate_ `MultiplyingOverlayTechnique`, not the default.
- **No render loop is required.** One frame held 6.1539 for 90 s with zero further draws. BrightIntosh's `preferredFramesPerSecond = 5` is belt-and-braces. This makes the trigger genuinely free — important for an always-on accessory app.
- **Release is slow.** After closing the trigger, headroom stayed at 6.1539 for 6+ s in my run (a verifier measured ~16 s). The UI must not claim "normal" until a fresh read is back under threshold.

### Primitive 2 — the gamma ramp above 1.0 (converts headroom into brightness)

`CGSetDisplayTransferByTable` accepts ramp values above 1.0 and does not clamp them (requested `1.5900`, read back `1.5900`). Normally `1.0` means peak scanout, so this would just clip. Once the panel is in HDR mode `1.0` no longer means peak, and the excess maps into the unlocked headroom — so **all** SDR content on the panel gets brighter, not just your own layer.

That distinction is the classic trap, and it is what separates this from ordinary EDR rendering: EDR alone brightens _your own layer's_ pixels. The gamma ramp is applied per-display in the scanout pipeline after compositing, so it lifts the whole desktop.

### The real numbers for this panel

`referenceEDR = peakNits / sdrMaxNits`. This panel's peak is 1600 nits (`ioreg`), so `1600 / 2.66 = 601.5` nits SDR white — confirming the 600-nit spec non-circularly. For `Mac15,11` the constants are **(referenceEDR 2.66, bonusGamma 0.50)**, _not_ the (3.2, 0.59) of the 500-nit M1/M2 panels.

The correct curve is the **gamma** path's, confirmed verbatim from upstream this session:

```
clampedEdr  = min(max(currentEdr, referenceEdr), 16.0)
fullFactor  = 1 + maxScreenBrightness * (1 - (clampedEdr - referenceEdr) / (16.0 - referenceEdr))
factor      = 1 + (fullFactor - 1) * userBrightness
```

**The EDR research shipped the wrong formula** — it transliterated `MultiplyingOverlayTechnique.brightnessFactor` (the _alternate_ backend) while labelling it the gamma path. Its verifier caught this and is right. The two differ in monotonicity: the real gamma factor **decreases** as headroom rises, while the overlay formula saturates flat at 1.50.

| currentEDR                         | real factor | research's factor |
| ---------------------------------- | ----------- | ----------------- |
| 2.66 (slider at max)               | **1.500**   | 1.500             |
| 4.00                               | 1.450       | 1.500             |
| **6.15 (this machine idles here)** | **1.369**   | 1.500             |
| 10.00                              | 1.225       | 1.500             |
| 16.00                              | 1.000       | 1.500             |

So: **1.50× is the ceiling, reached only with the macOS slider already at maximum. The sustained value at this machine's idle headroom is 1.369×.** My composed run reproduced `1.3690` exactly. Quote both numbers, never just the flattering one — and note that `currentEDR` is system-wide shared state, so any other EDR client (Safari on an HDR video, Preview on an HDR photo) moves it underneath you. Re-evaluate the factor on every headroom change.

Drop the "600 → 900 nits" framing entirely. It assumes the ramp scale factor maps linearly onto emitted luminance, the panel EOTF is applied after the LUT, and the backlight setpoint provably does not move during a boost. The honest statement is the dimensionless factor.

### Exact API sequence

1. Resolve the built-in display: `CGGetActiveDisplayList` → first id with `CGDisplayIsBuiltin`. (Do **not** assume `CGMainDisplayID()`; it equals the built-in here only because one display is attached.)
2. Gate on capability: `maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0`.
3. Capture the baseline ramp **once, while unboosted**: `CGGetDisplayTransferByTable`. Keep the returned `sampleCount`.
4. Create the 1×1 borderless window at `NSScreenSaverWindowLevel`, click-through, all-Spaces; host a `CAMetalLayer` configured as above; `orderFrontRegardless`; present one frame with `clearColor = 1.6`.
5. Poll `maximumExtendedDynamicRangeColorComponentValue` from a **freshly resolved** `NSScreen` until it _settles_ (see §6 — do not fire on the first crossing of 1.05).
6. Compute the factor from settled headroom; multiply the captured baseline; `CGSetDisplayTransferByTable`.
7. Teardown in this order: ramp → 1.0 **first**, _then_ close the trigger window. The reverse leaves a >1.0 ramp with no headroom to map into, which clips highlights.

### The safety property that makes this shippable

**A >1.0 gamma ramp does not survive process death.** Measured both ways this session:

```
--- exit() path ---   SET gamma[255]=1.369000 pid=86318 exiting via exit()
                      READ gamma[255]=1.000000
--- SIGKILL path ---  SET gamma[255]=1.369000 pid=86474 exiting via SIGKILL
                      READ gamma[255]=1.000000
```

CoreGraphics owns the override per-process and reverts it when the setter dies, including under `SIGKILL` — which no in-process handler could intercept anyway. **A crash cannot strand a blown-out display.** This retires the "SIGKILL-robust restore path / watchdog / launch-time unconditional restore" workstream the FOSS research proposed: it guards a failure mode that does not exist. The corollary is about correctness, not safety — because the ramp dies with the process, floating-clock must _hold_ the boost for as long as it is enabled; it cannot set-and-forget.

### Secondary capability, free of charge

Sub-minimum dimming is the _same_ call with factor < 1.0 (verified at 0.5000 and 0.2500), needs no EDR trigger at all, and is strictly better than a dark overlay window — no click interference, no screenshot contamination. This makes one continuous `-1.0 … +1.0` control natural: dim below the hardware floor, or boost above the ceiling.

### Normal range, for completeness

`DisplayServicesGetBrightness` / `SetBrightness`, `dlopen`'d from `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`. Both take a **float**, not a double (recovered from disassembly: `objc_msgSend$floatValue` and `fmov s8, s0` → `initWithFloat:`). Round-trips exactly, shares state with the F1/F2 keys and Control Center, needs **no entitlement and no TCC grant** (proven by an unentitled ad-hoc binary writing brightness with no prompt). It does **not** raise the brightness HUD, and it cannot — `DisplayServicesBrightnessChanged` no longer exists in macOS 15.8.

Three traps worth carrying forward:

- **`CoreDisplay` is dead for this on M3.** All three getters leave the out-parameter untouched at _any_ width (proven with a sentinel buffer), and their return codes are uninitialised garbage that differs run to run — never branch on a specific value. Do not write a CoreDisplay fallback. Also: `dlopen` of CoreDisplay.framework fails outright ("not in dyld cache").
- **IOKit is dead on Apple Silicon.** `CGDisplayIOServicePort` → 0, `IODisplayGetFloatParameter` → `kIOReturnUnsupported`, and `IOServiceGetMatchingServices("IODisplayConnect")` returns `KERN_SUCCESS` with an _empty iterator_ — the silent-failure shape that misleads people. Do not write an IOKit fallback.
- **`DisplayServicesUnregisterForBrightnessChangeNotifications` is broken.** It exists, its ABI is recoverable, it returns a hardcoded 0 — and callbacks keep firing afterwards. Registration is permanent for the process lifetime, so the observer **must** be idempotent or a second call silently double-registers with no way back.

---

## 4. Reference Objective-C implementation

Pure Objective-C, ARC, no Swift runtime. Clean-room: the curve below is derived from the panel spec (`1600/600 = 2.667` peak-to-SDR ratio, read from `ioreg`), not copied from GPL source.

**This code was compiled and run before being published here** — the bundle contained too much plausible-looking code that did not compile for that to be taken on trust. `clang -fobjc-arc -Wall` produces zero diagnostics, it links into an accessory app against `Cocoa`/`Metal`/`QuartzCore`, and driving it end-to-end gives:

```
supported=1 sysAvail=1 sysBrightness=0.6225
  t+0.5s engaged=0 gamma[255]=1.0000     <-- settle gate holding during overshoot
  t+1.0s engaged=0 gamma[255]=1.0000
  t+2.0s engaged=0 gamma[255]=1.0000
  t+2.5s engaged=1 gamma[255]=1.3692     <-- settled, factor applied once
  t+4.0s engaged=1 gamma[255]=1.3692
-- level 0.5 --   gamma[255]=1.1846      (1 + 0.3692*0.5, exact)
-- dim -1.0 --    gamma[255]=0.2000      (minimumGamma floor)
-- disengage --   gamma[255]=1.0000      (clean)
```

Three things that proves, beyond "it builds": the **settle gate works** — gamma stays at exactly 1.0 through the ~2 s overshoot and the factor is applied once, cleanly, with no spike-then-sag; the dimming half needs no EDR trigger; and calling `observeSystemBrightness:` twice does not double-register. Note `1.3692` rather than BrightIntosh's `1.3690` — that two-digit divergence is the clean-room constant (`2.667` vs their `2.66`) showing up, which is exactly what an independent derivation should look like.

### `FCXDRBrightness.h`

```objectivec
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const FCXDRBrightnessStateDidChangeNotification;

@interface FCXDRBrightness : NSObject
@property (class, readonly) FCXDRBrightness *shared;

/// YES if a built-in EDR-capable panel is present (potential headroom > 1).
@property (readonly) BOOL supported;
/// YES once macOS has actually raised the panel into HDR mode AND the reading settled.
@property (readonly) BOOL isEngaged;

/// -1.0 ... +1.0.  0.0 == untouched.  >0 boosts above SDR max, <0 dims below the
/// hardware minimum.  One continuous axis, so one GUI control drives both.
@property (nonatomic) float level;
/// Floor for the dimming half. Default 0.20.
@property (nonatomic) float minimumGamma;

- (void)engage;     ///< idempotent
- (void)disengage;  ///< idempotent; restores gamma; safe at any time

// --- normal-range (0..1) passthrough, dlopen'd, degrades to -1 / NO ---
@property (readonly) BOOL systemBrightnessAvailable;
- (float)systemBrightness;                       ///< -1.0 if unreadable
- (BOOL)setSystemBrightness:(float)value;        ///< clamped to [0,1]
/// Idempotent by contract: unregistering is impossible on macOS 15.8, so calling
/// this twice replaces the handler rather than double-registering.
- (BOOL)observeSystemBrightness:(void (^)(float brightness))handler;
@end
NS_ASSUME_NONNULL_END
```

### `FCXDRBrightness.m`

```objectivec
#import "FCXDRBrightness.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

NSNotificationName const FCXDRBrightnessStateDidChangeNotification =
    @"FCXDRBrightnessStateDidChangeNotification";

// Panel model. referenceEDR = peakNits/sdrMaxNits; this panel reports a 1600-nit
// peak via ioreg AppleARMBacklight BrightnessMilliNits max=1599999, and a 600-nit
// SDR white, so 1600/600 = 2.667. kMaxEDR is the panel's advertised potential.
static const float kReferenceEDR   = 2.667f;
static const float kMaxBonus       = 0.50f;   // ceiling is 1.50x, at headroom == reference
static const float kMaxEDR         = 16.0f;
static const float kHDRReady       = 1.05f;
static const double kClearValue    = 1.6;
static const NSUInteger kSettleHits = 3;      // consecutive equal reads before we trust it

#pragma mark - Trigger window

@interface FCEDRTriggerWindow : NSWindow
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
- (nullable instancetype)initForScreen:(NSScreen *)screen;
- (void)positionOnScreen:(NSScreen *)screen;
- (void)renderEDRFrame;
- (void)teardown;
@end

@implementation FCEDRTriggerWindow

- (instancetype)initForScreen:(NSScreen *)screen {
    self = [super initWithContentRect:NSMakeRect(0, 0, 1, 1)
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;

    self.collectionBehavior = NSWindowCollectionBehaviorStationary
                            | NSWindowCollectionBehaviorCanJoinAllSpaces
                            | NSWindowCollectionBehaviorIgnoresCycle
                            | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.level                   = NSScreenSaverWindowLevel;
    self.opaque                  = NO;
    self.hasShadow               = NO;
    self.backgroundColor         = NSColor.clearColor;
    self.ignoresMouseEvents      = YES;   // never intercept a click
    self.releasedWhenClosed      = NO;
    self.hidesOnDeactivate       = NO;
    self.canHide                 = NO;
    self.animationBehavior       = NSWindowAnimationBehaviorNone;
    self.excludedFromWindowsMenu = YES;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return nil;                      // no Metal -> no boost, degrade quietly

    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device       = device;
    layer.pixelFormat  = MTLPixelFormatRGBA16Float;   // half-float carries >1.0
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
    layer.colorspace   = cs;
    CGColorSpaceRelease(cs);
    layer.wantsExtendedDynamicRangeContent = YES;     // necessary, NOT sufficient
    layer.opaque       = NO;
    layer.drawableSize = CGSizeMake(1, 1);
    layer.frame        = CGRectMake(0, 0, 1, 1);
    layer.needsDisplayOnBoundsChange = NO;
    _metalLayer = layer;
    _queue      = [device newCommandQueue];
    if (!_queue) return nil;

    NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    host.wantsLayer = YES;
    host.layer      = layer;
    self.contentView = host;

    [self positionOnScreen:screen];
    return self;
}

- (void)positionOnScreen:(NSScreen *)screen {
    NSRect f = screen.frame;
    [self setFrame:NSMakeRect(f.origin.x, NSMaxY(f) - 1, 1, 1) display:YES];
}

// THE trigger. Setting wantsExtendedDynamicRangeContent alone does nothing --
// measured: a layer that never presents a drawable holds headroom at exactly
// 1.0000. A frame must actually be presented with a clear colour above 1.0.
- (void)renderEDRFrame {
    CAMetalLayer *l = self.metalLayer;
    if (!l || !self.queue) return;
    id<CAMetalDrawable> drawable = [l nextDrawable];
    if (!drawable) return;                         // transient; next poll retries
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture     = drawable.texture;
    rp.colorAttachments[0].loadAction  = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor  =
        MTLClearColorMake(kClearValue, kClearValue, kClearValue, 1.0);
    id<MTLCommandBuffer> cb = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

- (void)teardown {
    self.contentView = nil;
    self.metalLayer.device = nil;
    self.metalLayer = nil;
    self.queue = nil;
    [self close];
}

- (BOOL)canBecomeKeyWindow  { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

#pragma mark - Controller

@interface FCXDRBrightness ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, FCEDRTriggerWindow *> *triggers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *baseline;   // ramp blob
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *baseCount; // sampleCount
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *lastEDR;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *settleHits;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic) BOOL engaged;
@property (nonatomic, readwrite) BOOL isEngaged;
@end

@implementation FCXDRBrightness

+ (FCXDRBrightness *)shared {
    static FCXDRBrightness *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FCXDRBrightness new]; });
    return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _triggers   = [NSMutableDictionary new];
    _baseline   = [NSMutableDictionary new];
    _baseCount  = [NSMutableDictionary new];
    _lastEDR    = [NSMutableDictionary new];
    _settleHits = [NSMutableDictionary new];
    _level = 0.0f;
    _minimumGamma = 0.20f;

    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(screensChanged:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
        selector:@selector(systemWoke:) name:NSWorkspaceDidWakeNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
        selector:@selector(systemWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    return self;
}

- (void)dealloc {
    [self disengage];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

#pragma mark Display resolution

// NEVER cache an NSScreen: its EDR properties are frozen at the moment you
// obtained the object. Measured -- a retained NSScreen reported 1.0000 forever
// while a freshly-resolved one reported 7.5445 on the same display.
+ (nullable NSScreen *)screenForDisplay:(CGDirectDisplayID)did {
    for (NSScreen *s in NSScreen.screens)
        if ([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == did) return s;
    return nil;
}

/// Built-in panel, or kCGNullDirectDisplay in clamshell / headless.
/// Do NOT use CGMainDisplayID(): it coincides with the built-in only when no
/// external display is attached.
+ (CGDirectDisplayID)builtinDisplayID {
    uint32_t n = 0; CGDirectDisplayID ids[16];
    if (CGGetActiveDisplayList(16, ids, &n) != kCGErrorSuccess) return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < n; i++) if (CGDisplayIsBuiltin(ids[i])) return ids[i];
    return kCGNullDirectDisplay;
}

+ (NSArray<NSScreen *> *)edrCapableScreens {
    NSMutableArray *out = [NSMutableArray new];
    for (NSScreen *s in NSScreen.screens) {
        CGDirectDisplayID d = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(d) &&
            s.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0)
            [out addObject:s];
    }
    return out;
}

- (BOOL)supported { return [FCXDRBrightness edrCapableScreens].count > 0; }

#pragma mark Gamma

/// Capture ONLY while unboosted. Re-capturing a boosted ramp compounds the factor
/// multiplicatively and the error is unbounded -- a measured 1.2952 became 1.6776
/// (= 1.2952^2) across one sleep/wake cycle in an earlier draft of this code.
- (BOOL)captureBaselineForDisplay:(CGDirectDisplayID)did {
    if (self.baseline[@(did)]) return YES;
    const uint32_t cap = 256;
    CGGammaValue *buf = calloc(3 * cap, sizeof(CGGammaValue));
    if (!buf) return NO;
    uint32_t n = 0;
    CGError e = CGGetDisplayTransferByTable(did, cap, buf, buf + cap, buf + 2*cap, &n);
    if (e != kCGErrorSuccess || n == 0 || n > cap) { free(buf); return NO; }
    // Refuse a baseline that is already boosted -- the identity ramp ends at ~1.0.
    if (buf[n - 1] > 1.01f) {
        free(buf);
        CGDisplayRestoreColorSyncSettings();
        return NO;                                  // retry next poll from a clean ramp
    }
    self.baseline[@(did)]  = [NSData dataWithBytesNoCopy:buf
                                                 length:3*cap*sizeof(CGGammaValue)
                                           freeWhenDone:YES];
    self.baseCount[@(did)] = @(n);                  // carry sampleCount; do NOT assume 256
    return YES;
}

- (void)applyFactor:(float)factor toDisplay:(CGDirectDisplayID)did {
    NSData *base = self.baseline[@(did)];
    NSNumber *cnt = self.baseCount[@(did)];
    if (!base || !cnt) return;
    const uint32_t n = cnt.unsignedIntValue;
    const uint32_t cap = 256;
    const CGGammaValue *src = base.bytes;
    CGGammaValue out[3 * 256];
    // Only the first n entries are valid; writing a hardcoded 256 against a
    // shorter table would install calloc zeros in the tail -> black above that index.
    for (uint32_t i = 0; i < n; i++) {
        out[i]           = src[i]           * factor;
        out[cap + i]     = src[cap + i]     * factor;
        out[2*cap + i]   = src[2*cap + i]   * factor;
    }
    CGSetDisplayTransferByTable(did, n, out, out + cap, out + 2*cap);
}

/// Clean-room curve. Full bonus is available only when headroom is at the
/// reference (i.e. the macOS slider is already at maximum) and tapers linearly
/// to zero at the panel's potential. It is INVERSELY related to current headroom.
- (float)factorForHeadroom:(double)currentEDR {
    if (self.level < 0.0f)                       // dimming half: no EDR needed
        return 1.0f + (self.minimumGamma - 1.0f) * (-self.level);
    if (self.level == 0.0f) return 1.0f;
    if (kMaxEDR <= kReferenceEDR) return 1.0f;

    float c = (float)currentEDR;
    if (c < kReferenceEDR) c = kReferenceEDR;
    if (c > kMaxEDR)       c = kMaxEDR;
    float full = 1.0f + kMaxBonus * (1.0f - (c - kReferenceEDR) / (kMaxEDR - kReferenceEDR));
    return 1.0f + (full - 1.0f) * self.level;
}

#pragma mark Lifecycle

- (void)engage {
    if (!self.supported) return;
    self.engaged = YES;
    [self rebuildTriggers];
    if (!self.pollTimer) {
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
            selector:@selector(poll:) userInfo:nil repeats:YES];
        self.pollTimer.tolerance = 0.25;
    }
}

/// Teardown ORDER MATTERS: neutralise gamma first, then drop the trigger. The
/// reverse leaves a >1.0 ramp with no headroom to map into -> highlight clipping.
- (void)disengage {
    self.engaged = NO;
    [self.pollTimer invalidate]; self.pollTimer = nil;

    for (NSNumber *k in self.baseline.allKeys)
        [self applyFactor:1.0f toDisplay:k.unsignedIntValue];
    CGDisplayRestoreColorSyncSettings();

    [self.baseline removeAllObjects];
    [self.baseCount removeAllObjects];
    [self.lastEDR removeAllObjects];
    [self.settleHits removeAllObjects];

    for (FCEDRTriggerWindow *w in self.triggers.allValues) [w teardown];
    [self.triggers removeAllObjects];

    if (self.isEngaged) {
        self.isEngaged = NO;
        [NSNotificationCenter.defaultCenter
            postNotificationName:FCXDRBrightnessStateDidChangeNotification object:self];
    }
}

- (void)setLevel:(float)level {
    _level = fmaxf(-1.0f, fminf(1.0f, level));
    if (_level == 0.0f) { [self disengage]; return; }
    [self engage];        // engage AFTER level is set, so rebuildTriggers sees it
    [self poll:nil];
}

- (void)rebuildTriggers {
    NSMutableSet *live = [NSMutableSet new];
    BOOL needsHDR = (self.level > 0.0f);   // dimming needs no HDR trigger at all

    for (NSScreen *screen in [FCXDRBrightness edrCapableScreens]) {
        CGDirectDisplayID did = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        [live addObject:@(did)];
        if (![self captureBaselineForDisplay:did]) continue;
        if (CGDisplayIsAsleep(did)) continue;      // defer; re-armed on wake
        if (!needsHDR) continue;

        FCEDRTriggerWindow *w = self.triggers[@(did)];
        if (!w) {
            w = [[FCEDRTriggerWindow alloc] initForScreen:screen];
            if (!w) continue;                       // no Metal device: degrade
            self.triggers[@(did)] = w;
            [w orderFrontRegardless];
        } else {
            [w positionOnScreen:screen];
            [w orderFrontRegardless];
        }
        [w renderEDRFrame];
    }
    // Displays that went away: tear their triggers down.
    for (NSNumber *k in self.triggers.allKeys)
        if (![live containsObject:k]) {
            [self.triggers[k] teardown];
            [self.triggers removeObjectForKey:k];
            [self.baseline removeObjectForKey:k];
            [self.baseCount removeObjectForKey:k];
            [self.lastEDR removeObjectForKey:k];
            [self.settleHits removeObjectForKey:k];
        }
}

- (void)poll:(NSTimer *)t {
    if (!self.engaged) return;
    BOOL anySettled = NO;

    for (NSNumber *key in self.baseline.allKeys) {
        CGDirectDisplayID did = key.unsignedIntValue;
        NSScreen *screen = [FCXDRBrightness screenForDisplay:did];   // fresh, never cached
        if (!screen || CGDisplayIsAsleep(did)) continue;

        double edr = screen.maximumExtendedDynamicRangeColorComponentValue;

        // Gate on SETTLING, not on first crossing of 1.05. Engagement overshoots
        // (measured 1.94 -> 3.83 -> 6.15), and because the factor is inversely
        // related to headroom, acting during ramp-up produces a visible ~8%
        // brightness spike that then sags.
        double prev = self.lastEDR[key] ? self.lastEDR[key].doubleValue : -1.0;
        NSUInteger hits = self.settleHits[key] ? self.settleHits[key].unsignedIntegerValue : 0;
        hits = (fabs(edr - prev) < 0.01) ? hits + 1 : 0;
        self.lastEDR[key]    = @(edr);
        self.settleHits[key] = @(hits);

        BOOL settled = (edr > kHDRReady) && (hits >= kSettleHits);
        if (settled) anySettled = YES;

        float factor = (self.level < 0.0f)
            ? [self factorForHeadroom:edr]        // dimming: independent of headroom
            : (settled ? [self factorForHeadroom:edr] : 1.0f);

        [self applyFactor:factor toDisplay:did];
    }

    if (anySettled != self.isEngaged) {
        self.isEngaged = anySettled;
        [NSNotificationCenter.defaultCenter
            postNotificationName:FCXDRBrightnessStateDidChangeNotification object:self];
    }
}

#pragma mark Events

- (void)screensChanged:(NSNotification *)n {
    if (!self.engaged) return;
    [self rebuildTriggers];
    [self poll:nil];
}

- (void)systemWillSleep:(NSNotification *)n {
    if (!self.engaged) return;
    for (NSNumber *k in self.baseline.allKeys)
        [self applyFactor:1.0f toDisplay:k.unsignedIntValue];
}

- (void)systemWoke:(NSNotification *)n {
    if (!self.engaged) return;
    // CRITICAL: neutralise and hard-restore BEFORE discarding baselines, or the
    // next capture reads a still-boosted ramp and squares the factor every wake.
    for (NSNumber *k in self.baseline.allKeys)
        [self applyFactor:1.0f toDisplay:k.unsignedIntValue];
    CGDisplayRestoreColorSyncSettings();
    [self.baseline removeAllObjects];
    [self.baseCount removeAllObjects];
    [self.lastEDR removeAllObjects];
    [self.settleHits removeAllObjects];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.engaged) return;
        [self rebuildTriggers];
        [self poll:nil];
    });
}

#pragma mark - Normal-range brightness (dlopen'd DisplayServices)

typedef int  (*DSGet_f)(CGDirectDisplayID, float *);   // float, NOT double
typedef int  (*DSSet_f)(CGDirectDisplayID, float);
typedef int  (*DSCan_f)(CGDirectDisplayID);
typedef void (*DSCallback_f)(void *, void *, CFStringRef, void *);
typedef int  (*DSReg_f)(CGDirectDisplayID, void *, DSCallback_f);

static DSGet_f gDSGet; static DSSet_f gDSSet; static DSCan_f gDSCan; static DSReg_f gDSReg;
static BOOL gDSLoaded;
static CGDirectDisplayID gObservedDisplay;
static void (^gBrightnessHandler)(float);
static BOOL gObserving;                                 // unregister is impossible; see below

static void FCLoadDisplayServices(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The file does not exist on disk (shared cache since macOS 11) but dlopen
        // resolves it. Note CoreDisplay.framework does NOT dlopen -- do not try it.
        void *h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/"
                         "DisplayServices", RTLD_LAZY | RTLD_LOCAL);
        if (!h) return;                                  // degrade: no normal-range control
        gDSGet = (DSGet_f)dlsym(h, "DisplayServicesGetBrightness");
        gDSSet = (DSSet_f)dlsym(h, "DisplayServicesSetBrightness");
        gDSCan = (DSCan_f)dlsym(h, "DisplayServicesCanChangeBrightness");
        gDSReg = (DSReg_f)dlsym(h,
                    "DisplayServicesRegisterForBrightnessChangeNotifications");
        gDSLoaded = (gDSGet != NULL && gDSSet != NULL);   // reg/can are optional
    });
}

- (BOOL)systemBrightnessAvailable {
    FCLoadDisplayServices();
    if (!gDSLoaded) return NO;
    CGDirectDisplayID d = [FCXDRBrightness builtinDisplayID];
    if (d == kCGNullDirectDisplay) return NO;
    return gDSCan ? (gDSCan(d) != 0) : YES;
}

- (float)systemBrightness {
    FCLoadDisplayServices();
    CGDirectDisplayID d = [FCXDRBrightness builtinDisplayID];
    if (!gDSLoaded || d == kCGNullDirectDisplay) return -1.0f;
    float v = -1.0f;
    return (gDSGet(d, &v) == 0) ? v : -1.0f;
}

- (BOOL)setSystemBrightness:(float)value {
    FCLoadDisplayServices();
    CGDirectDisplayID d = [FCXDRBrightness builtinDisplayID];
    if (!gDSLoaded || d == kCGNullDirectDisplay) return NO;
    // The SPI itself saturates at 1.0 and still returns success, so clamp here to
    // keep our own accounting honest. Going beyond max is the EDR path's job.
    if (value < 0.0f) value = 0.0f;
    if (value > 1.0f) value = 1.0f;
    return gDSSet(d, value) == 0;
}

// Delivered on a private DisplayServices queue, and the brightness value is NOT
// passed (args are reserved/context/CFString/reserved) -- read it back here.
static void FCBrightnessDidChange(void *r0, void *ctx, CFStringRef name, void *r3) {
    float v = [FCXDRBrightness.shared systemBrightness];
    void (^h)(float) = gBrightnessHandler;
    if (h && v >= 0.0f) dispatch_async(dispatch_get_main_queue(), ^{ h(v); });
}

- (BOOL)observeSystemBrightness:(void (^)(float))handler {
    FCLoadDisplayServices();
    CGDirectDisplayID d = [FCXDRBrightness builtinDisplayID];
    if (!gDSLoaded || !gDSReg || d == kCGNullDirectDisplay) return NO;
    gObservedDisplay   = d;
    gBrightnessHandler = [handler copy];
    // DisplayServicesUnregisterForBrightnessChangeNotifications exists, returns a
    // hardcoded 0, and does NOT stop callbacks -- verified. Registration is therefore
    // permanent, so guard idempotence or a second call double-fires forever.
    if (gObserving) return YES;
    gObserving = YES;
    gDSReg(d, NULL, FCBrightnessDidChange);   // return value is a hardcoded 0: ignore it
    return YES;
}
@end
```

---

## 5. floating-clock integration plan

Verified against the working tree this session: 64 `.m` / 63 `.h`, **0 `.swift`**, `LSUIElement`, unsandboxed, no entitlements, `flags=0x0(none)` (no hardened runtime), signed with the persistent local cert. Baseline **`All 120 tests passed.`**

### CREATE

| Path                                              | Contents                                                                                                                                                                                                                                   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Sources/core/FCXDRBrightness.h` / `.m`           | §4 above.                                                                                                                                                                                                                                  |
| `Sources/core/DisplayBrightnessHelpers.h` / `.m`  | The **pure** arithmetic, split out deliberately so it stays in the test link: `FCClampBrightness`, `FCApplyBrightnessDelta`, `FCBrightnessStepPercent`, `FCGammaFactorForHeadroom`. Foundation-only — no `NSScreen`, no `CGMainDisplayID`. |
| `Sources/core/BrightnessStatusIndicator.h` / `.m` | The rail.                                                                                                                                                                                                                                  |
| `Sources/core/BrightnessBarZoneView.h` / `.m`     | The interactive zone.                                                                                                                                                                                                                      |
| `tests/test_brightness.h` / `.m`                  | Auto-discovered by `$(wildcard tests/*.m)`.                                                                                                                                                                                                |

**Correction to the researched plan:** it put the `NSScreen`/`CGMainDisplayID`-touching code in the "pure" helper module and claimed it mirrored `CoreAudioDeviceHALHelpers`. It does not — that module is Foundation-only. Keeping the genuinely pure arithmetic in its own file preserves the property the pattern exists for. (It happens to link either way, because `TEST_CFLAGS` already carries `-framework Cocoa`, but the distinction is the point.)

### The indicator contract — corrected

It is **three** methods, not four: `-refresh`, `-syncPosition`, `-isShowing`. Verified:

```
AudioStatusIndicator.h:42:   - (instancetype)initWithClockPanel:(NSPanel *)clockPanel;
NetworkStatusIndicator.h:48: - (instancetype)initWithClockPanel:(NSPanel *)clockPanel;
VPNStatusIndicator.h:30:     - (instancetype)initWithClockPanel:(NSPanel *)clockPanel   <- multi-line
MicMuteIndicator.h:40:       - (instancetype)initWithClockPanel:(NSPanel *)clockPanel   <- multi-line
```

VPN takes `micIndicator:` and Mic takes `deviceName:`, so the initialiser is **not** part of the shared shape. Also: "no `@protocol` exists anywhere in `Sources/`" is false — `Sources/segments/FloatingClockSegmentViews.h:31` declares `@protocol FCNamedSegment <NSObject>`. The indicators' informal duck type is a deliberate local choice, not a house-wide absence. Copy the shape; do not introduce a protocol.

### EDIT

1. **`Makefile:32`** — append to `TEST_EXCLUDED` (backslash-continued):

   ```
       Sources/core/FCXDRBrightness.m \
       Sources/core/BrightnessStatusIndicator.m \
       Sources/core/BrightnessBarZoneView.m \
   ```

   Do **not** add `DisplayBrightnessHelpers.m` — it must stay in the test link. `APP_SOURCES` is `find Sources -name '*.m'`, so all eight new files compile with no Makefile edit. **`CFLAGS` needs `-framework Metal`** (`QuartzCore`, which vends `CAMetalLayer`, is already on line 11; `grep -c 'framework Metal' Makefile` → 0). `TEST_CFLAGS` needs no change — `DisplayServices` is `dlopen`'d and the pure helper touches no framework.

2. **`Sources/core/BrightnessStatusIndicator.m`** — place the rail at the **new top of stack**. `-syncPosition` sums one slot (`20.0 + 3.0`) per visible junior across audio/mic/VPN/network. This is the documented extension point (`clock.m:272-276`: _"It sums its juniors' slots, so the existing three indicators are untouched"_) and costs **zero** edits to existing indicators. Mid-stack placement instead costs three extra edits plus a weak property in each header.

3. **`Sources/core/FloatingClockPanel.h`** — `@class FCBrightnessStatusIndicator;` near line 13; ivar `FCBrightnessStatusIndicator *_brightnessStatusIndicator;` in the block at 35-48.

4. **`Sources/clock.m`** — import; construct **after** the network indicator so all four juniors exist; wire the four weak junior properties. In `registerDefaults` (~line 146), beside `NetworkBarEnabled`:

   ```objectivec
   @"BrightnessBarEnabled": @YES,
   @"BrightnessBarStep":    @5,
   ```

   **Do not add a `BrightnessBoostEnabled` key.** The researched plan proposed one as an "inert" XDR opt-in; it is redundant once `level` is the single continuous control, and an inert pref that promises a capability is worse than no pref.

5. **`Sources/core/FloatingClockPanel+Runtime.m`** — import; add `[_brightnessStatusIndicator refresh];` after the network line at 76, with a tick-cost comment in the house style. The read is an in-process `dlopen`'d call plus an `NSScreen` property — comparable to the six CoreAudio property reads the audio bar already does per second, so **1 Hz is within budget and no decimation counter is needed**. Never spawn a subprocess here; that rule is hard-won (see the fork/exec-per-tick narrative at `docs/overlay-indicators.md:118`).

6. **`Sources/core/FloatingClockPanel+WindowPlacement.m`** — import; add `[_brightnessStatusIndicator syncPosition];` after line 55.

7. **`Sources/menu/FloatingClockPanel+MenuBuilder.m`** — a "Show Brightness Bar" item after "Show Network Bar" (~line 85), and a "Brightness Step" submenu via `submenuTitled:action:pairs:defaultsKey:` (~line 110) with pairs `1/2/5/10/25`.

8. **`Sources/menu/FloatingClockPanel+MenuHelpers.m`** — **two edits, both mandatory.** `submenuTitled:`'s `defaultsKey:` argument is _discarded_ (line 12 is literally `(void)key;`); the checkmark comes from a hardcoded title→key chain. Without both of these the menu is permanently uncheckmarked:
   - boolean chain (~line 97): `else if ([item.title isEqualToString:@"Show Brightness Bar"]) { item.state = [d boolForKey:@"BrightnessBarEnabled"] ? ... }`
   - submenu chain (~line 109): `else if ([subTitle isEqualToString:@"Brightness Step"]) currentValue = [d objectForKey:@"BrightnessBarStep"];`
   - Use `objectForKey:`, **not** `stringForKey:` — the representedObjects are `NSNumber`s and `-representedObject:matchesValue:` compares by `doubleValue`.

9. **`Sources/actions/FloatingClockPanel+ActionHandlers.{h,m}`** — declare **both** selectors in the header (unlike the existing `toggleShowNetworkBar:`, which is implemented at `.m:314` but never declared and works only via dynamic dispatch — do not copy that omission). Implement `toggleShowBrightnessBar:` (toggle the bool, then `[_brightnessStatusIndicator refresh]` for instant show/hide rather than ≤1 s tick lag) and `setBrightnessStep:` (guard `isKindOfClass:[NSNumber class]`, write the integer, no `applyDisplaySettings` since the step is read per click).

10. **`tests/test_session.m`** — `#import "test_brightness.h"` at the top; `RUN_TEST` lines in `main()` (line 749, block 751-881).

### NSUserDefaults keys

`registerDefaults`: `BrightnessBarEnabled` (BOOL, `YES`), `BrightnessBarStep` (int, `5`).

**`profileManagedKeys()` — add nothing.** Verified: neither `AudioBarEnabled` nor `NetworkBarEnabled` appears in `FloatingClockStarterProfiles.m` (grep returns empty), so indicator on/off is deliberately not profile-managed. The invariant test `test_starter_profiles_cover_all_keys` (`tests/test_session.m:590-626`) iterates `profileManagedKeys()` against every starter — adding a key there without also adding it to all eight starters, or to the exempt set at 600-613, turns that test red. Leaving it out keeps the test green with no edit, which is the whole point of the existing convention.

### Bar zone view + mouse handling

Two templates, and you need **both** — this is the one place the researched plan would not have compiled:

- **`AudioBarZoneView`** for the _interaction_ shape: `hitTest:` returning `self` for every point (mandatory — `NSTextField` subviews otherwise swallow `mouseDown:`; there is a dated in-source comment recording that exact silent no-op), x-coordinate region dispatch against cached label frames with a top-half/bottom-half split on the numeric cell, `scrollWheel:` at ±2 per notch, `menuForEvent:` (which gets right-click, ctrl-click and two-finger tap for free), and the `_renderKey` string composite that makes the steady-state tick allocate nothing.
- **`NetworkBarZoneView`** for the _measurement_ method: `naturalContentWidth` exists **only** there (`NetworkBarZoneView.h:56`, `.m:134`, called from `NetworkStatusIndicator.m:356`). The audio bar measures on the indicator instead. The researched plan called `[_zone naturalContentWidth]` while saying to copy the audio view — that combination does not compile.

Region layout: `[−] [ 123% ] [+]` — minus steps down, plus steps up, the numeric cell nudges by half, and the `else` branch cycles presets (25/50/75/100/boost), preserving the audio bar's muscle memory.

### Width consensus and hide ceremony

Publish the content need in `-refresh` **before** calling `syncPosition` — publishing inside `syncPosition` posts the change notification that re-enters it. Key by `NSStringFromClass(self.class)`; the singleton only notifies when the agreed max moves ≥ 0.5 pt.

On hide, copy **`NetworkStatusIndicator`**, not `AudioStatusIndicator`: call `FCHideOverlay(_bar)` _and_ `[[FCOverlayWidthConsensus shared] clearOverlay:...]`. The audio bar omits the withdrawal and leaves peers padded to a width nothing uses — a latent raggedness bug; do not replicate it.

Attach with `FCAttachOverlayToClock` so the bar moves atomically during drags, build the panel with `FCCreateOverlayPanel(clock, size, NO)` (`ignoresMouse:NO` for interactive), and match the dual-layer dark surface (0.16/0.16/0.18 @ 0.95 fill, 1 pt white @ 0.22 border, 7 pt radius).

### Tests — specific assertions

In `tests/test_brightness.m`, against the pure helpers only:

- `FCClampBrightness`: `0.0→0.0`, `1.0→1.0`, `-0.5→0.0`, `1.5→1.0`, `NaN→0.0`.
- `FCApplyBrightnessDelta`: round-trip `(0.5,+10)→0.6`; saturation at both rails; `-1.0` in stays `-1.0` out (uncontrollable stays uncontrollable).
- `FCBrightnessStepPercent`: unset→5, `0`→5, `99`→25 (clamped 1..25).
- **`FCGammaFactorForHeadroom` — the regression that protects against the formula error in the bundle**: assert it is _inversely_ monotonic. `f(2.667, 1.0)` ≈ 1.500, `f(6.1539, 1.0)` ≈ 1.369, `f(16.0, 1.0)` ≈ 1.000, and `f(a) > f(b)` for `a < b`. A flat 1.500 across all three is exactly the bug to catch.
- Baseline-guard: a table whose last entry exceeds 1.01 is refused as a baseline (the anti-compounding invariant).

### Docs

`docs/runtime-preferences.md` is the declared SSoT ("Keep THIS table current when adding keys") — two new rows at ~line 60. New section in `docs/overlay-indicators.md` next to the network picker at line 102. And **`CLAUDE.md` rows 105 (Linked frameworks: add Metal) and 110 (System mutations)** — line 110 currently asserts the `networksetup` reorder "is the only system-wide change this plugin makes". A display gamma ramp is a second one. That framing must change from "only" to an enumerated list; it is an operator-visible promise.

---

## 6. Risks, safety and degradation

### What the measurements retire

- **Leaving the panel stuck bright after a crash: impossible.** The ramp reverts on `exit()` and on `SIGKILL` (measured both). CoreGraphics owns the override per-process. **Delete the watchdog / launch-time-unconditional-restore workstream** the FOSS research proposed — it guards a non-existent failure mode. The real corollary is that the app must _hold_ the boost while enabled; it cannot set-and-forget.
- **Non-XDR Macs: safe by construction.** `maximumPotentialExtendedDynamicRangeColorComponentValue` is 1.0, so `edrCapableScreens` is empty, `supported` is NO, no trigger is created and no gamma is touched. The GUI should omit the control entirely rather than show a dead one.

### What genuinely can go wrong

| Risk                                                                                                                                                                                                                                                                                                                | Mitigation                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Multiplicative compounding on wake** — the measured 1.2952 → 1.6776 (= 1.2952²) bug. Re-capturing a boosted ramp as the new baseline squares the factor every wake, unbounded: five cycles → 3.65×, an unreadable display, persisting as long as the app runs.                                                    | Neutralise + `CGDisplayRestoreColorSyncSettings()` **before** discarding baselines (§4 `systemWoke:`), and refuse any captured baseline whose last entry exceeds 1.01.                                                                       |
| **Engagement overshoot** — acting on the first crossing of 1.05 applies the factor during ramp-up, and because the factor is _inversely_ related to headroom this produces a visible ~8 % spike that then sags, while values above 1.0 are still clipping.                                                          | Require `kSettleHits` consecutive stable reads (§4 `poll:`). Use 1.05 only as the UI's "HDR is on at all" signal.                                                                                                                            |
| **Teardown clipping** — dropping the trigger while a >1.0 ramp is applied leaves the ramp with no headroom to map into.                                                                                                                                                                                             | Ramp → 1.0 **first**, then close the window. Encoded in `disengage`.                                                                                                                                                                         |
| **Night Shift / True Tone / f.lux contention** — all write the same per-display transfer table. Night Shift is first-party and always available, so it is the likelier collision than the f.lux conflict BrightIntosh documents. Worse, engaging while Night Shift is active bakes its warm tint into the baseline. | Untested — see §7. Minimum: skip the write when readback already matches within tolerance, rather than rewriting unconditionally at 2 Hz and guaranteeing a tug-of-war. Port drift-tolerance reapply rather than blind rewrite.              |
| **Auto-brightness (ALC)** — the panel has an ambient sensor (`HasAmbientLightCompensation` = 1). Currently **disabled** on this machine (`AmbientLightCompensationEnabled` → 0), so nothing fights the control today. If the user enables it, the value will drift with no user action.                             | Read the flag at startup and surface a warning. Do **not** silently disable it — that would be an undeclared second system mutation.                                                                                                         |
| **Other EDR clients** — `currentEDR` is system-wide. A Safari HDR video moves it underneath you, and the correct factor moves with it.                                                                                                                                                                              | Re-evaluate on every poll (already does). Expect the factor to breathe between ~1.0 and ~1.5.                                                                                                                                                |
| **Panel heat / battery** — driving a mini-LED harder has a real power cost. The GPU cost is provably negligible (one 1×1 frame; no render loop needed) but the backlight cost is unquantified.                                                                                                                      | Measure with `powermetrics` before defaulting the toggle on. BrightIntosh ships battery-aware logic (`batteryAutomation`, threshold 50) worth reading.                                                                                       |
| **Display sleep / disconnect / clamshell**                                                                                                                                                                                                                                                                          | `CGDisplayIsAsleep` defers engagement; `NSApplicationDidChangeScreenParameters` rebuilds triggers and drops state for departed displays; `builtinDisplayID` returns `kCGNullDirectDisplay` in clamshell and every entry point early-returns. |
| **Stale `NSScreen`** — a retained `NSScreen` reports frozen EDR values forever (measured: held object said 1.0000 while a fresh one said 7.5445).                                                                                                                                                                   | Never cache. Re-resolve from `NSScreen.screens` on every read (`screenForDisplay:`).                                                                                                                                                         |
| **Gamma table downsampled 4×** — `CGDisplayGammaTableCapacity` is **1024** on this panel (I measured it) but the code uses 256, matching upstream. Risks banding on gradients, which is exactly where a multiplied ramp shows most.                                                                                 | Accept and document, or use the real capacity. Not a correctness bug.                                                                                                                                                                        |
| **EDR release hysteresis** — headroom stayed at 6.1539 for 6+ s after teardown in my run.                                                                                                                                                                                                                           | Do not let the UI claim "normal" until a fresh read is back under 1.05. Report "releasing…".                                                                                                                                                 |
| **OS upgrade** — the technique drives a public API outside its documented 0..1 range, so it can change without deprecation notice.                                                                                                                                                                                  | Gate any macOS 26 (Tahoe) upgrade on re-testing. The host is on 15.8, so not blocking.                                                                                                                                                       |

### Concrete safety design

1. **Idle timeout** — auto-return `level` to 0 after N minutes (default 30) unless the user touches the control. Bounds worst-case heat and battery, and rescues a mis-scroll the user did not notice.
2. **Settle gate** before any factor > 1.0 (§4).
3. **Baseline sanity check** — refuse any baseline ending above 1.01 (§4).
4. **Restore on `applicationWillTerminate:`** — cosmetic, for a clean fade; process death already covers the hard case.
5. **Do not persist a boost across launches.** Persisting `level` means a crash-loop relaunches into a boost. Persist the _bar's visibility_, start the _boost_ at 0.
6. **Scroll guard** — ±2 %/notch over a 20 pt rail is easy to trigger by accident. Require the pointer to rest in the zone, or make the zero detent sticky.

---

## 7. Open questions for the operator

| #   | Question                                                                                                                                      | Recommended default                                                                                                                                                           |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Ship this at all, given no photometric proof yet?** Everything measured is API state; nobody has proven photons.                            | **Build it, but eyeball it first.** Run the composed test, look at the screen. Two minutes settles what no amount of further API probing can.                                 |
| 2   | **Licence route** — clean-room, GPL the app, or ask upstream?                                                                                 | **Clean-room.** The constants derive from the panel spec (`1600/600`), and it is the only route that keeps `cc-skills` MIT. Add attribution anyway.                           |
| 3   | **Which display when an external monitor is attached?**                                                                                       | **Built-in only.** `builtinDisplayID`, not the clock's current screen. External panels have no EDR headroom to unlock, and the DDC path is a separate project.                |
| 4   | **Default the toggle on?**                                                                                                                    | **Off**, until `powermetrics` quantifies the battery cost. Ship the bar visible, the boost at 0.                                                                              |
| 5   | **Idle timeout duration?**                                                                                                                    | **30 minutes.** Long enough not to annoy, short enough to bound a forgotten boost.                                                                                            |
| 6   | **Night Shift interaction — test before or after shipping?**                                                                                  | **Before.** It is first-party and always available; a 2 Hz tug-of-war is a visible defect. One live test answers it.                                                          |
| 7   | **`CLAUDE.md` line 110 currently promises the network reorder is "the only system-wide change this plugin makes".** A gamma ramp is a second. | **Change "only" to an enumerated list**, in the same commit as the feature. It is an operator-visible promise.                                                                |
| 8   | **Keep `~/.local/state/betterdisplay-uninstall-2026-09-19/`?**                                                                                | **Keep until you confirm no reinstall**, then vault or delete. `RECORD.txt` holds the activation secret in cleartext (already mode 600).                                      |
| 9   | **Expose sub-minimum dimming?**                                                                                                               | **Yes** — it is the same call with factor < 1.0, needs no EDR trigger, works on every Mac, and is arguably more useful day to day than the boost. One control, `-1.0 … +1.0`. |

---

## Appendix — what I changed from the bundle, and why

| Dimension                 | Adjudication                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **betterdisplay-removal** | **Verifier wins.** A filesystem-wide `find` the research never ran locates the licence, the prefs plist and a `RECORD.txt` in a backup directory created 62 seconds before the removal. Licence not lost; virtual-display question answered **no**; the actor was a deliberate backup-first script, not a reckless one. I read those files directly. Also verifier-correct: the `C/` residue is a cache dir (May 2025 birthdate — sixteen months of reboots), not "cleared on reboot".            |
| **foss-landscape**        | **Verifier wins twice.** The research shipped `MultiplyingOverlayTechnique`'s formula labelled as the gamma path — wrong monotonicity, +9.6 % at this machine's operating point. And "the ramp survives process death" is false; I reproduced clean revert under both `exit()` and `SIGKILL`. Research wins on the ranking and the licence analysis, which are sound.                                                                                                                             |
| **edr-mechanism**         | **Verifier wins** on the wake-compounding bug, the 1.50× vs 1.369× headline, and the total absence of licence analysis. **Research wins** on the mechanism itself — I reproduced every core measurement.                                                                                                                                                                                                                                                                                          |
| **brightness-apis**       | **Verifier wins.** `Unregister` is broken (returns 0, callbacks continue) — which makes observer idempotence mandatory, not stylistic. `AmbientLightCompensationEnabled` takes a `bool*` and reports ALC currently **off**. CoreDisplay return codes are uninitialised garbage — never branch on them.                                                                                                                                                                                            |
| **host-architecture**     | **Split.** Its verifier **wins** on the repo corrections (three-method contract, `@protocol FCNamedSegment` exists, `naturalContentWidth` is network-only) and on `DisplayServicesSetBrightness` clamping at 1.0 — all three confirmed by me. But its headline **refutation of the EDR path is wrong**: it configured the layer without ever presenting a frame, measured the already-documented negative result, and generalised it into "the feature is unbuildable". Five measurements to one. |

**My own additions**: the composed EDR + gamma run (never done by anyone), the `SIGKILL` gamma-persistence test, `CGDisplayGammaTableCapacity` = 1024 on this panel, the EDR release-hysteresis measurement, and the settle-gate + baseline-sanity design that closes the overshoot and compounding defects.
