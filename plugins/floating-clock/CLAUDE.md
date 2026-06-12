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

## Overlay indicators (audio bar · mic-mute · VPN) — [docs/overlay-indicators.md](./docs/overlay-indicators.md)

Audio I/O bar (`AudioStatusIndicator`, default ON): manual IN/OUT device +
volume control above the clock; right-click pull-out menus with Bluetooth
connect/takeover (`AudioDeviceSelectionMenuController` +
`BluetoothPairedAudioDeviceConnector`); coreaudiod hijack guard keeps IN/OUT
independent. All overlay panels are drag-WELDED to the clock as child windows
(`ClockChildWindowAttachment`). The VPN/state-file banner stays generic and
secret-free. Defaults: `AudioBarEnabled`, `AudioBarStep`, `VPNIndicator*`.
Full saga, defaults tables, and diagnostics: the spoke above.

## Solar canvas + segment styling — [docs/solar-canvas-and-styling.md](./docs/solar-canvas-and-styling.md)

Compact-mode background rides an OKLab twilight ramp over the LIVE solar
elevation at the user's CoreLocation coordinates (`CanvasColorMode`:
solar-vivid DEFAULT / solar-atmospheric / theme — `SolarSkyColorRamp` +
`FCSolarElevationDegrees`). Hairline segment border lever (`BorderStyle`:
hairline DEFAULT / frame / none — `SegmentBorderSpec`,
`FCApplyBorderToLayer`). Compact text legibility via Core Text round-join
outline (`SolarOutlinedTextRenderingView`).

## Build signing + TCC — [docs/signing-and-tcc.md](./docs/signing-and-tcc.md)

The Makefile signs with the persistent "FloatingClock Local Signing" cert so
TCC grants (Bluetooth / mic / location) survive rebuilds. Identity changes
reset ALL grants — one re-Allow each. Cert recreation recipe in the spoke.


## Known limitations

- **Holiday awareness: 14/14 exchanges (2026 fixtures); half-days: 8/14.** `Sources/data/HolidayCalendar.{h,m}` + `HalfDayCalendar.{h,m}`, wired into `computeSessionState` with correct back-to-back chaining (weekend+holiday clusters). Live caveats: 6 exchanges' half-days deferred, SSE make-up Saturdays (补班) not modelled, lunar dates fixture-locked best-effort. Full iter-173…192 chronicle + per-exchange detail: [docs/holiday-coverage.md](./docs/holiday-coverage.md).
- **No extended after-hours trading window modelled**. Each exchange's full extended session (US equities 16:00–20:00 ET, various 1–2 h windows elsewhere) is not modelled. What is modelled: the first 15 minutes immediately after regular close promote CLOSED → AFTER-HOURS (iter-125, rose ◒ glyph) — a short signal symmetric to iter-123's PRE-MARKET. Full per-market extended-session modelling remains deferred pending a decision on per-exchange duration data.

## Future Enhancements — [docs/roadmap.md](./docs/roadmap.md)

Near-term + Tier-3 backlog and the shipped-in-v4 log live in the spoke.
