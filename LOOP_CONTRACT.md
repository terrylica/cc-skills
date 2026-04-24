---
name: floating-clock-v2-enhancements
version: 2
iteration: 5
status: ACTIVE
last_updated: 2026-04-24T01:30:00Z
exit_condition: "saturation OR user-stop OR max_iterations OR explicit DONE section"
max_iterations: 100
trigger: "/loop — reads this file verbatim each firing"
dispatch_policy:
  enabled: false
  require_experimental_teams: false
---

# Floating-Clock v2 Enhancements

**This file IS the /loop prompt.** It is versioned, self-updates each firing, and git history tells the evolution story.

## How to invoke this loop

Put this in `/loop` (or `ScheduleWakeup.prompt`):

```
/loop

Read and execute the latest autonomous work contract at:
  /Users/terryli/eon/cc-skills/LOOP_CONTRACT.md

Follow its instructions verbatim. That file self-updates; this trigger stays fixed.
```

---

## Core Directive (preserve verbatim across revisions)

Evolve the `plugins/floating-clock` marketplace plugin from v1 (a working always-on-top NSPanel clock with iTerm2 font + multi-monitor antifragility) into a fully interactive, user-configurable, easily-installable macOS utility. Hard constraint: **minimum memory and binary footprint at every step** — no SwiftUI runtime tax, no extraneous dependencies, menu-driven preferences over separate windows when possible. Every user-selectable setting must persist to NSUserDefaults. Every system touchpoint (file read/write, install path, framework link) must be documented in the plugin's CLAUDE.md so a first-time user knows exactly what the app does and doesn't do to their machine. Each iteration lands one atomic, user-visible improvement validated programmatically (leaks, build warnings, `validate-plugins.mjs`, idle CPU) before moving to the next.

---

## Execution Contract

Each firing must:

1. **Orient** — read Current State, recent commits, check any in-flight processes.
2. **Act** — execute the single highest-value next step from the Implementation Queue, AND if time remains, chain the next non-conflicting item.
3. **Revise** — rewrite Current State + append to Revision Log + update Queue.
4. **Persist** — atomic commit(s), then either chain in-turn (Tier 0) or exit if queue empty.

### Phase 1 — Orient

```bash
git -C /Users/terryli/eon/cc-skills log --oneline -5
git -C /Users/terryli/eon/cc-skills status --short
pgrep -fl "FloatingClock.app/Contents/MacOS/floating-clock" 2>/dev/null || echo "no clock running"
```

One-sentence assessment: _"Last firing landed X; next logical step is Y from Tier 1."_

### Phase 2 — Act

Priority order for this campaign:

1. **In-flight build**: if a `make all` or test is mid-run, wait for it (Monitor).
2. **Uncommitted work**: commit as atomic group before starting new work.
3. **Next Tier 1 item**: do the work, commit, run validation gauntlet.
4. **Continuation**: if primary ships cleanly and tokens remain, chain the next Tier 1 item in the same turn.

### Phase 3 — Revise

Rewrite **Current State**. Move completed items from Implementation Queue to a done-list under Current State. Append one line to Revision Log.

### Phase 4 — Persist and continue

- **Tier 0 (in-turn chaining)** is the default for this campaign. All work is local builds and file edits — no external blockers.
- Commit per-iteration with `loop(iter-<N>): <summary>`.
- Additional code commits use conventional commit scopes (`feat(floating-clock)`, `docs(floating-clock)`, `fix(floating-clock)`).
- When the Implementation Queue is empty, flip `status: DONE` in frontmatter and stop.

---

## Validation Gauntlet (run after each iteration's code change)

```bash
cd /Users/terryli/eon/cc-skills/plugins/floating-clock
make clean && make all 2>&1 | tee /tmp/clock-build.log
# Must: zero warnings, binary Mach-O arm64, bundled + signed

cd /Users/terryli/eon/cc-skills
bun scripts/validate-plugins.mjs 2>&1 | tail -3
# Must: exit 0

# Only if the iteration added runtime behavior:
pkill -f "FloatingClock.app/Contents/MacOS/floating-clock" 2>/dev/null
defaults delete com.terryli.floating-clock 2>/dev/null
./plugins/floating-clock/build/FloatingClock.app/Contents/MacOS/floating-clock &
sleep 1.5
leaks $(pgrep -f "FloatingClock.app/Contents/MacOS/floating-clock" | head -1) 2>&1 | grep -E "Physical footprint|leaks for"
# Must: 0 leaks, footprint under 20 MB
```

---

## Current State — ACTIVE (campaign v2 reopened)

**Prior campaign (iter-1 through iter-5) shipped v1.1.0 (v1 clock + context menu + icon + slash commands + touchpoints). Campaign reopened with 5 new items per user confirmation 2026-04-24.**

**Last completed iteration**: iter-5 — final validation gauntlet + leak fix + tick-clip fix.

**Full current apex**:

- Always-on-top borderless translucent NSPanel (alpha 0.32 default)
- iTerm2 font resolution cascade (4-tier fallback, current user font: JetBrainsMonoNLNFM-Regular)
- Bottom-center-of-primary default position (via `[NSScreen screens].firstObject`)
- Multi-monitor-aware persistence with antifragile fallback (runtime screen-unplug handler)
- Right-click context menu: Show Seconds/Date toggles + Time Format/Font Size/Opacity/Text Color submenus + Reset Position + About + Quit (⌘Q)
- All 6 user-visible settings persist to NSUserDefaults with sane defaults via `registerDefaults:`
- Dynamic date formatter adapts to user choices; window auto-resizes with ceilf() + generous padding to prevent seconds clip
- Self-generated app icon (1024×1024 Core Graphics glyph → iconutil ICNS); Spotlight / Launchpad / Finder index the app
- 4 Claude Code slash commands: `/floating-clock:install`, `:launch`, `:quit`, `:uninstall`
- Comprehensive Touchpoints manifest in CLAUDE.md — every file read/write, framework link, signing posture, network usage, launchd integration documented
- v1.1.0 in plugin.json

**Final metrics**:

- Binary (bundled + signed): 98 KB
- Icon file: 124 KB ICNS
- Physical footprint peak: 14.1 MB
- Idle CPU: 0.0%
- Leaks: 0 leaks / 0 bytes
- Build warnings: 0 with -Wall
- Source: 523 LoC (clock.m) + 172 LoC (gen-icon.m, build-time only)

**Active monitors**: none.

**Outstanding housekeeping**:

- [ ] iter-6 — Expand font sizes (15 options, hierarchical Small/Medium/Large/Huge submenus)
- [ ] iter-7 — 10 color-theme presets (fg + bg + alpha bundled; swatches in menu)
- [ ] iter-8 — Market-session Time Zone menu + 2-line clock display (12 exchanges + Local; IANA-TZ-backed)
- [ ] iter-9 — Session state visualization (● OPEN / ◐ PRE-OPEN / ◑ LUNCH / ○ CLOSED + 1/8-block progress bar + 2h17m countdown)
- [ ] iter-10 — Final validation gauntlet + v1.2.0 release bump

---

## Implementation Queue

### Tier 1 (start here — build atomically, validate each, commit)

- [x] **iter-1 — NSMenu context menu with persistent options** ✅ COMPLETE
      Implemented right-click context menu on the clock window with all required items and submenus.
      Validation results: - Build: 0 warnings, 96 KB binary, no errors - Plugin validator: PASSED (34 plugins valid) - Runtime: 14.4 MB peak footprint, 0 leaks - All menu methods compiled: buildMenu, refreshMenuChecks, applyDisplaySettings, all action handlers - NSUserDefaults keys registered: ShowSeconds, ShowDate, TimeFormat, FontSize, BackgroundAlpha, TextColor
      Commit: caeb743c `feat(floating-clock): right-click context menu with persistent user options`

- [x] **iter-2 — App icon for Spotlight / Launchpad / Alfred indexing** ✅ COMPLETE
      Core Graphics-drawn 1024×1024 glyph, bundled via `iconutil`. 124 KB ICNS. Spotlight-indexable.
      Commit: c2168d0f `feat(floating-clock): generate app icon at build time for Spotlight indexing`

- [x] ~~**iter-2 — App icon for Spotlight / Launchpad / Alfred indexing (original spec)**~~
      Generate a minimal icon at build time inside the Makefile — no external assets. Approach: draw a 1024×1024 SVG (clock face: dark rounded square background with a white circle outline and hour/minute hands at 10:10), convert via `rsvg-convert` or `qlmanage`+`sips`, pipe through `iconutil` to produce `Icon.icns`, bundle into `FloatingClock.app/Contents/Resources/`. If `rsvg-convert` unavailable, fall back to a pure-CoreGraphics one-shot Swift-less generator written in `Sources/gen-icon.m` (also compiled as a tiny helper binary run once at build time). Add `CFBundleIconFile = Icon` to Info.plist. Verify: `mdimport -d1 /Applications/FloatingClock.app` indexes it, `mdfind "kMDItemDisplayName == 'FloatingClock'"` returns the path.
      Validation: run Validation Gauntlet + `file build/FloatingClock.app/Contents/Resources/Icon.icns` shows `Mac OS X icon`.
      Commit: `feat(floating-clock): generate app icon at build time for Spotlight indexing`

- [x] **iter-3 — Claude Code slash commands (4 total)** ✅ COMPLETE
      `/floating-clock:install`, `:launch`, `:quit`, `:uninstall`. plugin.json bumped 1.0.0 → 1.1.0.
      Commit: c5a26ba3 `feat(floating-clock): install/launch/quit/uninstall slash commands + v1.1.0 bump`

- [x] ~~**iter-3 — Claude Code slash commands (original spec)**~~
      Add `plugins/floating-clock/commands/` with four command files: - `install.md` — runs `make all && cp -R build/FloatingClock.app /Applications/ && open /Applications/FloatingClock.app` - `launch.md` — runs `open /Applications/FloatingClock.app || ./build/FloatingClock.app` (prefers installed over local build) - `quit.md` — runs `pkill -f "FloatingClock.app/Contents/MacOS/floating-clock"` - `uninstall.md` — runs `pkill -f ... && rm -rf /Applications/FloatingClock.app && defaults delete com.terryli.floating-clock`
      Register the plugin's commands in `marketplace.json` if required by the validator, and ensure each command's SKILL-style frontmatter is correct. Match the pattern of existing plugins (inspect `plugins/mise/skills/` or `plugins/gmail-commander/commands/` for reference).
      Validation: `bun scripts/validate-plugins.mjs` must still exit 0. Verify the commands show up when the plugin is re-loaded by Claude Code (best-effort: spawn `claude --help` or check the plugin's SKILL list).
      Commit: `feat(floating-clock): add install/launch/quit/uninstall slash commands`

- [x] **iter-4 — Touchpoint manifest in CLAUDE.md** ✅ COMPLETE
      Added comprehensive Touchpoints table + Runtime Preferences table to plugins/floating-clock/CLAUDE.md.
      Commit: ea22a3b8 `docs(floating-clock): add Touchpoints manifest and Runtime Preferences table`

- [x] ~~**iter-4 — Touchpoint manifest (original spec)**~~
      Add a new **## Touchpoints** section to `plugins/floating-clock/CLAUDE.md` enumerating every system interaction with a 2-column table: `Kind | Details`. Cover: reads, writes, install path, build artifacts, bundles loaded (frameworks from `otool -L`), entitlements (none), network (none), launchd integration (none), Dock/menubar presence (LSUIElement hides from Dock). Include exact path(s) for every entry — no vague descriptions.
      Validation: `bun scripts/validate-plugins.mjs` exit 0. Lint-check the CLAUDE.md markdown (if the repo has a linter) or at minimum run `grep -c "Touchpoints" plugins/floating-clock/CLAUDE.md`.
      Commit: `docs(floating-clock): add Touchpoints section to CLAUDE.md`

- [x] **iter-5 — Final validation + leak fix + tick-clip fix** ✅ COMPLETE
      Gauntlet caught two issues: (1) 32-byte `_NSLocalEventObserver` leak from unretained ⌘Q monitor, (2) clock text clipped at the right edge because window padding matched label inset with zero slack. Both fixed.
      Commits: d89a4411 `fix(floating-clock): retain NSEvent monitor via ivar to prevent 32-byte leak`, 4ab429ca `fix(floating-clock): increase window padding + ceil() to prevent seconds clip`

- [x] ~~**iter-5 — Final validation (original spec)**~~
      Run the full Validation Gauntlet. Check: no regressions on leaks, RSS, footprint; binary under 100 KB bundled; all 4 slash commands discoverable; icon visible in Finder/Spotlight. Update the plugin's `plugin.json` version from `1.0.0` → `1.1.0`. Consider triggering `mise run release:full` to cut a new marketplace release (tier completion per Release Decision Rule).
      Commit: `chore(floating-clock): bump to 1.1.0 after iter-1 through iter-4`

### Campaign v2 (reopened 2026-04-24 — user confirmed design after 4-agent research)

**Design reference**: see `## Campaign v2 Design` section below for full data tables and composed-line examples.

- [ ] **iter-6 — Expand font sizes: 15 options in hierarchical submenus**
      Replace the flat 6-item Font Size submenu with a nested structure:
      `Font Size ▶
   Small  ▶  10 / 12 / 14 / 16
   Medium ▶  18 / 20 / 22 / 24
   Large  ▶  28 / 32 / 36 / 42
   Huge   ▶  48 / 56 / 64
`
      Add a generic helper `groupedSubmenu:action:groups:defaultsKey:` so iter-7 (themes) can also use nested groups.
      NSUserDefaults key `FontSize` still holds a single `double` — no schema change.
      Validation: gauntlet + pick 10pt and 64pt, confirm window resizes and text renders cleanly at both extremes.
      Commit: `feat(floating-clock): hierarchical font-size submenu with 15 options from 10 to 64pt`

- [x] **iter-7 — 10 color-theme presets with menu swatches** ✅ COMPLETE
      ClockTheme struct with id/display/fg/bg/alpha. 10 presets bundled. Core Graphics 14×14 swatches (bg rounded rect + fg inner) assigned to menu items on build. ColorTheme NSUserDefaults key, atomic fg/bg/alpha apply. Legacy TextColor migration (amber→amber_crt, green→green_phosphor, others→terminal). Removed Opacity submenu + setOpacity/setTextColor methods. Replaces flat 5-color submenu.
      Validation: fresh defaults→terminal, cycle dracula/gruvbox→persist, TextColor=amber migration→amber_crt. 0 leaks, 15MB peak, 80KB binary, 633 LoC, 0 warnings.
      Commit: 6064aeb3 `feat(floating-clock): 10 color-theme presets with inline CG swatches and atomic fg/bg/alpha`

- [ ] **iter-8 — Market-session Time Zone menu + clock in remote TZ**
      Add `Time Zone ▶` submenu with "Local Time" at top, then 4 region sub-submenus (Americas/Europe/Asia/Oceania) containing 12 exchanges. Data table (all IANA-TZ-backed):
      `Local Time         — system default
 NYSE/NASDAQ        America/New_York     09:30–16:00  (no lunch)
 TSX (Toronto)      America/Toronto      09:30–16:00  (no lunch)
 LSE (London)       Europe/London        08:00–16:30  (no lunch)
 Euronext (Paris)   Europe/Paris         09:00–17:30  (no lunch)
 XETRA (Frankfurt)  Europe/Berlin        09:00–17:30  (no lunch)
 SIX (Zurich)       Europe/Zurich        09:00–17:20  (no lunch)
 TSE (Tokyo)        Asia/Tokyo           09:00–15:30  (lunch 11:30–12:30)
 HKEX (Hong Kong)   Asia/Hong_Kong       09:30–16:00  (lunch 12:00–13:00)
 SSE (Shanghai)     Asia/Shanghai        09:30–14:57  (lunch 11:30–13:00)
 KRX (Seoul)        Asia/Seoul           09:00–15:30  (no lunch)
 NSE (Mumbai)       Asia/Kolkata         09:15–15:30  (no lunch)
 ASX (Sydney)       Australia/Sydney     10:00–16:00  (no lunch)
`
      Store as a static C struct array of 13 entries (Local + 12). Add new NSUserDefaults key `SelectedMarket` (NSString, default `"local"`).
      When a non-local market is selected, `tick` uses `NSDateFormatter.timeZone = [NSTimeZone timeZoneWithName:iana]`. Foundation handles DST automatically per hemisphere.
      This iter does NOT add the session-state line yet — that's iter-9. Time-display-only so iter-9 can focus on visuals.
      Validation: gauntlet + select Tokyo → clock shows JST (~9 hours ahead of PDT), select London → BST, kill+relaunch → selection persists.
      Commit: `feat(floating-clock): Time Zone menu with 12 major exchanges + IANA-backed conversion`

- [ ] **iter-9 — Session-state 2-line display with progress bar + countdown**
      When `SelectedMarket != "local"`, the window switches to 2-line mode:
      `14:37:21                       ← primary line, user font size, exchange local time
 ● NYSE ████████▊▒▒▒▒ 2h17m      ← secondary line, 11pt monospacedSystemFont
`
      Per R2/R4 research: - Progress bar: 12 characters using 1/8-width blocks `█▉▊▋▌▍▎▏` for filled portion, `░` or space for unfilled. Use NSAttributedString to color the filled portion in the theme's fg color and the unfilled portion in a dimmed gray (0.3 white). - State glyph + color (leading position): - `●` green: OPEN (regular session) - `◐` amber: PRE-OPEN (15 min before session, for exchanges with opening auctions — NYSE, TSE, LSE have them) - `◑` violet: LUNCH BREAK (TSE / HKEX / SSE only, during their lunch windows) - `○` gray: CLOSED (overnight, weekend) - Countdown format: `2h17m` when ≥1h remaining, `47m` when <1h, `5m32s` when <2m for tension. When CLOSED, show `○ NYSE CLOSED · opens in 14h23m` (or date format `opens Mon 09:30` if >99 hours out). - Lunch break counts as a distinct state (not CLOSED) — informative for traders per user confirmation.
      Add a new secondary `NSTextField *_sessionLabel` subview. `applyDisplaySettings` must measure both lines with `sizeWithAttributes:` and resize the window to `max(widths) + 32px × height_1 + height_2 + 28px`. Anchor resize at center so window doesn't drift.
      When market is "local", hide `_sessionLabel` (set `hidden = YES`) and use original 1-line sizing path.
      Session-state computation: new static fn `computeSessionState(const Market *m, NSDate *now)` returning `{state, progress_pct, secs_until_next_transition}`. Uses NSTimeZone + NSCalendar for conversions, runs each `tick` (once/second — cheap).
      Validation: gauntlet + cycle through NYSE (during or after session hours), TSE (verify lunch break state triggers at JST 11:30), weekend test (simulate via date stub if needed), verify progress bar sub-cell smoothness. All 4 state glyphs must be reachable and visually distinct.
      Commit: `feat(floating-clock): session-state line with progress bar, countdown, and 4-state glyph`

- [ ] **iter-10 — Final validation + v1.2.0 release bump**
      Full gauntlet. Bump plugin.json 1.1.0 → 1.2.0. Update CLAUDE.md: - Touchpoints table: add new NSUserDefaults keys (`ColorTheme`, `SelectedMarket`) - Runtime Preferences table: document all new options - Design section: document session-state semantics, lunch-break handling, progress bar encoding - Future Enhancements: holiday awareness (Tier 2), multi-market rotation (Tier 3)
      Commit: `chore(floating-clock): bump to 1.2.0 after iter-6 through iter-9`

### Tier 2 (post-MVP — nice-to-have)

- [ ] Holiday awareness for market sessions (bundled annual JSON/iCal, refreshed yearly)
- [ ] Pre-open auction window as distinct state (currently lumped into CLOSED for exchanges without pre-open)
- [ ] System appearance (light/dark) auto-adjust background + text color
- [ ] Weekday abbreviation (Mon/Tue/…) when Show Date is on
- [ ] Clickable calendar popup on left double-click

### Tier 3 (deferred)

- [ ] Multi-market rotation mode (cycle through 2-3 favorites every 10s)
- [ ] Settings export/import (JSON)
- [ ] User-definable theme bundles (add your own palette)

---

## Non-Obvious Learnings (preserve across revisions)

- **`[NSScreen mainScreen]` is unreliable for LSUIElement apps before a window is key.**
  Why: per Apple docs, mainScreen = "screen containing the window with keyboard focus". An accessory app's window isn't key at init time, so mainScreen is indeterminate on multi-monitor systems. Caught during v1 validation when default bottom-center landed on the external 4K instead of the primary.
  How to apply: use `[NSScreen screens].firstObject` (guaranteed primary with menu bar at origin (0,0)) whenever the code needs "the primary display" specifically.

- **iTerm2 stores fonts in `~/Library/Preferences/com.googlecode.iterm2.plist` under `New Bookmarks[i].Normal Font`.**
  Why: format is `"<PostScriptName> <size>"` (space-separated). Users may have multiple profiles; `Default Bookmark Guid` picks the active one.
  How to apply: always `isKindOfClass:` every dict lookup before using — plist can be malformed, missing, or have unexpected types.

- **User's preferred background alpha is 0.32** (more translucent than the 0.55 initial default).
  How to apply: this is the default in the v1 code; any new color picker should surface 0.32 as the initial value.

- **Footprint is a hard constraint, not a soft goal.**
  Why: user's explicit preference: "I will always opt for the lowest memory and resources footprint possible, no matter what it takes, even the most complicated method."
  How to apply: prefer NSMenu over NSWindow for preferences, prefer single-file Objective-C over multi-file, prefer compile-time constants over runtime registries, never introduce a Swift/SwiftUI dependency.

- **Validator runs on every commit via pre-commit hook.**
  How to apply: anything touching `plugins/` must keep `bun scripts/validate-plugins.mjs` green. Marketplace.json entry must match plugin.json. Skills (commands) have their own schema requirements — match existing plugin patterns.

---

## Revision Log (append-only, one line per firing)

- 2026-04-23 23:59 UTC — iter-0: scaffolded contract, queue seeded with 5 Tier 1 items covering the user-confirmed scope (context menu, icon, slash commands, touchpoint manifest, release). Next: iter-1 starts NSMenu implementation.
- 2026-04-24 00:05 UTC — iter-1: NSMenu context menu shipped (caeb743c). 6 persistent options + reset/about/quit. 521 LoC. Binary 96 KB. Next: iter-2 icon generation.
- 2026-04-24 00:20 UTC — iter-2: Core Graphics app icon shipped (c2168d0f). gen-icon helper + iconutil pipeline. 124 KB ICNS. Next: iter-3 slash commands.
- 2026-04-24 00:35 UTC — iter-3: Slash commands + v1.1.0 bump shipped (c5a26ba3). 4 skills. 203 skills total in validator. Next: iter-4 touchpoints doc.
- 2026-04-24 00:40 UTC — iter-4: Touchpoints manifest + Runtime Preferences table shipped (ea22a3b8). Every system interaction documented. Next: iter-5 final validation.
- 2026-04-24 00:45 UTC — iter-5: Gauntlet caught 32-byte \_NSLocalEventObserver leak (d89a4411) and seconds-clip visual regression (4ab429ca); both fixed. 0 leaks, 0 warnings, 14.1 MB peak, 0.0% idle CPU. Queue empty → status: DONE. Loop terminates.
- 2026-04-23 17:35 UTC — iter-1: right-click NSMenu context menu with 6 persistent options COMPLETE. 96KB binary, 521 LoC, 0 warnings, all validation passed. Commit caeb743c. Next: iter-2 starts icon generation.
- 2026-04-24 18:48 UTC — iter-7: 10-color-theme presets SHIPPED (6064aeb3). ClockTheme struct + swatches + atomic fg/bg/alpha + legacy TextColor migration. Terminal→terminal, amber→amber_crt, green→green_phosphor, others→terminal. Fresh defaults: terminal. Dracula/gruvbox cycles persist. 0 leaks, 15MB peak, 80KB binary, 633 LoC, 0 warnings. Next: iter-8 market-session timezone menu.
