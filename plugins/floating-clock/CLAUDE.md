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

Tests live in `tests/test_session.m` — 31 fixtures covering
`computeSessionState` (session boundaries, weekend skip, lunch state,
progress math), the TZ-helper layer (DST branching for
BST/CEST/EDT/AEDT, UTC-offset formatting including Kolkata's UTC+5:30,
fullTzLabel composition), cityCode / flag emoji mapping coverage for
all 12 exchanges, starter-profile key-coverage invariants (caught
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
- **Color themes**: 25 preset bundles (each sets foreground, background, alpha atomically). Originals (10): Terminal, Amber CRT, Green Phosphor, Solarized Dark, Dracula, Nord, Gruvbox, Rose Pine, High Contrast, Soft Glass. iter-32 (+10): Synthwave, Monokai, Gotham, Ayu Mirage, Catppuccin, Tokyo Night, Kanagawa, Paper White, Sepia, Midnight Blue. iter-92 (+5): Oceanic Deep, Cherry Blossom, Espresso, Lavender Dream, Mint Dark. Menu items show 14×14 color swatches drawn inline via Core Graphics.
- **Market sessions** (when a non-local market is selected):
  - 12 major exchanges grouped by region (Americas / Europe / Asia / Oceania) — NYSE, TSX, LSE, Euronext, XETRA, SIX, TSE, HKEX, SSE, KRX, NSE, ASX
  - Time displayed in that exchange's local time via IANA `NSTimeZone` (DST-correct across hemispheres)
  - Second line shows state glyph + market code + progress bar + countdown:
    - `●` green: OPEN (regular session)
    - `◑` violet: LUNCH (TSE / HKEX / SSE only)
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

| Key                         | Type         | Default                  | Source                                                                                                                                   |
| --------------------------- | ------------ | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `DisplayMode`               | NSString     | `"three-segment"`        | Menu (three-segment / single-market / local-only)                                                                                        |
| `ShowSeconds`               | BOOL         | `YES`                    | Menu — strips `:ss` from all time displays when NO                                                                                       |
| `ShowDate`                  | BOOL         | `YES`                    | Menu                                                                                                                                     |
| `DateFormat`                | NSString     | `"short"`                | Menu (short / long / iso / numeric / weeknum / dayofyr)                                                                                  |
| `TimeFormat`                | NSString     | `"24h"`                  | Menu (24h / 12h) — only affects LOCAL; UTC always 24h canonical                                                                          |
| `TimeSeparator`             | NSString     | `"colon"`                | Menu (colon / middot / space / slash / dash) — character between HH / mm / ss tokens. Applies to LOCAL + UTC time (iter-98).             |
| `ShowFlags`                 | BOOL         | `YES`                    | Menu — country-flag emoji on ACTIVE/NEXT headers                                                                                         |
| `ShowUTCReference`          | BOOL         | `YES`                    | Menu — inline `· HH:mm:ss UTC` on LOCAL row                                                                                              |
| `ShowSkyState`              | BOOL         | `YES`                    | Menu — sun/moon glyph on LOCAL row (☀ hours 6–18, 🌙 otherwise)                                                                          |
| `ShowProgressPercent`       | BOOL         | `NO`                     | Menu — inline `N%` next to ACTIVE progress bar (added iter-57)                                                                           |
| `FontSize`                  | double       | `24.0`                   | Menu (15 options, 10–64 pt)                                                                                                              |
| `ActiveFontSize`            | double       | `11.0`                   | Per-segment font size for ACTIVE                                                                                                         |
| `NextFontSize`              | double       | `11.0`                   | Per-segment font size for NEXT                                                                                                           |
| `FontWeight`                | NSString     | `"medium"`               | Menu (regular / medium / semibold / bold / heavy) — applies to ACTIVE + NEXT monospaced paths. LOCAL keeps iTerm2 / named-font weight.   |
| `ActiveWeight`              | NSString     | inherits `FontWeight`    | Per-segment weight override for ACTIVE (iter-89). Same 5 presets. Empty/unset → falls back to `FontWeight`.                              |
| `NextWeight`                | NSString     | inherits `FontWeight`    | Per-segment weight override for NEXT (iter-89). Same 5 presets. Empty/unset → falls back to `FontWeight`.                                |
| `LetterSpacing`             | NSString     | `"normal"`               | Menu (compact / tight / normal / airy / wide) — NSKernAttributeName on ACTIVE + NEXT attributed strings (iter-94). LOCAL unaffected.     |
| `LineSpacing`               | NSString     | `"normal"`               | Menu (tight / snug / normal / loose / airy) — NSParagraphStyle.lineSpacing on ACTIVE + NEXT (iter-95). LOCAL unaffected.                 |
| `LocalOpacity`              | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for LOCAL (iter-90). 0 or unset → falls back to `CanvasOpacity` → theme->alpha. Clamped to [0.10, 1.00].      |
| `ActiveOpacity`             | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for ACTIVE (iter-90). Same fallback chain.                                                                    |
| `NextOpacity`               | double       | inherits `CanvasOpacity` | Per-segment canvas opacity for NEXT (iter-90). Same fallback chain.                                                                      |
| `ColorTheme`                | NSString     | `"terminal"`             | Legacy / fallback — superseded by per-segment themes                                                                                     |
| `LocalTheme`                | NSString     | `"terminal"`             | Per-segment theme for LOCAL                                                                                                              |
| `ActiveTheme`               | NSString     | `"green_phosphor"`       | Per-segment theme for ACTIVE                                                                                                             |
| `NextTheme`                 | NSString     | `"soft_glass"`           | Per-segment theme for NEXT                                                                                                               |
| `CanvasOpacity`             | double       | `0.75`                   | Menu — segment backdrop alpha (Opaque 1.00 / Solid 0.90 / Glass 0.75 / …)                                                                |
| `ActiveBarCells`            | int          | `40`                     | Menu — progress-bar cell count                                                                                                           |
| `ProgressBarStyle`          | NSString     | `"dots"`                 | Menu (dots / blocks / dashes / arrows / binary / braille / hearts / stars / ribbon / diamond — 10 presets, iter-91)                      |
| `NextItemCount`             | int          | `3`                      | Menu — max rows in NEXT TO OPEN                                                                                                          |
| `LayoutMode`                | NSString     | `"stacked-local-top"`    | Menu (stacked-local-top / stacked-local-bottom / triptych)                                                                               |
| `SegmentGap`                | NSString     | `"normal"`               | Menu (tight / snug / normal / airy / spacious)                                                                                           |
| `CornerStyle`               | NSString     | `"rounded"`              | Menu (sharp 0pt / hairline 1pt / micro 3pt / rounded 6pt / soft 10pt / squircle 14pt / jumbo 22pt / pill half-axis — 8 presets, iter-97) |
| `ShadowStyle`               | NSString     | `"none"`                 | Menu (none / subtle / lifted / glow / crisp / plinth / halo — 7 presets, iter-93)                                                        |
| `Density`                   | NSString     | `"default"`              | Menu (ultracompact 4pt / compact 12pt / default 24pt / comfortable 36pt / spacious 48pt / cavernous 64pt — 6 presets, iter-99)           |
| `SelectedMarket`            | NSString     | `"local"`                | Menu — only used in single-market mode                                                                                                   |
| `ActiveProfile`             | NSString     | `"Default"`              | Menu → Profile (Default / Day Trader / Night Owl / Minimalist / Watch Party + user-saved)                                                |
| `Profiles`                  | NSDictionary | starter bundle           | User-saved profile bundles — `{name → prefs-dict}`                                                                                       |
| `FontName`                  | NSString     | unset                    | Power-user override (PostScript name)                                                                                                    |
| `FloatingClockWindowFrame`  | NSString     | unset                    | Auto-saved on window move. `capture-clock.sh` reads this.                                                                                |
| `FloatingClockScreenNumber` | NSNumber     | unset                    | Auto-saved on window move                                                                                                                |
| `TextColor`                 | NSString     | unset                    | Legacy (pre-1.2.0). Migrated to `ColorTheme` on upgrade                                                                                  |
| `BackgroundAlpha`           | double       | unset                    | Legacy (pre-1.2.0). Alpha now `CanvasOpacity` or theme                                                                                   |

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
  segments/
    FloatingClockSegmentViews.{h,m}     Local/Active/Next/ClockContentView subclasses
  content/
    ActiveSegmentContentBuilder.{h,m}   live-markets rendering
    NextSegmentContentBuilder.{h,m}     next-to-open rendering
    SegmentHeaderRenderer.{h,m}         shared title/legend/hrule helper (iter-73)
    UrgencyColors.{h,m}                 shared urgency palette + thresholds (iter-73)
    LandingTimeFormatter.{h,m}          dual-zone time w/ weekday disambiguation (iter-74)
  data/
    ThemeCatalog.{h,m}                  10 theme presets + CG swatches
    MarketCatalog.{h,m}                 12-exchange registry + IANA helpers
    MarketSessionCalculator.{h,m}       computeSessionState, countdown fmts
  rendering/
    FontResolver.{h,m}                  iTerm2 → system monospaced cascade + FontWeight helpers (iter-88/89)
    SegmentOpacityResolver.{h,m}        3-tier canvas-opacity fallback (iter-90)
    AttributedStringLayoutMeasurer.{h,m} NSLayoutManager multi-line height
    VerticallyCenteredTextFieldCell.{h,m} cell that centers attributed text
  menu/
    FloatingClockPanel+MenuBuilder.{h,m} full preferences menu + shared helpers + Profile
    FloatingClockPanel+SegmentMenus.{h,m} LOCAL / ACTIVE / NEXT scoped menus (iter-87 split)
  actions/
    FloatingClockPanel+ActionHandlers.{h,m} every menu-item action target
  preferences/
    FloatingClockPanel+ProfileManagement.{h,m}  save/load/switch/delete
    FloatingClockStarterProfiles.{h,m}  6 bundled starters + profileManagedKeys
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

## Known limitations

- **No holiday awareness**. Session state assumes regular weekday hours. During exchange holidays (e.g. US Thanksgiving, Chinese Golden Week, Good Friday) the clock will show OPEN when the exchange is actually closed. Adding holiday awareness requires bundling annual data per exchange — deferred pending a maintenance plan for yearly tzdata-style refreshes.
- **No pre-open / after-hours auction window as a distinct state**. Exchanges with opening auctions (NYSE, TSE, LSE) and after-hours sessions (US equities 16:00–20:00 ET) currently show CLOSED outside the regular 09:30–16:00 window. Adding `kSessionPreMarket` / `kSessionAfterHours` is a Tier-2 enhancement.
- **Stacked-top/bottom layouts under LayoutMode have not been exercised in recent iterations**. The `triptych` mode is the primary code path. Stacked variants may have minor layout drift.

## Future Enhancements

### Near-term

- Holiday awareness (bundled annual JSON per exchange, refreshed yearly)
- Pre-open / after-hours auction as distinct states (with distinct glyphs + urgency tiers)
- System appearance (light/dark) auto-adjust of themes

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
