# floating-clock

Always-on-top floating desktop clock for macOS. Single-file Objective-C implementation (~80 KB binary, ~13 MB physical footprint) using NSPanel. Right-click for 25 color themes, 15 font sizes (10–64 pt), and live market-session state across 12 major global stock exchanges. Sub-0.1% idle CPU.

**Hub:** [CLAUDE.md](../../CLAUDE.md) | **Sibling:** [plugins/CLAUDE.md](../CLAUDE.md)

## Build

From the plugin directory:

```bash
cd plugins/floating-clock
make all          # build + bundle + sign
make run          # build + bundle + sign + open app
make install      # install to /Applications
make test         # build + run data-layer unit tests
make check        # build + test (pre-release validation)
make clean        # remove build/ artifacts
make help         # list all targets
```

Tests live in `tests/test_session.m` + `tests/test_levers.m` + `tests/test_holidays.m` + `tests/test_halfdays.m` (iter-176 + iter-193 splits) — 84 fixtures covering
`computeSessionState` (session boundaries, weekend skip, lunch state,
progress math), the TZ-helper layer (DST branching for
BST/CEST/EDT/AEDT, UTC-offset formatting including Kolkata's UTC+5:30,
fullTzLabel composition), cityCode / flag emoji mapping coverage for
all 14 exchanges, starter-profile key-coverage invariants (caught
iter-55 drift in iter-56), progressive countdown format (sub-day
`T-HH:MM:SS` vs ≥24h `T-Nd Hh MMm`), lunch-market identification,
`FCFormatLandingTime` cross-day/cross-weekday matrix,
`FCParseFontWeight` id→NSFontWeight mapping with fallback (iter-88),
`FCResolveSegmentWeight` three-tier fallback chain (segment key →
global FontWeight → Medium, iter-89), and `FCResolveSegmentOpacity`
three-tier fallback chain with clamping (segment key → CanvasOpacity
→ theme->alpha, iter-90). Added after iter-48 caught a
"closed-before-open-today" off-by-7h bug that had shipped since
iter-9.

Binary at `build/floating-clock` (~184 KB signed), app bundle at
`build/FloatingClock.app`. App bundle includes
`Contents/Resources/Icon.icns` (generated at build time from
`Sources/gen-icon.m` via Core Graphics — no external image
dependencies). Spotlight/Launchpad/Finder index the app with this icon
after first install.

Third-party code: `Sources/vendor/RMBlurredView/` vendors
[RMBlurredView](https://github.com/raffael/RMBlurredView) (Raffael
Hannemann, 2013, MIT) for the frosted-glass segment backdrops. ~115
LoC, only public APIs (CIFilter + CALayer.backgroundFilters), one
local pragma delta from upstream (iter-81).

## Slash Commands

| Command                     | Purpose                                                                          |
| --------------------------- | -------------------------------------------------------------------------------- |
| `/floating-clock:install`   | Build + copy to `/Applications/` + launch                                        |
| `/floating-clock:launch`    | Open the installed (or local) app                                                |
| `/floating-clock:quench`    | Terminate the running clock                                                      |
| `/floating-clock:diagnose`  | One-page health report (binary info, signing, process, active profile, tests)    |
| `/floating-clock:uninstall` | Quit, remove from `/Applications/`, clear NSUserDefaults (confirmation required) |

## Design

- **NSPanel (not NSWindow)**: Borderless, non-activating, always floating
- **All Spaces**: `collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary`
- **Timer**: `dispatch_source_t` aligned to second boundary, 1-second interval
- **No Dock icon**: `LSUIElement=YES` in Info.plist
- **Font resolution** (in priority order):
  1. User override via NSUserDefaults key `FontName` (PostScript name)
  2. iTerm2 default profile's `Normal Font` (extracted from `com.googlecode.iterm2.plist`)
  3. System monospaced fallback: SF Mono (macOS 10.15+) or Menlo (older)
  4. Size selectable from 15 options (10 / 12 / 14 / 16 / 18 / 20 / 22 / 24 / 28 / 32 / 36 / 42 / 48 / 56 / 64 pt) grouped as Small / Medium / Large / Huge in the context menu
- **Color themes**: 30 preset bundles (each sets foreground, background, alpha atomically). Originals (10): Terminal, Amber CRT, Green Phosphor, Solarized Dark, Dracula, Nord, Gruvbox, Rose Pine, High Contrast, Soft Glass. iter-32 (+10): Synthwave, Monokai, Gotham, Ayu Mirage, Catppuccin, Tokyo Night, Kanagawa, Paper White, Sepia, Midnight Blue. iter-92 (+5): Oceanic Deep, Cherry Blossom, Espresso, Lavender Dream, Mint Dark. iter-132 (+2): Forest, Volcanic. iter-169 (+1): Carnival (Brazilian yellow-on-green, pairs with B3). iter-195 (+1): Aurora (cyan-green on deep indigo — cool winter-night mood). iter-222 (+1): Concrete (architectural chromaless gray on charcoal — fills the gap between nord's blue-tinted gray and high_contrast's pure white-on-black). Menu items show 14×14 color swatches drawn inline via Core Graphics.
- **Market sessions** (when a non-local market is selected):
  - 14 major exchanges grouped by region (Americas / Europe / Africa / Asia / Oceania) — NYSE, TSX, B3, LSE, Euronext, XETRA, SIX, TSE, HKEX, SSE, KRX, NSE, ASX, JSE (iter-155 JSE, iter-161 B3)
  - Time displayed in that exchange's local time via IANA `NSTimeZone` (DST-correct across hemispheres)
  - Second line shows state glyph + market code + progress bar + countdown:
    - `●` green: OPEN (regular session)
    - `◑` violet: LUNCH (TSE / HKEX / SSE only)
    - `◐` amber: PRE-MARKET (iter-123, final 15 min before today's open, weekdays only)
    - `◒` rose: AFTER-HOURS (iter-125, first 15 min after today's close, weekdays only)
    - `○` gray: CLOSED (overnight, weekend) — shows `opens in Xh Ym` or `opens EEE HH:mm` for gaps >99h
  - Progress bar uses Unicode 1/8-width blocks (`█▉▊▋▌▍▎▏░`) for sub-cell smoothness
  - Countdown format: `2h17m` (≥1h), `47m` (<1h), `5m32s` (<2m)
  - Window auto-resizes to a 2-line layout with center-anchor; falls back to 1-line when Local Time is selected
- **Default position** (first launch, no saved state): bottom-center of main screen's `visibleFrame` (respects menu bar and Dock)
- **Multi-monitor position persistence**:
  - Saves both window frame and screen ID on every move (`windowDidMove:`)
  - On launch: restores only if saved screen still connected AND frame intersects that screen
  - If saved screen disconnected: falls back to bottom-center of main screen
  - At runtime: monitors `NSApplicationDidChangeScreenParametersNotification`; if clock's screen unplugged, relocates to bottom-center of main screen with animation
- **Defensive parsing**: All plist dictionary lookups verify `isKindOfClass:` before use — malformed iTerm2 plist cannot crash the clock
- **Self-generated icon**: `gen-icon` helper draws a 1024×1024 clock glyph (dark rounded square + white face + 10:10 hands) using only Core Graphics. `iconutil` bundles into ICNS at build time. Zero external image assets.

## Touchpoints

Everything this plugin touches on your system. Nothing outside this table.

| Kind                    | Detail                                                                                                                                                                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Reads (filesystem)**  | `~/Library/Preferences/com.googlecode.iterm2.plist` — read-only, font lookup only. If missing/malformed: silently falls back to SF Mono.                                                                                                                                  |
| **Writes (filesystem)** | `~/Library/Preferences/com.terryli.floating-clock.plist` — written via NSUserDefaults. See Runtime Preferences below for keys.                                                                                                                                            |
| **Install path**        | `/Applications/FloatingClock.app` — placed by `/floating-clock:install` or `make install`. Uninstall removes this directory only.                                                                                                                                         |
| **Build artifacts**     | `plugins/floating-clock/build/` — gitignored. Contains `floating-clock` binary, `gen-icon` helper, PNG iconset, `Icon.icns`, and `FloatingClock.app`. `make clean` removes.                                                                                               |
| **Linked frameworks**   | `Cocoa`, `Foundation`, `AppKit`, `CoreFoundation`, `libobjc`, `libSystem` (main binary). Plus `ImageIO`, `UniformTypeIdentifiers`, `CoreServices` (build-time `gen-icon` helper only — not linked into the running app). All framework paths are system, not third-party. |
| **Signing**             | Ad-hoc code signature via `codesign --force --deep --sign -`. No Developer ID cert required. No notarization. Gatekeeper allows ad-hoc apps on first run with standard right-click → Open bypass if needed.                                                               |
| **Entitlements**        | None. Unsandboxed. No hardened runtime flags.                                                                                                                                                                                                                             |
| **Network**             | None. The binary makes no network calls.                                                                                                                                                                                                                                  |
| **Launchd**             | None. Not registered as a LaunchAgent or LaunchDaemon. No autostart at login — launch manually via Spotlight, Launchpad, Finder, or `/floating-clock:launch`.                                                                                                             |
| **Dock / menu bar**     | Hidden from both. `LSUIElement=YES` in Info.plist makes it an accessory app — no Dock tile, no application menu bar. The only visible UI is the floating clock window itself.                                                                                             |
| **System permissions**  | None at runtime. Accessibility access is NOT required (nothing uses the AX API). The context menu works via standard NSMenu, which needs no permission grant.                                                                                                             |
| **Keyboard monitors**   | One local (in-process) `NSEvent` monitor for ⌘Q to route to `NSApp terminate:`. Scope: only this app's events — does not see other apps' keystrokes. No global event taps.                                                                                                |
| **Clock source**        | `dispatch_source_t` on the main queue, timer aligned to second boundaries via `[NSDate timeIntervalSince1970]` fractional remainder. No IPC with any external time service.                                                                                               |

## Runtime Preferences

All settings persist in `~/Library/Preferences/com.terryli.floating-clock.plist` (NSUserDefaults). Inspect or reset via the `defaults` CLI:

```bash
defaults read com.terryli.floating-clock          # show all
defaults delete com.terryli.floating-clock        # reset everything (next launch -> defaults)
```

**Full key table (60+ keys): [docs/runtime-preferences.md](./docs/runtime-preferences.md)** — display modes, fonts, themes, per-segment overrides, profiles, urgency levers, indicator bars. Update the spoke, not this hub, when adding keys.

## Implementation

**Entry point**: `Sources/clock.m` (~240 LoC)
**Icon helper**: `Sources/gen-icon.m` (~170 LoC, build-time only)

Post-v4 modularization, source is organized hierarchically by area:

```
Sources/
  clock.m                               entry + registerDefaults + panel init
  core/
    FloatingClockPanel.{h,m}            NSPanel subclass (interface)
    FloatingClockPanel+Runtime.{h,m}    tick pipeline, timers, positioning
    FloatingClockPanel+Layout.{h,m}     3-segment + legacy layout maths
    DateFormatPrefix.{h,m}              9-preset DateFormat → UTS#35 pattern (iter-113)
    SkyGlyph.{h,m}                      5-phase hour-of-day → emoji dispatcher (iter-114)
    SegmentGap.{h,m}                    7-preset SegmentGap → points (iter-115)
    DensityPad.{h,m}                    6-preset Density → inner-row padding (iter-116)
    CornerRadius.{h,m}                  8-preset CornerStyle → layer radius (iter-117)
    ShadowSpec.{h,m}                    7-preset ShadowStyle → spec struct (iter-120)
    SessionSignalWindow.{h,m}           5-preset SessionSignalWindow → minutes, gates PRE-MARKET + AFTER-HOURS promotions (iter-126)
    ClipboardHeader.{h,m}               FCComposeClipboardSnapshot — self-documenting UTC-stamped header for Copy cluster (iter-160)
  segments/
    FloatingClockSegmentViews.{h,m}     Local/Active/Next/ClockContentView subclasses
  content/
    ActiveSegmentContentBuilder.{h,m}   live-markets rendering
    NextSegmentContentBuilder.{h,m}     next-to-open rendering
    SegmentHeaderRenderer.{h,m}         shared title/legend/hrule helper (iter-73)
    UrgencyColors.{h,m}                 shared urgency palette + thresholds (iter-73), continuous gradient + 1Hz pulse (iter-212)
    UrgencyHorizon.{h,m}                6-preset UrgencyHorizon → seconds, runtime gradient horizon (iter-215)
    UrgencyFlash.{h,m}                  4-preset UrgencyFlash → dim-alpha, runtime 1Hz pulse intensity (iter-219)
    WeekProgressBar.{h,m}               FCWeekFraction + FCBuildWeekProgressBar — pure-offline week-progress bar on LOCAL (iter-229)
    LandingTimeFormatter.{h,m}          dual-zone time w/ weekday disambiguation (iter-74)
  data/
    ThemeCatalog.{h,m}                  25 theme presets + CG swatches (iter-92)
    MarketCatalog.{h,m}                 12-exchange registry + IANA helpers
    MarketSessionCalculator.{h,m}       computeSessionState, countdown fmts, progress-bar 10-glyph dispatch (iter-91)
  rendering/
    FontResolver.{h,m}                  iTerm2 → system monospaced cascade + FontWeight (iter-88/89) + LetterSpacing (iter-94) + LineSpacing (iter-95) + CurrentTimeFormat (iter-107)
    SegmentOpacityResolver.{h,m}        3-tier canvas-opacity fallback (iter-90)
    AttributedStringLayoutMeasurer.{h,m} NSLayoutManager multi-line height
    VerticallyCenteredTextFieldCell.{h,m} cell that centers attributed text
  menu/
    FloatingClockPanel+MenuBuilder.{h,m} full preferences menu + Profile submenu + Quick Styles integration
    FloatingClockPanel+SegmentMenus.{h,m} LOCAL / ACTIVE / NEXT scoped menus (iter-87 split)
    FloatingClockPanel+MenuHelpers.{h,m} shared NSMenu helpers (iter-96 proactive split)
  actions/
    FloatingClockPanel+ActionHandlers.{h,m} every menu-item action target (40+ setters + applyQuickStyle + resetVisualStyle)
  preferences/
    FloatingClockPanel+ProfileManagement.{h,m}  save/load/switch/delete
    FloatingClockStarterProfiles.{h,m}  6 bundled starters + profileManagedKeys
    FloatingClockQuickStyles.{h,m}      14 Quick Style bundled moods (iter-104 extracted, iter-105/106/130/144/170/196 expansions)
  vendor/
    RMBlurredView/                       iter-65 frosted-glass library (MIT)
  gen-icon.m                             build-time-only icon renderer
```

Design notes:

- `@autoreleasepool` for memory hygiene
- Self-contained: no separate header files, no external dependencies beyond system frameworks
- No SwiftUI, no Swift runtime tax
- Automatic Reference Counting (ARC)
- `resolveClockFont()`: 4-tier font resolution
- `defaultFrame()`: bottom-center of primary display (uses `[NSScreen screens].firstObject`, not `mainScreen`)
- `screensChanged:`: runtime observer for monitor hot-unplug
- `buildMenu` / `refreshMenuChecks:` / `applyDisplaySettings`: NSMenu-driven preferences
- `groupedSubmenuTitled:` + `setChecksInMenu:` — recursive helpers for hierarchical menus (font sizes, regions)
- `kThemes[]` — static C array of 10 theme structs (id, display, fg_rgb, bg_rgb, alpha)
- `swatchForTheme()` — inline CoreGraphics drawing of menu item color swatches
- `kMarkets[]` — static C array of 13 market structs (id, display, code, iana, session hours, lunch times)
- `computeSessionState()` — state + progress + countdown via `NSCalendar` in the exchange's IANA TZ
- `buildProgressBar()` — Unicode 1/8-width block bar with color-split filled/unfilled portions via `NSAttributedString`
- `ClockContentView`: custom `NSView` subclass whose `menuForEvent:` returns the context menu on right-click

## Canonical UI Names (iter-199 registry)

Every user-visible UI element has a stable canonical short name so feedback can be precise (e.g. "the label in the bottom-right of ACTIVE called [COUNTDOWN] is 2pt too small"). Toggle `Show Debug Labels` in the context menu (or `defaults write com.terryli.floating-clock ShowDebugLabels -bool YES`) to render these as tiny corner overlays on the running app. Hovering any named NSView shows its full NSToolTip.

| Nameidg    | Surface class                | Purpose / hover tooltip                                                                                          |
| ---------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `[LOCAL]`  | `LocalSegmentView`           | LOCAL — top segment, current user-local time                                                                     |
| `[ACTIVE]` | `ActiveSegmentView`          | ACTIVE — bottom-left segment, currently-open markets with progress bars                                          |
| `[NEXT]`   | `NextSegmentView`            | NEXT — bottom-right segment, upcoming-open markets with landing countdowns                                       |
| `[TIME]`   | `LocalSegmentView.timeLabel` | TIME — user-local time text inside [LOCAL] (NSToolTip only; no corner overlay since the label fills the segment) |

Sub-element names for elements that live inside attributed-string content (e.g. `[PROGRESSBAR]`, `[COUNTDOWN]`, `[HEADER-LEGEND]`, `[SKYGLYPH]`, `[DATE]`, `[MARKETCODE]`) can't use NSToolTip directly because `NSAttributedString` text runs aren't distinct `NSView`s. A future iter may add a custom NSView overlay that turns on text-run hit-testing when `ShowDebugLabels` is YES; for now the names stay as a paper reference so the user can call them out verbally ("the [COUNTDOWN] column right-aligns oddly when the market has lunch") and we find them in code by grep.

## Always-visible audio I/O status bar (`AudioStatusIndicator`, 2026-06-11)

`Sources/core/AudioStatusIndicator.{h,m}` — interactive bar pinned directly above
the clock (the **bottom-most** slot of the indicator stack; the mic-mute and VPN
bars shift one 20pt+3pt slot up while it shows). Visible **by default**
(`AudioBarEnabled` registered YES). Replaces the decommissioned
`com.terryli.audio-device-monitor` launchd service (amonic repo,
`archive/audio-device-monitor-decommissioned-2026-06-11/`) — automatic
"plug-and-play" prioritization is gone; this bar is fully manual control.

Layout: `IN <device> − <level> +  │  OUT <device> − <level> +` (green `IN` /
blue `OUT` prefixes, middle-truncating names, levels 0–100 or `--` when the
device exposes no volume control — e.g. DisplayPort sinks).

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
backdrops. 2026-06-11 (second user request): the same treatment IS now on the
clock body — see "Hairline segment border" below.

### Hairline segment border (`BorderStyle`, 2026-06-11)

The audio bar's edge recipe promoted to the clock pills. Catalog dispatcher
`Sources/core/SegmentBorderSpec.{h,m}` (locked by test_levers), applied in
BOTH layout families via `FCApplyBorderToLayer` (FloatingClockPanel+Layout.m):
the three-segment pills AND the compact local-only/single-market modes, where
the window contentView IS the pill (first ship missed those — user caught the
bare double-click-shrunk view; three-segment clears the contentView border so
mode switches never leak a stale frame). Color is luminance-adaptive per
segment theme bg: white @ alpha on dark fills, black @ alpha+0.08 on light.
Menu: context menu → Display → Border. Presets: `none` / `hairline` (1pt @
0.22, DEFAULT — registered in clock.m, threaded through all 8 starter
profiles; Minimalist=none, Auction Watcher=frame) / `frame` (1.5pt @ 0.35).

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
- **Change flash**: a device or level change blinks the affected text amber
  for ~1.4s (`kFlashSecs`), then decays to white on the next tick — external
  changes (volume keys, other apps) catch the eye.

| default key       | type | default | meaning                        |
| ----------------- | ---- | ------- | ------------------------------ |
| `AudioBarEnabled` | BOOL | `YES`   | master on/off (also in menu)   |
| `AudioBarStep`    | int  | `5`     | −/+ click step %, clamped 1–25 |

### Pull-out device menus + Bluetooth connect/takeover (2026-06-11, second directive)

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

### Scope-independence hijack guard (2026-06-11, user bug report)

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

### Stable local signing identity (2026-06-11, TCC re-prompt fix)

Ad-hoc signing (`codesign --sign -`) mints a new code identity per build →
TCC (Bluetooth/mic) re-prompts after every reinstall. The Makefile now
signs with the self-signed cert **"FloatingClock Local Signing"** when
present (auto-fallback to ad-hoc). One Allow then persists forever.
Recreate on a new machine (OpenSSL 3 p12 import is broken against macOS
`security` — import PEMs separately):

```bash
DIR=~/.local/share/floating-clock-signing && mkdir -p $DIR && cd $DIR
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=FloatingClock Local Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
security import key.pem  -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import cert.pem -k ~/Library/Keychains/login.keychain-db
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem  # GUI password dialog
```

Silent Bluetooth pre-authorization is impossible without MDM — the grant
row is `kTCCServiceBluetoothAlways` / `com.terryli.floating-clock` in the
user TCC.db; one human click is mandatory, once per identity.

## Generic external-state status indicator (`VPNStatusIndicator`, 2026-06-07)

A second banner alongside the mic-mute bar: `Sources/core/VPNStatusIndicator.{h,m}`.
It shows a colored bar (default violet `#8B2FE6`) above the clock — and **above the
mic-mute bar when that one is showing** (via the new `FCMicMuteIndicator -isShowing`) —
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

## Known limitations

- **Holiday awareness: 14/14 exchanges (2026 fixtures); half-days: 8/14.** `Sources/data/HolidayCalendar.{h,m}` + `HalfDayCalendar.{h,m}`, wired into `computeSessionState` with correct back-to-back chaining (weekend+holiday clusters). Live caveats: 6 exchanges' half-days deferred, SSE make-up Saturdays (补班) not modelled, lunar dates fixture-locked best-effort. Full iter-173…192 chronicle + per-exchange detail: [docs/holiday-coverage.md](./docs/holiday-coverage.md).
- **No extended after-hours trading window modelled**. Each exchange's full extended session (US equities 16:00–20:00 ET, various 1–2 h windows elsewhere) is not modelled. What is modelled: the first 15 minutes immediately after regular close promote CLOSED → AFTER-HOURS (iter-125, rose ◒ glyph) — a short signal symmetric to iter-123's PRE-MARKET. Full per-market extended-session modelling remains deferred pending a decision on per-exchange duration data.

## Future Enhancements

### Near-term

- Holiday awareness (bundled annual JSON per exchange, refreshed yearly)
- System appearance (light/dark) auto-adjust of themes
- Copy Time / Copy segments keyboard shortcuts (requires global event tap for LSUIElement)

### Tier-3

- Multi-market rotation mode (cycle 2–3 favorites every 10 s)
- User-definable theme bundles (pick fg/bg/alpha via menu)
- Settings export/import (JSON, for sync across machines)
- Launchd login-item for autostart

### Already shipped in v4 (moved out of "future")

- ~~Per-segment themes (LocalTheme / ActiveTheme / NextTheme)~~ — iter-14
- ~~Profile system with bundled starters~~ — iter-17
- ~~Segment-scoped right-click menus~~ — iter-15
- ~~Regional TZ abbreviations (PDT / BST / CEST / JST / AEDT) + UTC offset~~ — iter-37/38
- ~~Inline UTC reference on LOCAL~~ — iter-39
- ~~Sun/moon day-night glyph~~ — iter-42
- ~~Progress-bar running head~~ — iter-43
- ~~Urgency color tiers on ACTIVE + NEXT countdowns~~ — iter-44/45
- ~~NEXT cross-day weekday disambiguation~~ — iter-49
- ~~Unit test harness for session-state + TZ helpers~~ — iter-50/51
- ~~PRE-MARKET state (15-min amber ◐ pre-open window)~~ — iter-123
- ~~AFTER-HOURS state (15-min rose ◒ post-close window)~~ — iter-125
- ~~User-configurable SessionSignalWindow (off / 5-60 min)~~ — iter-126
- ~~Copy Time / Active Markets / Next Opens to clipboard~~ — iter-149/150
