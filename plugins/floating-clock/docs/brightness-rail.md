# Brightness rail — 0–140% over the built-in display

Spoke for the overlay rail added 2026-09-19. The hub keeps one line; the detail lives here. Mechanism research is in [xdr-brightness-engineering-brief.md](./xdr-brightness-engineering-brief.md); the incident that shaped how it was developed is in [2026-09-19-display-blackout-forensics.md](./2026-09-19-display-blackout-forensics.md).

## What it is

One continuous control spanning two unrelated mechanisms, with the hand-over at 100% invisible to the user.

| Range  | Mechanism                                                                                 | Notes                                                                                                                                                         |
| ------ | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0–100% | macOS brightness value via the private `DisplayServices` SPI, reached by `dlopen`/`dlsym` | The same value F1/F2 and Control Center read. Setting it here moves the slider everywhere. A missing symbol degrades the rail rather than breaking the build. |
| >100%  | EDR headroom + a gamma ramp scaled above 1.0                                              | The part macOS ships no GUI for. Slider pins to maximum; the extra comes from gamma.                                                                          |

Interaction mirrors the audio bar so the two rails feel identical: drag or click the track, `−`/`+` step by `BrightnessBarStep`, the number's top half nudges up and bottom half down, scroll is ±2/notch, right-click opens presets. A tick on the track marks 100%, so "you are now beyond the normal maximum" is legible without reading the number.

## Why both halves are required

1. **EDR trigger.** A 1×1 borderless window hosting a `CAMetalLayer` with `wantsExtendedDynamicRangeContent`, `MTLPixelFormatRGBA16Float` and `extendedLinearSRGB`, which **renders** frames whose clear colour exceeds 1.0. Measured on Mac15,11: headroom ramps 1.0 → 6.15 over roughly two seconds.

   Configuring the layer is **not** enough. A layer that never presents a frame leaves headroom pinned at exactly 1.0000 forever. This is the trap that makes the feature look impossible, and it produced two flatly contradictory research findings before a direct test settled it.

2. **Gamma push.** `CGSetDisplayTransferByTable` accepts ramp entries above 1.0 and does not clamp them (requested 1.4500, read back 1.4500). With the panel in HDR mode 1.0 is no longer peak scanout, so the excess maps into the unlocked headroom and _every_ pixel on the desktop brightens. That is why a 1×1 trigger suffices: the trigger unlocks, the ramp spends.

**There is no instrument on the machine that can verify the result.** `screencapture` and `CGDisplayCreateImage` sample the framebuffer _before_ the display gamma LUT, so a boosted and an unboosted screenshot are byte-identical. Confirmed visually by a human A/B test instead.

## Constraints that cost a measurement

- The **main runloop must turn over** between configuring the layer and the grant arriving — CoreAnimation commits its transaction at the end of a runloop iteration. Engagement is asynchronous with a callback; there is deliberately no blocking "engage and wait" entry point, because a nested `-runUntilDate:` spin makes the trigger silently no-op.
- **Never re-capture a baseline ramp while a factor is applied.** That squares the factor on every capture — measured 1.2952 → 1.6776 across one sleep/wake in an early draft, unbounded.
- **Apply only once headroom has settled.** The factor is larger at lower headroom, so acting on the first crossing overshoots ~8% and then visibly sags.
- **Releasing is not instant.** Headroom decays over roughly 15 s after the trigger goes away; the UI must not claim "off" until a fresh read says so.
- **Never retain an `NSScreen`.** A held instance reports frozen EDR values forever.
- `ioreg`'s `AppleARMBacklight` → `BrightnessMilliNits` is **stale** — it did not move across a full 1.00 → 0.20 slider sweep. Do not use it as a live readout, or as evidence about luminance in either direction.

## Safety design

The primary property is free: a gamma override is owned per-process and reverts automatically when that process dies, **including under `SIGKILL`**. A crash cannot strand a blown-out panel. The corollary is that the app must _hold_ the boost while it is on — there is no set-and-forget.

On top of that: a settle gate; a baseline-neutrality guard that refuses to capture an already-boosted ramp; gamma write-verification with panic-restore; a headroom-withdrawal guard; refusal to engage in a calibrated reference preset; an unbypassable cap at the single site that writes hardware; `atexit` restore; and a 30-minute idle timeout on the boost only (never on the ordinary 0–100 range).

Hiding the bar releases any active boost — a control the user cannot see must not keep holding the panel bright.

### Attack-test results, 2026-09-20 (Mac15,11 / macOS 15.8)

Run `scripts/brightness-diagnostics/fc-brightness-failure-mode-harness.m` with FloatingClock **quit** (two processes writing the same gamma table fight, and the results are meaningless). **12 passed, 0 failed, 1 skipped.**

| Guard                                        | Result                                                                                           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Boost writes a >1.0 ramp                     | top 1.3000 at headroom 2.6667                                                                    |
| `panicRestore` returns the ramp to identity  | top 1.0000, level dropped to 100                                                                 |
| **SIGKILL a boosted child reverts the ramp** | top 1.0000 — the primary safety property, verified directly                                      |
| **3× sleep/wake does not compound**          | before 1.3000, after 1.3000                                                                      |
| Factor stays under the absolute cap          | 1.3000 ≤ 1.6000                                                                                  |
| Screen reconfiguration leaves a sane ramp    | top 1.3000                                                                                       |
| Absurd request clamped                       | asked 9999, got 140                                                                              |
| Clamped request never exceeds the cap        | top 1.4000 ≤ 1.6000                                                                              |
| `releaseBoost` returns the ramp to identity  | top 1.0000                                                                                       |
| Refuses to boost in a reference preset       | **SKIPPED** — cannot be forced from code; set System Settings → Displays → Preset to exercise it |

## Degradation

- **No extra EDR headroom** (any non-XDR Mac): `maximumPotentialExtendedDynamicRangeColorComponentValue` is 1.0, `maximumLevel` collapses to 100, and the rail is an ordinary brightness slider. No trigger is created and no gamma is written.
- **Calibrated reference preset**: boost refuses, and `boostUnavailableReason` says why so the menu can explain rather than merely grey out.
- **No controllable built-in display** (clamshell on an external monitor): the rail renders `--` and ignores input rather than pretending.
- **Auto-brightness enabled**: the ambient sensor can walk the value back with no user action. The menu warns; it deliberately does **not** disable the setting, which would be a second undeclared system mutation.

## Licensing

Clean-room. Public Apple API plus a `dlopen`'d `DisplayServices`, and no code, constants, per-model device table or response curve from [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (GPL-3.0) — this repository is MIT, and vendoring would relicense it. The mechanism is unprotectable; the expression is ours.

**Correction, 2026-09-20.** An earlier draft claimed their hardcoded `referenceEDR` of 2.66 for `Mac15,11` "does not match this machine, which reports 2.0513 at slider maximum". That was wrong. The 2.0513 reading was taken ~1.2 s after a slider change — mid-ramp, the very sample-before-settled error the engine's own settle gate exists to prevent. Measured with the grant settled, this panel reports **2.6667**, which is exactly 1600/600 and exactly their constant. Runtime derivation remains the right design (no device table, adapts to unreleased hardware) but it is **not more accurate than theirs**.

## Cost

Steady-state CPU delta is below measurement noise: **0.760%** with the rail enabled versus **0.800%** disabled. The first cut measured **+0.32%** because `naturalContentWidth` ran a text layout pass on every 1 Hz tick; it now re-measures only when the rendered composite actually changed.

Measure with a CPU-time delta over ≥25 s (`ps -o time=` sampled twice). `ps %cpu` is a lifetime average dominated by launch cost and reports ~0.0%, which is how the hub's stale "sub-0.1%" claim survived for so long.

## Preferences

| Key                    | Type | Default | Meaning                                                                 |
| ---------------------- | ---- | ------- | ----------------------------------------------------------------------- |
| `BrightnessBarEnabled` | BOOL | `YES`   | Menu "Show Brightness Bar". Hiding also releases any active boost.      |
| `BrightnessBarStep`    | int  | `5`     | `−`/`+` click step in percent, clamped 1–25. Scroll is always ±2/notch. |

There is deliberately **no** `BrightnessBoostEnabled` key. The level _is_ the control, and an inert preference promising a capability the hardware may not have is worse than no preference. The boost is never persisted across launches: a crash-loop must not relaunch into a boosted panel.

Neither key is profile-managed, matching `AudioBarEnabled` and `NetworkBarEnabled` — indicator visibility is deliberately outside the profile system.
