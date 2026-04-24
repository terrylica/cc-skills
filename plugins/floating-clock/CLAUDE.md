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
| `/floating-clock:quit`      | Terminate the running clock                                                      |
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
defaults delete com.terryli.floating-clock        # reset everything (next launch → defaults)
```

| Key                         | Type         | Default                  | Source                                                                                                                                                                                                                                                                                                            |
| --------------------------- | ------------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DisplayMode`               | NSString     | `"three-segment"`        | Menu (three-segment / single-market / local-only)                                                                                                                                                                                                                                                                 |
| `ShowSeconds`               | BOOL         | `YES`                    | Menu — strips `:ss` from all time displays when NO                                                                                                                                                                                                                                                                |
| `ShowDate`                  | BOOL         | `YES`                    | Menu                                                                                                                                                                                                                                                                                                              |
| `DateFormat`                | NSString     | `"short"`                | Menu (short / long / iso / compact_iso / numeric / usa / european / weeknum / dayofyr — 9 presets, iter-111)                                                                                                                                                                                                      |
| `TimeFormat`                | NSString     | `"24h"`                  | Menu (24h / 12h) — only affects LOCAL; UTC always 24h canonical                                                                                                                                                                                                                                                   |
| `TimeSeparator`             | NSString     | `"colon"`                | Menu (colon / middot / space / slash / dash / pipe / plus — 7 presets, iter-98/139) — character between HH / mm / ss tokens. Applies to LOCAL + UTC time.                                                                                                                                                         |
| `SessionSignalWindow`       | NSString     | `"15min"`                | Menu (off / 5min / 15min / 30min / 60min — 5 presets, iter-126) — minute count that gates iter-123's PRE-MARKET (◐ amber) and iter-125's AFTER-HOURS (◒ rose) promotions. `off` disables both.                                                                                                                    |
| `UrgencyHorizon`            | NSString     | `"60min"`                | Menu (5min / 15min / 30min / 60min / 120min / 240min — 6 presets, iter-215) — horizon in minutes for iter-212's imminence-gradient. Below this distance from open/close, ACTIVE + NEXT countdowns + ACTIVE bar leading edge run green→red on a Weber-Fechner log scale.                                           |
| `UrgencyFlash`              | NSString     | `"normal"`               | Menu (off / subtle / normal / intense — 4 presets, iter-219) — 1Hz pulse intensity for iter-212's flash modulator. `off` disables the pulse entirely; subtle / normal / intense vary the dim-half alpha (0.80 / 0.45 / 0.15). Above the flash threshold the alpha is always full regardless of preset.            |
| `ShowFlags`                 | BOOL         | `YES`                    | Menu — country-flag emoji on ACTIVE/NEXT headers                                                                                                                                                                                                                                                                  |
| `ShowUTCReference`          | BOOL         | `YES`                    | Menu — inline `· HH:mm:ss UTC` on LOCAL row                                                                                                                                                                                                                                                                       |
| `ShowSkyState`              | BOOL         | `YES`                    | Menu — time-of-day glyph on LOCAL row; 5 phases (iter-112): 🌅 dawn [5,7) · ☀️ day [7,17) · 🌇 dusk [17,19) · 🌙 night [19,5)                                                                                                                                                                                     |
| `ShowDebugLabels`           | BOOL         | `NO`                     | Menu (iter-199) — corner-overlay canonical names `[LOCAL]` / `[ACTIVE]` / `[NEXT]` on each segment for precise feedback. NSToolTips remain active regardless. Registry: see Canonical UI Names table.                                                                                                             |
| `ShowProgressPercent`       | BOOL         | `NO`                     | Menu — inline `N%` next to ACTIVE progress bar (added iter-57)                                                                                                                                                                                                                                                    |
| `FontSize`                  | double       | `24.0`                   | Menu (15 options, 10–64 pt)                                                                                                                                                                                                                                                                                       |
| `ActiveFontSize`            | double       | `11.0`                   | Per-segment font size for ACTIVE                                                                                                                                                                                                                                                                                  |
| `NextFontSize`              | double       | `11.0`                   | Per-segment font size for NEXT                                                                                                                                                                                                                                                                                    |
| `FontWeight`                | NSString     | `"medium"`               | Menu (thin / regular / medium / semibold / bold / heavy / black — 7 presets, iter-129) — applies to ACTIVE + NEXT monospaced paths. LOCAL keeps iTerm2 / named-font weight.                                                                                                                                       |
| `ActiveWeight`              | NSString     | inherits `FontWeight`    | Per-segment weight override for ACTIVE (iter-89). Same 7 presets (iter-129). Empty/unset → falls back to `FontWeight`.                                                                                                                                                                                            |
| `NextWeight`                | NSString     | inherits `FontWeight`    | Per-segment weight override for NEXT (iter-89). Same 7 presets (iter-129). Empty/unset → falls back to `FontWeight`.                                                                                                                                                                                              |
| `LetterSpacing`             | NSString     | `"normal"`               | Menu (condensed / compact / tight / normal / airy / wide / extrawide — 7 presets, iter-94/137) — NSKernAttributeName on ACTIVE + NEXT attributed strings. LOCAL unaffected.                                                                                                                                       |
| `LineSpacing`               | NSString     | `"normal"`               | Menu (tight / snug / normal / loose / airy / spacious / cavernous — 7 presets, iter-95/138) — NSParagraphStyle.lineSpacing on ACTIVE + NEXT. LOCAL unaffected.                                                                                                                                                    |
| `LocalOpacity`              | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for LOCAL (iter-90). 0 or unset → falls back to `CanvasOpacity` → theme->alpha. Clamped to [0.10, 1.00].                                                                                                                                                                               |
| `ActiveOpacity`             | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for ACTIVE (iter-90). Same fallback chain.                                                                                                                                                                                                                                             |
| `NextOpacity`               | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for NEXT (iter-90). Same fallback chain.                                                                                                                                                                                                                                               |
| `ColorTheme`                | NSString     | `"terminal"`             | Legacy / fallback — superseded by per-segment themes                                                                                                                                                                                                                                                              |
| `LocalTheme`                | NSString     | `"terminal"`             | Per-segment theme for LOCAL                                                                                                                                                                                                                                                                                       |
| `ActiveTheme`               | NSString     | `"green_phosphor"`       | Per-segment theme for ACTIVE                                                                                                                                                                                                                                                                                      |
| `NextTheme`                 | NSString     | `"soft_glass"`           | Per-segment theme for NEXT                                                                                                                                                                                                                                                                                        |
| `CanvasOpacity`             | double       | `0.75`                   | Menu — segment backdrop alpha (Opaque 1.00 / Solid 0.90 / Glass 0.75 / …)                                                                                                                                                                                                                                         |
| `ActiveBarCells`            | int          | `40`                     | Menu — progress-bar cell count                                                                                                                                                                                                                                                                                    |
| `ProgressBarStyle`          | NSString     | `"dots"`                 | Menu (dots / blocks / thindots / dashes / arrows / chevrons / triangles / binary / braille / waves / hearts / stars / ribbon / diamond — 14 presets, iter-91/131/197)                                                                                                                                             |
| `NextItemCount`             | int          | `3`                      | Menu — max rows in NEXT TO OPEN (1 / 2 / 3 / 4 / 5 / 7 / 10 — 7 presets, iter-101)                                                                                                                                                                                                                                |
| `LayoutMode`                | NSString     | `"stacked-local-top"`    | Menu (stacked-local-top / stacked-local-bottom / triptych)                                                                                                                                                                                                                                                        |
| `SegmentGap`                | NSString     | `"normal"`               | Menu (flush 0pt / tight 2pt / snug 3pt / normal 4pt / airy 8pt / spacious 14pt / cavernous 24pt — 7 presets, iter-108)                                                                                                                                                                                            |
| `CornerStyle`               | NSString     | `"rounded"`              | Menu (sharp 0pt / hairline 1pt / micro 3pt / rounded 6pt / soft 10pt / squircle 14pt / jumbo 22pt / pill half-axis — 8 presets, iter-97)                                                                                                                                                                          |
| `ShadowStyle`               | NSString     | `"none"`                 | Menu (none / subtle / lifted / glow / crisp / plinth / halo / vignette / floating — 9 presets, iter-93/217)                                                                                                                                                                                                       |
| `Density`                   | NSString     | `"default"`              | Menu (ultracompact 4pt / compact 12pt / default 24pt / comfortable 36pt / spacious 48pt / cavernous 64pt — 6 presets, iter-99)                                                                                                                                                                                    |
| `SelectedMarket`            | NSString     | `"local"`                | Menu — only used in single-market mode                                                                                                                                                                                                                                                                            |
| `ActiveProfile`             | NSString     | `"Default"`              | Menu → Profile (Default / Day Trader / Night Owl / Minimalist / Researcher / Watch Party / Auction Watcher + user-saved) — 7 bundled starters (iter-140 added Auction Watcher, showcases iter-123/125/126 auction cluster)                                                                                        |
| `Profiles`                  | NSDictionary | starter bundle           | User-saved profile bundles — `{name → prefs-dict}`                                                                                                                                                                                                                                                                |
| _Quick Style_               | (action)     | n/a                      | Menu → Quick Style (Brutalist / Zen / Retro CRT / Executive / Neon / Hacker / Glacier / Midnight / Featherlight / Industrial / Trading Floor / Scholar / Samba / Borealis / Cinema / Levitation — 16 moods, iter-102/105/106/130/144/170/196/218) — writes a curated 10-key aesthetic bundle atomically. No pref. |
| `FontName`                  | NSString     | unset                    | Power-user override (PostScript name)                                                                                                                                                                                                                                                                             |
| `FloatingClockWindowFrame`  | NSString     | unset                    | Auto-saved on window move. `capture-clock.sh` reads this.                                                                                                                                                                                                                                                         |
| `FloatingClockScreenNumber` | NSNumber     | unset                    | Auto-saved on window move                                                                                                                                                                                                                                                                                         |
| `TextColor`                 | NSString     | unset                    | Legacy (pre-1.2.0). Migrated to `ColorTheme` on upgrade                                                                                                                                                                                                                                                           |
| `BackgroundAlpha`           | double       | unset                    | Legacy (pre-1.2.0). Alpha now `CanvasOpacity` or theme                                                                                                                                                                                                                                                            |

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

## Known limitations

- **Partial holiday awareness (NYSE + LSE + TSE + HKEX + XETRA + Euronext 2026, back-to-back chaining correct)**. iter-173 shipped `Sources/data/HolidayCalendar.{h,m}` + `FCIsMarketHoliday(mkt, date)` lookup (NYSE 2026); iter-174 wired it into `computeSessionState`; iter-175 refactored to per-market registry + LSE; iter-176 added TSE; iter-177 fixed advance-to-next-trading-day loop to skip _both_ weekends AND holidays (Dec 24 LSE after-close now chains Xmas + weekend + Boxing Day → Dec 29 Tue); iter-178 added HKEX (first lunar-calendar — LNY 3-day cluster, Buddha's Birthday, Dragon Boat, Mid-Autumn, Chung Yeung); iter-179 added XETRA + Euronext paired (both share the TARGET2 settlement-calendar 5 closures identically in 2026: Jan 1, Good Fri, Easter Mon, May 1, Dec 25 — one shared data array, two registry entries, zero duplication); iter-180 added ASX 2026 (first Oceania coverage — Australia Day, 4-day Easter long weekend incl. ASX-distinctive Easter Tuesday, King's Birthday, Boxing Day observed); iter-181 added TSX 2026 (Canadian — Family Day, Victoria Day, Canada Day, Civic Holiday, Canadian Thanksgiving in Oct, Boxing Day observed; TSX trades Easter Monday unlike most other non-US exchanges); iter-182 added SIX 2026 (Swiss — Berchtold's Day Jan 2, Ascension Day, Whit Monday, plus Dec 24 + Dec 31 as FULL closures unlike most exchanges that treat these as half-days; Swiss National Day Aug 1 Sat has no substitute); iter-183 added SSE 2026 (first Chinese calendar — two 7-day Golden Week clusters: Spring Festival Feb 17-23 and National Day Oct 1-7 + Qingming/Labour Day/Dragon Boat/Mid-Autumn; Dragon Boat Jun 19 and Mid-Autumn Sep 25 dates coincide with HKEX since both follow the lunar calendar); iter-184 added KRX 2026 (Korean — Seollal 3-day + Chuseok 3-day clusters incl. substitute holidays for weekend coincidences per Korean law, Buddha's Birthday obs, Children's Day, Hangeul Day, Liberation/Foundation/Independence Movement substitutes, Dec 31 year-end 폐장일; Sep 25 Chuseok Day 2 is a TRIPLE-market lunar coincidence with HKEX + SSE Mid-Autumn); iter-185 added NSE 2026 (Indian — most diverse mix); iter-186 added JSE (South African — Family Day / Easter Mon, Freedom Day, Youth Day, Women's Day Aug 10 Mon substitute, Heritage Day, Reconciliation, civic + Christian dates) + B3 (Brazilian — Carnival 2-day cluster Feb 16-17, Corpus Christi Easter+60d, Tiradentes, Independence, Aparecida, All Souls', Black Awareness, New Year + Christmas) in a single iter — completing the 14/14 holiday-awareness milestone. Caveats still in play: (1) early-close half-days — iter-188/189 built the HalfDayCalendar infrastructure (lookup + computeSessionState wiring); iter-190 extended to LSE + XETRA + Euronext (TARGET2 shared array); iter-191 added HKEX + TSX; iter-192 added JSE Dec 24 (12:00 SAST) + ASX Dec 24 (14:10 AEDT) — fills Africa + Oceania gap. Half-day coverage 6/14 → 8/14. 6 other exchanges' half-day data remains deferred (TSE 大発会/大納会 shortened sessions, SSE NYE Dec 31 shortened, B3 Ash Wed "opens late" inverse pattern, NSE Muhurat special evening session, KRX Dec 30 closing ceremony). Note: SIX Dec 24 + Dec 31 are FULL closures (iter-182) not half-days, no conflict; (2) China's "make-up trading Saturdays" (补班, working Saturdays designated to compensate for Golden Week closures) are NOT modelled — SSE trades on these days but the weekend branch in computeSessionState still reports CLOSED; (3) lunar-calendar dates for HKEX/SSE/KRX/NSE 2026 are fixture-locked best-effort — may shift 1 day if exchanges' official annual calendars differ.
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
