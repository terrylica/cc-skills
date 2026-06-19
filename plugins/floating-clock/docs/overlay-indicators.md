← [Back to plugin CLAUDE.md](../CLAUDE.md)

# Overlay indicators — audio I/O bar · mic-mute banner · VPN banner

The clock carries a stack of overlay NSPanels pinned above it. This spoke is
the SSoT for the audio bar saga (2026-06-11/12), the drag-welding
architecture, and the generic VPN/state-file banner.

## Always-visible audio I/O status bar (`AudioStatusIndicator`, 2026-06-11)

`Sources/core/AudioStatusIndicator.{h,m}` — interactive bar pinned directly above
the clock (the **bottom-most** slot of the indicator stack; the mic-mute and VPN
bars shift one 20pt+3pt slot up while it shows). Visible **by default**
(`AudioBarEnabled` registered YES). Replaces the decommissioned
`com.terryli.audio-device-monitor` launchd service (amonic repo,
`archive/audio-device-monitor-decommissioned-2026-06-11/`) — automatic
"plug-and-play" prioritization is gone; this bar is fully manual control.

Layout: `IN <device> − <level> +  │  OUT <device> − <level> +` (green `IN` /
blue `OUT` prefixes, levels 0–100 or `--` when the device exposes no volume
control — e.g. DisplayPort sinks).

**Content-width sizing (2026-06-14).** Names used to truncate in the middle
(`Terry's AirPods Pro` → `Terry's…`) because the bar was locked to the clock
width and split 50/50. Now each zone is measured for the width it needs to
show its prefix+name in full (`-zoneWidthForName:isInput:muted:`), and the bar
**grows wider than the clock**, **centered** on it, to fit both — floored at
the clock width (never narrower) and capped at the screen's visible width
(only then do names shrink proportionally and, as a last resort, truncate).
Geometry SSoT: `FCComputeOverlayFrameWithWidth` in `OverlayStackingPositioner`
(the legacy clock-width `FCComputeOverlayFrame` is now that fn with
`desired == clock width`). The asymmetric zone split lives in
`-layoutZonesInBarWidth:` (even slack split when the bar ≥ content). Cosmetic
note: the mic-mute / VPN banners stay clock-width, so when the audio bar
widens they sit centered above a wider bar.

Interactions (each zone independent):

- **Click device name** → switch that category to the next available REAL
  device, name-sorted ring. Virtual/aggregate transports (BackgroundMusic,
  Lark loopback, multi-output sets) are excluded from the ring — cycling
  wedged on "Background Music" otherwise (its UI-Sounds sibling refuses
  main-default) — but a virtual default is still _displayed_ truthfully, and
  one click escapes to the first real device.
- **Click − / +** → step that category's volume by `AudioBarStep` (default 5).
- **Click the number** → top half steps up, bottom half steps down.
- **Scroll over a zone** → fine adjust (±2 per notch).

Implementation notes: same NSPanel+CALayer mechanics as the other banners but
`ignoresMouseEvents = NO`; `FCAudioZoneView` overrides `hitTest:` to claim every
click inside the zone (NSTextField subviews swallowed mouseDown otherwise —
verified 2026-06-11). Refresh is tick-driven (6 HAL property reads/sec, no
listeners/IOProcs); each zone caches a render-key composite so labels only
redraw when something visible changes.

**Any-background legibility (research-converged "dual-layer" treatment,
2026-06-11):** the pill melted into pure-black backgrounds (user report). Fix —
the same recipe macOS HUDs / launcher panels use, zero per-frame sampling:
1pt hairline border (white @ 0.22) defines the edge on black where shadows are
invisible; surface lifted 0.11 → 0.16 gray (Material-style dark elevation) so
the fill separates from `#000`; `NSPanel hasShadow` keeps doing the work on
light backgrounds. Verified by screenshot over both pure-black and white
backdrops. The same treatment now lives on the clock body — see
[solar-canvas-and-styling.md](./solar-canvas-and-styling.md).

AskUserQuestion-selected extras (same day, all verified on-screen):

- **"Show Audio Bar"** context-menu toggle (Display section) → flips
  `AudioBarEnabled` with instant show/hide + checkmark.
- **Mute state on IN**: while the ACTIVE mic is muted (CoreAudio mute flag on
  the current default input OR the mic indicator's banner state), the IN zone
  renders `IN⊘` + red struck-through device name + red level. 2026-06-11
  fix: `FCMicMuteIndicator` now binds DEFAULT-INPUT-FIRST (was Antlion-first,
  which falsely flagged AirPods red when the Antlion's hardware button was
  pressed); Bluetooth inputs are never silence-metered (a persistent IOProc
  would hold the headset in HFP/SCO call mode). The Antlion's analog button
  is still caught — when the Antlion is the default input. Companion fix
  outside this repo: `~/.local/bin/mic-mute` (chezmoi) gained a `default`
  target and both Karabiner F10 bindings use it, so the mute key follows the
  active mic too.
- **Mute state on OUT (2026-06-14)**: symmetric to IN — when the system output
  is muted (the mute key / `set volume output muted`), the OUT zone renders
  `OUT⊘` + red struck-through device name + red level. Detection is a pure 1Hz
  property read, `FCReadOutputMute` = `kAudioDevicePropertyMute` on the
  **output scope** main element of the default output device. There is NO
  silence-meter/IOProc path (that's input-only — outputs have no analog mute
  button to catch), so the HAL flag is the whole signal.
  - **Why `FCReadOutputMute` must NOT gate on `AudioObjectHasProperty` (the one
    asymmetry vs `FCReadInputMute`):** on the OUTPUT scope, `AudioObjectHasProperty`
    returns FALSE _even when the property is readable_ (macOS quirk, confirmed
    on this Mac across built-in / Bluetooth / virtual by a toggle probe). Gating
    on it would make output mute silently always-NO. `AudioObjectGetPropertyData`
    self-gates instead — it errors on devices that truly lack the property (→ NO)
    and returns 0 where there's no independent HAL mute.
  - **Coverage / honesty:** Bluetooth (AirPods) tracks the system mute exactly.
    Built-in speakers and virtual devices have no independent HAL mute — the
    volume-key mute lives in the OS mixer, not the device — so they read 0
    (unmuted) and the OUT zone simply never shows `⊘`. We deliberately do NOT
    treat volume==0 as muted (would false-positive when the user just turns the
    level down, and on HDMI/DP sinks). Detection verified empirically (on-device
    mute-toggle probe) + on-screen, not by headless unit test; the unit suite
    only locks the unknown-device nil-guard (`test_mute_readers_guard`).
- **Change flash**: a device or level change blinks the affected text amber
  for ~1.4s (`kFlashSecs`), then decays to white on the next tick — external
  changes (volume keys, other apps) catch the eye.

| default key       | type | default | meaning                        |
| ----------------- | ---- | ------- | ------------------------------ |
| `AudioBarEnabled` | BOOL | `YES`   | master on/off (also in menu)   |
| `AudioBarStep`    | int  | `5`     | −/+ click step %, clamped 1–25 |

## Drag-welding (`ClockChildWindowAttachment`, 2026-06-12)

All three overlay panels (audio bar, mic-mute, VPN) are attached as CHILD
WINDOWS of the clock via `Sources/core/ClockChildWindowAttachment.{h,m}` —
the WindowServer moves them atomically with the clock during drags (the old
windowDidMove→syncPosition chase trailed one move-event behind; fast drags
visibly decoupled the bar — user-caught "elastic trail"). Separation of
concerns: indicators own content + relative stacking (syncPosition
unchanged); the attachment module owns only the idempotent attach +
detach-BEFORE-orderOut contract. New overlays get welding by calling the two
functions at their show/hide points.

## Pull-out device menus + Bluetooth connect/takeover (2026-06-11)

**Right-click / two-finger tap / ctrl-click** on either zone pops an independent
device-selection menu (all three gestures come free via `-menuForEvent:`).
The left-click cycle toggle is untouched. Verified on-screen 2026-06-11:
menu structure, direct live-device selection, IN/OUT independence, and a real
takeover (device connected & switched from an iPhone).

- `Sources/core/AudioDeviceSelectionMenuController.{h,m}` — builds the menu
  fresh per invocation: live CoreAudio devices (✓ on current; click = switch
  now) + `BLUETOOTH — CONNECT` section of paired-but-offline BT audio devices
  (`○` prefix). Orchestrates connect → bounded HAL polling (0.5s × 16) →
  set-default, with transient `⏳ name…` / `✗ name` status in the zone.
- `Sources/core/BluetoothPairedAudioDeviceConnector.{h,m}` — IOBluetooth
  wrapper: `pairedDevices` filtered to the Audio/Video major class;
  async `openConnection:` with self-retaining attempt objects + timeout
  backstop. **`openConnection` IS the takeover request** — audio devices
  (AirPods/W1/H1, multipoint headsets) switch to the most recent requesting
  host; this is the in-app equivalent of `blueutil --connect` /
  lapfelix/BluetoothConnector (the FOSS canon for un-sticking devices from an
  iPhone). CoreBluetooth is BLE-only and useless here; IOBluetooth remains
  the only public classic-BT API.
- Requirements: `-framework IOBluetooth` (Makefile CFLAGS) and
  `NSBluetoothAlwaysUsageDescription` (Info.plist; macOS TCC prompts on the
  first menu open since `pairedDevices` is called lazily).
- Resource posture: zero steady-state cost — no listeners, no daemons, no
  polling; IOBluetooth is touched only while a menu is open or a connect is
  in flight. Connect ≠ routed: the CoreAudio endpoint appears async after
  the baseband link, hence the poll-then-select stage (honest `✗` when a
  device connects but exposes no endpoint in that scope, e.g. a speaker
  picked from the INPUT menu).

## Scope-independence hijack guard (2026-06-11, user bug report)

Selecting AirPods for INPUT also flipped the OUTPUT. Probe-verified root
cause (`scripts/audio-diagnostics/fc-audio-default-routing-probe.m`): the
defaults are NOT bound — AirPods are TWO HAL devices (24kHz HFP mic +
48kHz A2DP out) behind separate default-in/default-out properties —
**coreaudiod auto-routes the other scope to a BT device when it connects**
(watcher caught it twice, +0s and +7s after connect). Fix in
`AudioDeviceSelectionMenuController`: snapshot the other scope before
connect; for 20s (40 × 0.5s) restore it whenever it's hijacked _by the
connected device_ (ID-change first, then name match), max 3 restores then
`✗ macOS keeps re-routing`. `↩ name` transient on each restore. Explicit
user selections bump a per-scope generation counter that cancels the guard
(menu picks AND the left-click cycle). Restore targets may legitimately be
virtual (Background Music) — existence is re-probed across ALL transports
(`deviceIDStillExists:`), since HAL IDs are reassigned on unplug.
Adversarially reviewed (19-agent workflow, 16 findings → 8 confirmed → all
fixed or dispositioned 2026-06-11).

**Per-app caveat (Typeless et al.)**: live capture sessions do NOT migrate
when the default input changes — apps must listen for
`kAudioHardwarePropertyDefaultInputDevice` and rebind; many (Typeless
"Auto-detect") resolve once at session start. Capture-path truth-test:
`scripts/audio-diagnostics/fc-default-input-capture-rms-probe.m` (records
default input, prints per-500ms RMS; AirPods stem-scratch is the
discriminator).

## Generic external-state status indicator (`VPNStatusIndicator`, 2026-06-07)

A second banner alongside the mic-mute bar: `Sources/core/VPNStatusIndicator.{h,m}`.
It shows a colored bar (default violet `#8B2FE6`) above the clock — and **above the
mic-mute bar when that one is showing** (via `FCMicMuteIndicator -isShowing`) —
whenever an external **state file** exists on disk. Same `NSPanel`+CALayer mechanics, the
same 1 Hz refresh off the clock `tick`, and `syncPosition` from `windowDidMove:`.

Deliberately **generic and secret-free** — it has no idea what the state represents (a
VPN, tunnel, build, backup). Everything is `NSUserDefaults`-driven (domain
`com.terryli.floating-clock`) and it is **disabled by default**, so the public build ships
inert until a deployment opts in:

| default key             | type   | default                               | meaning                        |
| ----------------------- | ------ | ------------------------------------- | ------------------------------ |
| `VPNIndicatorEnabled`   | BOOL   | `NO`                                  | master on/off                  |
| `VPNIndicatorStateFile` | string | `~/.config/floating-clock/vpn-active` | bar shows iff this path exists |
| `VPNIndicatorLabel`     | string | `"VPN"`                               | bar text                       |
| `VPNIndicatorColorHex`  | string | `"#8B2FE6"`                           | bar color `#RRGGBB`            |

A deployment wires it up by (a) `defaults write com.terryli.floating-clock VPNIndicatorEnabled -bool YES`
(+ optional label/color/path overrides) and (b) having some external toggle create/remove
the state file. Keep this plugin free of any host/IP/secret — the _meaning_ of the state
(and the toggle that drives it) lives in the operator's private infra repo, never here.
