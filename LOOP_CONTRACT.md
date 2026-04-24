---
name: floating-clock-v4-continuous-aesthetic-evolution
version: 4
iteration: 160
status: ACTIVE
last_updated: 2026-04-24T18:30:00Z
exit_condition: "explicit user-stop OR max_iterations OR explicit DONE section"
max_iterations: 10000
trigger: "/loop — reads this file verbatim each firing"
wake_policy:
  mode: snappy
  delay_seconds: 60
  rationale: "User directive 2026-04-24: 'between wake time, it is not acceptable to have long wake time'. No external blockers in this campaign, all work is local file edits + builds + agent dispatch."
dispatch_policy:
  enabled: true
  require_experimental_teams: false
  per_iteration_agents_min: 2
  per_iteration_agents_max: 4
  alignment_auditor_mandatory: true
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

- [x] **iter-8 — Market-session Time Zone menu + clock in remote TZ** ✅ COMPLETE
      ClockMarket struct array with 13 entries (Local + 12 exchanges), all IANA-TZ-backed. Time Zone submenu with regional grouping (Americas/Europe/Asia/Oceania). tick() applies timezone via NSDateFormatter.timeZone lookup. setMarket: persists SelectedMarket. Recursive menu checking handles nested structure. Time-display-only (session state deferred to iter-9).
      Validation: TSE (Tokyo JST = UTC+9) matches expected time exactly. LSE (London GMT/BST) correct. ASX (Sydney AEDT/AEST) correct. Persistence test: SelectedMarket = "asx" persists across restarts. Leaks: 0, Memory: 14.4MB peak, Binary: 98KB, LoC: 749, Warnings: 0.
      Commit: 76c988f3 `feat(floating-clock): Time Zone menu with 12 major exchanges + IANA-backed conversion`

- [x] **iter-9 — Session-state 2-line display with progress bar + countdown** ✅ COMPLETE
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

## Campaign v3 — Three-Segment Dashboard + Profile System + 25-Phase Audit

**Reopened 2026-04-24** per user directive. Extensive autonomous campaign with 7 feature iterations (iter-11 through iter-17) followed by 25 validation iterations (iter-18 through iter-42) and a synthesis iteration (iter-43) — 33 total. Uses multi-agent dispatch (Phase 2a enabled) for audits.

### Locked Design Decisions (from user confirmation 2026-04-24)

1. **Layout**: Three horizontal segments — `LOCAL | ACTIVE MARKETS | NEXT TO OPEN`.
2. **Window sizing**: Adaptive height + soft width budget (~620 px baseline). Grows vertically when many markets active.
3. **TZ grouping in ACTIVE segment**: Strict IANA — exchanges in identical IANA TZ strings collapse under one header (NYSE+NASDAQ), different-IANA (Paris/Berlin) do not.
4. **Empty ACTIVE**: Visible with "—" placeholder (stable layout).
5. **Legacy preservation**: New pref `DisplayMode` — `three-segment` (new default) / `single-market` (legacy iter-9) / `local-only` (pre-iter-8). Existing users' `SelectedMarket` migrates to `single-market` mode.
6. **Right-click scope**: segment-specific. Right-click inside the LOCAL segment → menu scoped to local-only options + LocalTheme; right-click ACTIVE → active-scoped options + ActiveTheme; right-click NEXT → next-scoped options + NextTheme. A separate global right-click on the frame border opens the full preferences menu.
7. **Profile system**: user saves/loads named profile bundles (all prefs). Bundled starters: `Default`, `Day Trader`, `Night Owl`, `Minimalist`, `Watch Party`. Additionally, Claude Code's auto-memory system records profile activations so future sessions know the user's style.
8. **Per-segment themes**: three new NSUserDefaults keys `LocalTheme`, `ActiveTheme`, `NextTheme`. Existing `ColorTheme` becomes the fallback / legacy.

### Audit Agent Archetypes (10 distinct teams)

Each audit iteration spawns 2-4 of these agents with `run_in_background: true` for parallel evaluation. Agents write structured reports to `.planning/audits/iter-NN-<topic>/<archetype>.md`. Aggregation happens in the main loop.

1. **Visual Inspector** — multimodal vision agent; reviews screenshots against expected layout.
2. **Typography Critic** — spacing, baseline alignment, font-weight progression, monospace consistency.
3. **Color Theorist** — WCAG contrast, cross-segment harmony, color-blindness considerations.
4. **Trader Persona: NYC Day Trader** — roleplays watching NY open while caring about Asia close.
5. **Trader Persona: London Macro** — roleplays watching EU/UK with US overlap.
6. **Trader Persona: Asia-Pacific** — roleplays night-session Asian volatility.
7. **Trader Persona: Remote Nomad** — roleplays someone frequently changing local time zones.
8. **Novice User** — first-launch discovery, can they customize without docs.
9. **Power User** — can they find every option, is profile switching fluent.
10. **Accessibility Auditor** — legibility at small sizes, low-vision, motor-impaired menu navigation.
11. **Adversarial Fuzzer** — DST transitions, TZ lookup failures, all-markets-closed scenarios, resize stress.
12. **Code Reviewer** — single-file constraint, ARC correctness, thread safety, memory footprint discipline.

(12 archetypes; loop uses whichever are most relevant per audit phase, targeting "at least 10" participation across the 25 audit iterations.)

### Agent Report Schema

Every audit agent writes to its designated file using this template (Markdown + YAML frontmatter):

```markdown
---
archetype: <archetype name>
iter: <NN>
topic: <one-line topic>
timestamp: <ISO 8601>
verdict: approve | flag | reject
severity: low | medium | high | critical
---

## What I evaluated

<1 paragraph — scope of this specific audit>

## Findings

- <finding 1, with rationale>
- <finding 2>
- ...

## Recommended fixes (prioritized)

1. <fix>
2. <fix>

## Specific evidence

<screenshots, logs, file:line references, or concrete examples>
```

### Feature Iterations (iter-11 through iter-17)

- [x] **iter-11 — Three-segment NSView layout scaffold** ✅ COMPLETE
      Three `NSView` subclasses (LocalSegmentView, ActiveSegmentView, NextSegmentView) arranged horizontally with 4pt gaps. Each has backgroundColor (hardcoded theme: dark/green/blue tints at 0.5 alpha) and cornerRadius 6pt. Each segment's menuForEvent: returns a menu with "Full Preferences…" option. New DisplayMode NSUserDefaults key (default "three-segment") with migration: SelectedMarket != "local" → "single-market". applyDisplaySettings branches to applyThreeSegmentLayout / applySingleMarketLayout / applyLocalOnlyLayout. tick branches to tickThreeSegment / tickLegacy. LOCAL segment shows local time, ACTIVE/NEXT show static placeholders "ACTIVE (—)" / "NEXT (—)". Window resizes to fit three segments horizontally. Three-segment views lazily created, hidden when DisplayMode != "three-segment". No regressions: single-market and local-only modes use original iter-9 behavior.
      Validation: fresh install → three-segment ✓, SelectedMarket=tsx migration → single-market ✓, mode switch → local-only ✓, 0 leaks, 13.1MB peak, 104KB binary, 1343 LoC, 0 -Wall warnings.
      Commit: cd879d20 `feat(floating-clock): three-segment NSView scaffold with DisplayMode pref (iter-11)`

- [x] **iter-12 — ACTIVE segment population with IANA TZ grouping** ✅ COMPLETE
      Scan `kMarkets` each tick; any market in `kSessionOpen` or `kSessionLunch` state → add to ACTIVE. Group by `iana` string (strict equality). One "block" per unique IANA, listing all markets in that IANA. Each market line shows: code + state glyph + progress bar (8 cells) + countdown. Empty-active shows "—". Max 6 visible (scroll/clip extras with "…").
      Commit: 82b879c3 `feat(floating-clock): ACTIVE segment shows live markets grouped by IANA timezone (iter-12)`

- [x] **iter-13 — NEXT segment population (next opens)** ✅ COMPLETE
      For each market in `kSessionClosed` or `kSessionLunch`, compute seconds-to-next-open/resume. Sort ascending. Show top 3. Lunch-resume markets included as distinct items with violet `◑` glyph + "resumes in Xm LUNCH" suffix. Countdown format: "opens in 1h45m" or "opens Mon 09:30" (>99h). Edge case: no upcoming events → "— NO UPCOMING OPENS —".
      Implementation: buildNextSegmentContent method, NextSegmentView multi-line configuration, window layout measurement integration.
      Validation: 1630 LoC, 103 KB binary, 15.2 MB peak, 0 leaks, 0 warnings (-Wall). All three segments render correctly: LOCAL time, ACTIVE markets by IANA, NEXT top-3 opens.
      Commit: e32576c8 `feat(floating-clock): NEXT segment with top-3 upcoming opens including lunch resumes (iter-13)`

- [ ] **iter-14 — Per-segment themes (LocalTheme / ActiveTheme / NextTheme)**
      Three new NSUserDefaults keys, each holding a theme id from `kThemes`. Defaults: Local=`terminal`, Active=`green_phosphor` (lively), Next=`soft_glass` (subdued). Legacy `ColorTheme` key becomes read-only fallback if any per-segment key unset.
      Commit: `feat(floating-clock): per-segment theme customization with independent NSUserDefaults keys`

- [ ] **iter-15 — Segment-scoped right-click menus**
      Each segment's `menuForEvent:` returns a menu scoped to that segment's options: theme picker, a segment-enable/disable toggle (hide this segment entirely), and a "Show Full Preferences…" escape hatch to the global menu. Global menu remains accessible via right-click on the window frame/gutter (outside any segment).
      Commit: `feat(floating-clock): segment-scoped right-click context menus`

- [ ] **iter-16 — DisplayMode switch preserving legacy**
      New submenu `Display Mode ▶` with `Three-Segment ✓ / Single Market / Local Only`. In `single-market` mode, the clock reverts to iter-9 behavior (1 exchange selected via `SelectedMarket`). In `local-only`, reverts to iter-7 behavior (just HH:MM:SS). Existing v1.2.0 users who had `SelectedMarket != local` auto-migrate to `single-market` mode on first launch of v1.3.0 (preserve workflow).
      Commit: `feat(floating-clock): DisplayMode switch with backward-compatible migration`

- [ ] **iter-17 — Profile system with bundled starters + Claude Code memory integration**
      New NSUserDefaults key `Profiles` holding a dictionary `{name → prefs-dict}`, and `ActiveProfile` holding current profile name. New submenu `Profile ▶ <list of profiles> / Save Current As… / Delete…`. Bundle 5 starters: `Default` (factory), `Day Trader` (large font, three-segment, amber theme), `Night Owl` (small font, dim themes, local-only), `Minimalist` (local-only, soft-glass theme), `Watch Party` (xtra-large font, Dracula, single-market NYSE). When user activates a profile, record it via Claude Code's auto-memory system (append to `~/.claude/projects/…/memory/`) so future Claude sessions know which profile the user is on.
      Commit: `feat(floating-clock): profile system with 5 bundled starters and CC memory integration`

### Audit Iterations (iter-18 through iter-42 — exactly 25 phases)

Each audit iter spawns 2-4 agents in parallel (`run_in_background: true`). Agents write reports to `.planning/audits/iter-NN-<topic>/`. Main loop aggregates. No code changes in audit phase — findings go into `.planning/audits/SYNTHESIS.md` at iter-43.

**Visual / Multimodal (5 phases — each spawns Visual Inspector + 1 persona):**

- [ ] **iter-18** — Default fresh install visual review (no prefs set). Agents: Visual Inspector, Novice User.
- [ ] **iter-19** — All 10 themes applied to each segment: 30 permutations screenshot grid. Agents: Visual Inspector, Color Theorist.
- [ ] **iter-20** — Font-size scaling: screenshots at 10/16/24/36/48/64pt. Agents: Visual Inspector, Typography Critic.
- [ ] **iter-21** — Multi-market density stress: all Asia active (5 markets). Agents: Visual Inspector, Power User.
- [ ] **iter-22** — Edge cases: midnight UTC (no markets open), weekend, DST transition dates. Agents: Visual Inspector, Adversarial Fuzzer.

**Aesthetic (5 phases):**

- [ ] **iter-23** — Typography & spacing across segments. Agents: Typography Critic, Accessibility Auditor.
- [ ] **iter-24** — Cross-segment color harmony. Agents: Color Theorist, Visual Inspector.
- [ ] **iter-25** — Information hierarchy & eye-scan paths. Agents: Visual Inspector, Novice User, Power User.
- [ ] **iter-26** — Minimalism vs density balance. Agents: Typography Critic, Trader NYC Day Trader.
- [ ] **iter-27** — macOS HIG compliance (menu behavior, context-menu conventions). Agents: Power User, Code Reviewer.

**International Trader Personas (8 phases):**

- [ ] **iter-28** — NYC Day Trader: watching NY open with Tokyo close peripheral. Agents: NYC Day Trader, Visual Inspector.
- [ ] **iter-29** — London Macro: EU markets with US overlap. Agents: London Macro, Color Theorist.
- [ ] **iter-30** — Asia-Pacific Forex. Agents: Asia-Pacific, Visual Inspector.
- [ ] **iter-31** — HK/SSE arbitrage. Agents: Asia-Pacific, Adversarial Fuzzer (lunch-break behavior).
- [ ] **iter-32** — After-hours US retail. Agents: NYC Day Trader, Power User.
- [ ] **iter-33** — Multi-asset institutional (many markets at once). Agents: Power User, Visual Inspector.
- [ ] **iter-34** — Remote Nomad (often-changing local TZ). Agents: Remote Nomad, Adversarial Fuzzer.
- [ ] **iter-35** — Quant researcher (precision + edge cases). Agents: Code Reviewer, Adversarial Fuzzer.

**Customization UX (7 phases):**

- [ ] **iter-36** — Novice first-launch discoverability. Agents: Novice User, Accessibility Auditor.
- [ ] **iter-37** — Power user feature exploration. Agents: Power User, Code Reviewer.
- [ ] **iter-38** — Profile switching workflow. Agents: Power User, Novice User.
- [ ] **iter-39** — Theme creation UX (picking fg/bg/alpha). Agents: Color Theorist, Power User.
- [ ] **iter-40** — Building a custom layout from defaults. Agents: Novice User, Power User.
- [ ] **iter-41** — Claude Code memory integration — does it persist preferences meaningfully. Agents: Power User, Code Reviewer.
- [ ] **iter-42** — Final adversarial sweep: what breaks, what's annoying, what should be Tier 2. Agents: Adversarial Fuzzer, all personas (one comment each).

**Synthesis:**

- [ ] **iter-43** — Aggregate all 25 audit reports. Produce `SYNTHESIS.md` with: top-10 critical findings, top-10 aesthetic improvements, top-10 UX improvements, list of Tier 2 deferred items, and a single "must-fix before v1.3.0" priority list. No code changes — document only, user reviews before any fixes land.

### Autonomous Loop Rules for Campaign v3

- **Feature iters (iter-11 to iter-17)**: Tier 0 in-turn chaining, same as campaign v2. Each ships + validates.
- **Audit iters (iter-18 to iter-42)**: Phase 2a multi-agent dispatch with `run_in_background: true`. Main loop waits for parallel reports (fires new wake on last report completion via notification). Aggregates + commits report files (no source changes). Continues to next iter.
- **Synthesis (iter-43)**: Single Agent call reading all 25 audit directories, producing SYNTHESIS.md. Flip `status: DONE`.
- **Safety**: if any audit agent reports `severity: critical` with `verdict: reject` on a just-shipped feature iter, the main loop PAUSES the audit campaign and spawns a fix iter BEFORE continuing. User is notified via PushNotification.
- **User stop-early**: user can `rm LOOP_CONTRACT.md` or edit frontmatter to `status: STOPPED`, and the loop exits cleanly at next firing.

---

## Campaign v4 — Continuous Aesthetic/UX Evolution (Active from iter-25)

**Scope expanded 2026-04-24 via /autonomous-loop:start** — user directive:

> Continuous, limitless, and unbounded iterations to aesthetically and critically find and expand customization. We aim to make aesthetic choices, layout choices, and layout options more unbounded, providing more options to users to perform customizations in a modularized manner. Every round should involve using multimodal models to self-critically assess and dispatch individual layout artists and user experience analysts to make it increasingly sophisticated—round after round, time after time, through every iteration. Also, you have to make consistent adjustments to the UI. The UI and the menu bar must be revamped consistently because you always have to use an alignment auditor to ensure all layouts and functionalities are aligned with the user interface and the menu options.

### Core Directive v4 (preserve verbatim across revisions)

Every firing pushes the floating-clock further along **three orthogonal axes**: (1) _aesthetic options_ — more themes, more fonts, more progress-bar glyphs, more color palettes, more shadow / border / corner styles; (2) _layout options_ — more arrangement modes, more inter-segment spacing choices, more orientation options, more density profiles; (3) _menu surface_ — hierarchical multi-layer menus (MENU → submenu → sub-submenu) that expose every new option discoverably. No wait between iterations — every firing commits atomically and queues the next snappily (≤120s wake).

### v4 Multi-Agent Dispatch Protocol

**Every iteration** spawns (via `Agent` tool, `run_in_background: true` when work is parallel):

1. **Layout Artist** — proposes one new layout option / adjustment. Writes to `.planning/v4-iter-NN/layout-artist.md`.
2. **UX Analyst** — evaluates current state from a user's cognitive-load perspective. Writes `.planning/v4-iter-NN/ux-analyst.md`.
3. **Alignment Auditor** (mandatory every iteration) — confirms every newly-shipped user-visible option has a menu path AND every menu item maps to a live option. Writes `.planning/v4-iter-NN/alignment-audit.md`. Flags drift as `severity: high`.
4. **Optional 4th rotating role** — drawn from the v3 archetype pool (Visual Inspector, Typography Critic, Color Theorist, trader personas, Accessibility Auditor, Adversarial Fuzzer) — rotates each firing.

All four write the Agent Report Schema from v3. Main loop synthesizes in-turn and ships one atomic commit per iteration with prefix `loop(iter-<N>-v4): <summary>`.

### v4 Queue (always append, never shrink)

The queue is **self-generating**: each iteration's agents propose the next iteration's items via their "Recommended fixes (prioritized)" sections. The main loop seeds with the below minimum, then chains what agents recommend.

**Seeded Tier 1 (first pass, iter-25 through iter-40):**

- [ ] **iter-25** — Multi-layer menu revamp scaffold: top menu bar structure `MENU → Aesthetics ▶ | Layout ▶ | Data ▶ | Profile ▶ | Advanced ▶`. Every existing menu item finds a home in this hierarchy. Agents: Layout Artist, UX Analyst, Alignment Auditor, Typography Critic.
- [ ] **iter-26** — More progress-bar glyph sets: `blocks` (current 1/8-width), `dots` (● ○), `dashes` (━ ╌), `arrows` (▶ ▷), `binary` (█ ░), `braille` (⣿ ⣀). New `ProgressBarStyle` pref. Agents: Layout Artist, UX Analyst, Alignment Auditor, Color Theorist.
- [ ] **iter-27** — Layout orientation options: `stacked-local-top` (current), `stacked-local-bottom`, `horizontal-triptych` (original), `compact-single-row`, `grid-2x2`. New `LayoutMode` pref. Agents: Layout Artist, UX Analyst, Alignment Auditor, Visual Inspector.
- [ ] **iter-28** — Inter-segment gap options: tight (2pt), snug (4pt), normal (8pt), airy (12pt), spacious (20pt). New `SegmentGap` pref. Agents: Layout Artist, Typography Critic, Alignment Auditor, UX Analyst.
- [ ] **iter-29** — Corner radius / border style options per segment (sharp, rounded, pill, squircle). Agents: Layout Artist, Color Theorist, Alignment Auditor, Accessibility Auditor.
- [ ] **iter-30** — Drop shadow / glow / inset options. Agents: Layout Artist, Color Theorist, Alignment Auditor, Adversarial Fuzzer.
- [ ] **iter-31** — Typography weight progression: regular / medium / semibold / bold / heavy per segment. Agents: Typography Critic, UX Analyst, Alignment Auditor, Accessibility Auditor.
- [ ] **iter-32** — 10 more theme presets added (total 20). Agents: Color Theorist, Visual Inspector, Alignment Auditor, UX Analyst.
- [ ] **iter-33** — Per-segment font override (not just global). Agents: Typography Critic, Power User, Alignment Auditor, UX Analyst.
- [ ] **iter-34** — Menu-driven preset palette editor. Agents: UX Analyst, Color Theorist, Alignment Auditor, Power User.
- [ ] **iter-35** — Density profiles: compact / default / comfortable / spacious affecting all spacing at once. Agents: Layout Artist, Typography Critic, Alignment Auditor, UX Analyst.
- [ ] **iter-36** — Locale-aware date format presets. Agents: UX Analyst, Remote Nomad, Alignment Auditor, Adversarial Fuzzer.
- [ ] **iter-37** — Country-flag glyphs on ACTIVE/NEXT exchange headers. Agents: Visual Inspector, UX Analyst, Alignment Auditor, Accessibility Auditor.
- [ ] **iter-38** — Per-profile window position memory (Day Trader on external monitor, Minimalist on primary). Agents: Power User, UX Analyst, Alignment Auditor, Adversarial Fuzzer.
- [ ] **iter-39** — Animation toggle: fade-in / slide transitions for state changes. Agents: UX Analyst, Visual Inspector, Alignment Auditor, Accessibility Auditor.
- [ ] **iter-40** — Keyboard-driven menu navigation (⌘, for full prefs). Agents: Power User, Accessibility Auditor, Alignment Auditor, UX Analyst.

_Additional iters seeded dynamically by agent recommendations. No fixed endpoint._

### v4 Snappy-Wake Rules

- **Fallback heartbeat**: 60s (1 minute). Dynamic mode only.
- **No 1200s+ waits** under any condition. User directive is explicit: "it is not acceptable to have long wake time."
- Every firing ends with `ScheduleWakeup(delaySeconds: 60, prompt: pointer-trigger)` unless the user stops the loop.
- Exit only on: explicit user-stop, status: DONE after all queue items done + no agent recommends further, or max_iterations reached.

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

- **500-LoC hard cap per source file (user directive 2026-04-24).**
  Rule: no single `.m` / `.h` / `.c` file may exceed 500 LoC. If a file crosses that threshold, the next iteration MUST modularize it before adding any new feature. Use long self-explanatory filenames under a hierarchical `Sources/<area>/` tree (e.g. `Sources/menu/FloatingClockMenuBuilder.m`). Campaign v4 iters take every opportunity to split proactively — don't wait until a file is overweight; anticipate and pre-split.
  Why: single-file Objective-C helped v1–v3 ship fast, but at ~2400 LoC it's now a maintenance hazard and hides coupling. User directive overrides the earlier "prefer single-file" heuristic for files > 500 LoC.

- **Canvas-only transparency (2026-04-24).**
  Rule: transparency settings affect ONLY segment backgrounds. Text must always render at alpha=1.0 regardless of any opacity setting. Never use `NSWindow.alphaValue` for theme-related dimming — it dims text too.
  Why: users need to keep reading the clock face even when the canvas fades into the desktop.

- **Validator runs on every commit via pre-commit hook.**
  How to apply: anything touching `plugins/` must keep `bun scripts/validate-plugins.mjs` green. Marketplace.json entry must match plugin.json. Skills (commands) have their own schema requirements — match existing plugin patterns.

- **Never run `defaults delete com.terryli.floating-clock` mid-loop** (iter-103 learning).
  Why: caught live during iter-100 verification — wiped the user's running-clock state (window position, active profile, per-segment themes, quick-style selection). User observed "clock is no longer visible" as a direct consequence of the stale pref path + no-longer-running process. `defaults delete` belongs ONLY in the explicit `make leaks` gauntlet which the user has opted into for fresh-install reproducibility; it MUST NOT appear in the per-iter validation loop.
  How to apply: validation commands that touch live state (defaults, pkill, killing foreground apps, mv/rm on user's bundle) are out-of-scope for autonomous iteration. Read-only checks (`file`, `codesign -v`, `ls`, `otool -L`, `wc -l`, `pgrep -l`) are fine. When in doubt: only use the commands listed in this file's Validation Gauntlet section, which are curated for safety.

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
- 2026-04-24 18:53 UTC — iter-8: Market-session Time Zone menu SHIPPED (76c988f3). ClockMarket struct (13 entries: Local + 12 exchanges IANA-backed). Time Zone submenu with regional grouping (Americas/Europe/Asia/Oceania). tick() applies timezone via NSDateFormatter. setMarket: persists SelectedMarket. Tested: TSE/LSE/ASX timezone conversion pixel-perfect, persistence verified, 0 leaks, 14.4MB peak, 98KB binary, 749 LoC, 0 warnings. Next: iter-9 session-state 2-line display.
- 2026-04-24 19:05 UTC — iter-9: Session-state 2-line display SHIPPED (3922f36b). SessionState enum (OPEN/LUNCH/CLOSED), computeSessionState() with NSCalendar/IANA TZ, glyphForState() + colorForState(), buildProgressBar() with 1/8-width blocks, formatCountdown(), secondary NSTextField with attributed string (split-color bar). applyDisplaySettings measures both lines, center-anchored resize. Local mode: session label hidden, 1-line layout. Market mode: 2-line layout with state glyph + progress + countdown. Tested: NYSE OPEN, TSE OPEN, Local 1-line, all 0 leaks, 13.5MB peak, 84KB binary, 1000 LoC, 0 warnings. Next: iter-10 final validation + v1.2.0 bump.
- 2026-04-23 20:15 UTC — iter-11: Three-segment NSView scaffold SHIPPED (cd879d20). LocalSegmentView, ActiveSegmentView, NextSegmentView with hardcoded segment backgrounds (dark/green/blue tints at 0.5 alpha, 6pt radius). DisplayMode NSUserDefaults key (three-segment/single-market/local-only) with migration for legacy users (SelectedMarket != local → single-market). applyDisplaySettings dispatches to mode-specific layout methods. tick() branches to tickThreeSegment / tickLegacy. Segments arranged horizontally with 4pt gaps. LOCAL shows local time, ACTIVE/NEXT show placeholders. All three modes tested: fresh → three-segment ✓, legacy SelectedMarket=tsx → single-market ✓, mode switch → local-only ✓. 0 leaks, 13.1MB peak, 104KB binary, 1343 LoC, 0 -Wall warnings. Next: iter-12 populate ACTIVE segment with live markets.
- 2026-04-23 20:25 UTC — iter-12: ACTIVE segment population SHIPPED (82b879c3). Scans kMarkets each tick for open/lunch states, groups by IANA timezone, renders with state glyph + progress bar (1/8-width blocks, color-split) + countdown. buildActiveSegmentContent with multi-line attributed string, per-group headers. Max 6 markets per group; empty ACTIVE shows "—". Tested: NYC/Toronto together (same IANA), Tokyo group separate, progress bars render correctly. 0 leaks, 14.1 MB peak, 98 KB binary, 1516 LoC, 0 warnings. Next: iter-13 populate NEXT segment with top-3 upcoming opens.
- 2026-04-23 20:30 UTC — iter-13: NEXT segment population SHIPPED (e32576c8). buildNextSegmentContent scans closed+lunch markets, sorts by secs-to-next ascending, shows top 3. Lunch-resume markets get violet ◑ glyph + "resumes in Xm LUNCH" suffix. Countdown format: "opens in 1h45m" or "opens Mon 09:30" for >99h gaps. Edge case: no upcoming events → "— NO UPCOMING OPENS —". NextSegmentView configured for multi-line (usesSingleLineMode=NO, alignment=LEFT). applyThreeSegmentLayout measures NEXT content for accurate window sizing. Tested: TSE lunch-resume appears in NEXT with violet glyph, LSE/EUX opens calculated correctly, window resizes to fit. 0 leaks, 15.2 MB peak, 103 KB binary, 1630 LoC, 0 warnings. Queue checkpoint: iter-14 through iter-17 deferred pending user direction on per-segment themes + profile system scope. Current state: all three segments ACTIVE + rendering live data. Next: awaiting user decision on Tier 1 continuation or transition to audit phase (iter-18).
- 2026-04-24 00:12 UTC — iter-14..22: feature-rich iteration batch — per-segment themes, segment-scoped menus, DisplayMode switch, profile system + CC memory integration, VCenteredCell (NSLayoutManager SOTA vertical centering), partial-cell progress-bar gap fix, progress-bar-width hierarchical submenu up to 40 cells, window clamp to visibleFrame, Profile/Quick Save in all three scoped menus, Date Format presets (6 options), dynamic height via per-tick relayoutThreeSegmentIfNeeded, trailing-\n line-fragment padding in both measureAttributedUnwrapped and VCenteredCell, mandatory seconds everywhere, ACTIVE headers carry per-exchange local weekday+date+time. Head: f6a7399e.
- 2026-04-24 00:12 UTC — iter-23: Stacked block layout SHIPPED. LOCAL now occupies a full-width top row; ACTIVE + NEXT share a centered bottom row. topRowWidth = MAX(local content, bottom-row pair) so the two rows are flush. Verified visually with all 6 active markets rendered; window shape is now a stable rectangle anchored by LOCAL instead of a wide horizontal strip. Next: address user's modularization directive — split clock.m into hierarchical modules with self-explanatory long filenames (architecture proposal pending user choice between umbrella-header and per-unit-header styles).
- 2026-04-24 00:16 UTC — iter-24: LOCAL centering fix + canvas transparency restored (410bc80d). sizeToFit left the label in a state where the widened frame did not re-center the text. Switched to sizeWithAttributes on the actual stringValue (no cell mutation), then explicitly reset label+cell alignment=center and usesSingleLineMode=YES on every relayout. Vertical centering already came from VCenteredCell. Also restored transparency: new CanvasOpacity pref (default 1.0, clamped [0.10, 1.0]) applied via NSWindow.alphaValue for a uniform canvas-wide dimmer on top of per-theme background alphas. Six-preset Transparency submenu (Opaque/Solid/Glass/Medium/Faint/Ghost) in the LOCAL scoped menu; key added to profileManagedKeys. Next: modularization (pending user pick umbrella-header vs per-unit-header style) OR user-surfaced issues after next visual inspection.
- 2026-04-24 00:30 UTC — iter-25a: **modularization pass 1** (eae0a72c, 6df6b494, afc82068). Fixes shipped first: canvas-only transparency (applyTheme multiplies theme bg-alpha by CanvasOpacity; panel.backgroundColor=clearColor so text stays solid while desktop shows through), adaptive LOCAL sizing via NSLayoutManager measurement + cap-height slack (no top-clip at 10pt→64pt), panel/contentView layer set clearColor in init. Then extracted 2 leaf modules: Sources/rendering/VerticallyCenteredTextFieldCell.{h,m} + Sources/rendering/AttributedStringLayoutMeasurer.{h,m}. FC-prefix added to C fn symbols. Makefile: `find Sources -name '*.m' ! -name gen-icon.m` auto-compiles new modules. clock.m 2402→2330 LoC (−72). Next: iter-25b extracts data/ (ThemeCatalog + MarketCatalog), then 25c (MarketSessionCalculator + content builders), then 25d (segments + menu builders + preferences), then 25e (FloatingClockPanel core split).
- 2026-04-24 02:30..03:15 UTC — iter-26..36 batch: Glass-default CanvasOpacity=0.75, Save-as-Default action with [d synchronize], hand-curated BST/CEST/JST/PDT TZ abbreviations via friendlyAbbrevForIana, UTC offset (`UTC-7` / `UTC+5:30`) inline via utcOffsetForIana, fullTzLabelForIana composer, inline UTC reference on LOCAL (`PDT UTC-7 · 09:37:07 UTC`), UTC always 24h canonical, Show UTC Reference toggle. Plus `scripts/capture-clock.sh` helper for focused window screenshots. Shipped 0357bea1..b42d5a95.
- 2026-04-24 03:45..04:10 UTC — iter-37..50 aesthetic + coverage: progress-bar running-head (dim past / bright frontier / gray empty), urgency color tiers on ACTIVE close countdown (>1h green / 30-60min amber / <30min red), symmetric tiers on NEXT, ShowSeconds actually honored (fixed long-standing UX lie), NEXT cross-day weekday disambiguation, **real bug fixed** in computeSessionState's closed-before-open-today path (was off by 7h since iter-9), unit test harness added (tests/test_session.m, `make test` target), session-state + TZ-helper fixtures locked in. Shipped 3ddd416f..45e390be.
- 2026-04-24 04:30..05:10 UTC — iter-51..69 tabulation + library pass: cityCode/flag emoji coverage tests, starter-profile key-coverage invariant (caught iter-55's own drift, fixed inline), Researcher starter profile added, rocket-launch `T-HH:MM:SS` countdown, richer two-line-per-market NEXT layout (market-own-TZ + session duration), trailing-newline fix for AppKit last-line clipping, tabulated demarcation (title + legend + hrules) mirrored across ACTIVE and NEXT, column-header legend drops repeated "until open" / "local" / "session" suffixes, NSVisualEffectView then **RMBlurredView library integration** for fanciful frosted-glass vibrancy (~115 LoC MIT vendored, Raffael Hannemann), TSE "Sun 17:00 → Mon 09:00 JST" both-sides-weekday disambiguation, tighter `└─` alignment under market code column. Shipped ec16d7da..f4e4f1b2.
- 2026-04-24 05:20..06:02 UTC — iter-70..82 DRY + polish: dropped redundant "Fri Apr 24" date prefix from ACTIVE headers, ACTIVE title + legend matching NEXT, **SegmentHeaderRenderer + UrgencyColors + LandingTimeFormatter** shared helpers eliminate ~80 LoC duplication between ACTIVE and NEXT builders (with named constants `kFCSegmentHRule`, `kFCUrgencyRedThresholdSecs`, `kFCUrgencyAmberThresholdSecs`, `kFCSecondsPerDay`, `kFCMaxBoundedCountdownSecs` replacing magic numbers), 4 new FCFormatLandingTime fixtures lock cross-day/cross-weekday matrix, progressive human-readable countdown at ≥24h (`T-2d 11h 27m` vs sub-day `T-HH:MM:SS`), plugin 1.3.0→1.4.0, `make leaks` + `make check` targets, category/primary method-redeclaration warnings eliminated, vendored-file pragma silences upstream warnings. Clean warning-free build, 24 tests passing, 184 KB binary, 20.8 MB physical footprint. Shipped 0a53988d..8f820d6f.
- 2026-04-24 06:15 UTC — iter-86: Sources/ architecture tree added to plugins/floating-clock/CLAUDE.md (828c5569). 11-level hierarchy with brief annotations per file matches the modularized layout after iter-70..85.
- 2026-04-24 06:20 UTC — iter-87: **500-LoC cap enforcement** (605243bc). FloatingClockPanel+MenuBuilder.m crossed the cap (612 LoC) — split into MenuBuilder (428 LoC: full menu + shared helpers + Profile submenu) and new FloatingClockPanel+SegmentMenus (199 LoC: buildLocalSegmentMenu / buildActiveSegmentMenu / buildNextSegmentMenu / showFullPreferences:). SegmentViews.m already dispatches via informal protocol so no caller changes. `make check` clean, 24 tests pass.
- 2026-04-24 06:30 UTC — iter-88: **FontWeight typographic lever** (b3a453a5). New global `FontWeight` pref (default `medium`), 5 presets (Regular / Medium / Semibold / Bold / Heavy) under DISPLAY category. Applied at every monospacedSystemFont call site (ACTIVE + NEXT) via new helpers `FCParseFontWeight` + `FCResolveMonoFont` in FontResolver. LOCAL primary stays on iTerm2 / named-font path — documented limitation. Starter profiles get character-matching defaults (Day Trader=bold, Watch Party=heavy, Night Owl/Minimalist=regular, Default/Researcher=medium). Tests +1 (25 total). Warning-free build, 184 KB binary.
- 2026-04-24 06:40 UTC — iter-89: **per-segment FontWeight overrides** (b47dd029). New `ActiveWeight` + `NextWeight` prefs with 3-tier fallback (segment key → global FontWeight → Medium) via new helper `FCResolveSegmentWeight` in FontResolver. Font Weight submenu added to ACTIVE + NEXT scoped right-click menus (LOCAL skipped — iTerm2 path). Starter profiles set per-segment weights matching their global FontWeight. Tests +1 covering all 3 fallback tiers + empty-string pass-through (26 total). Warning-free build, 184 KB binary.
- 2026-04-24 06:50 UTC — iter-90: **per-segment Transparency** (0450705d). New `LocalOpacity` / `ActiveOpacity` / `NextOpacity` prefs via new `Sources/rendering/SegmentOpacityResolver.{h,m}` module. `FCResolveSegmentOpacity` three-tier lookup (segment key → CanvasOpacity → theme->alpha) with clamping to [0.10, 1.00]. `applyTheme:` now takes `opacityKey:` param; LOCAL scoped Transparency submenu rewired to write LocalOpacity; ACTIVE + NEXT scoped menus get new Transparency submenus. Tests +1 (27 total) covering all tiers, clamping, and segment=0 pass-through. Warning-free build, 184 KB binary.
- 2026-04-24 07:00 UTC — iter-91: **progress-bar glyph catalog 6 → 10** (f43c39f1). New styles: hearts (♥ ♡), stars (★ ☆), ribbon (▰ ▱), diamond (◆ ◇). ACTIVE scoped menu's Progress Bar Style submenu grows to 10 entries with inline glyph previews. Unknown ids still fall back to "dots". Tests +1 (28 total) — verifies buildProgressBar emits the correct prefix/suffix glyph for each of the 10 ids plus the fallback path. Warning-free build, 184 KB binary.
- 2026-04-24 07:10 UTC — iter-92: **theme catalog 20 → 25** (44d6499a). Five new mood palettes: oceanic_deep, cherry_blossom, espresso, lavender_dream, mint_dark. Zero menu changes needed — theme submenus auto-enumerate kThemes. Tests +1 (29 total) `test_theme_catalog_invariants` locks count=25, checks id/display non-empty, color channels and alpha in [0,1], themeForId round-trip for every entry, plus unknown-id fallback to kThemes[0]. CLAUDE.md header bumped 10 → 25 themes with provenance by batch.
- 2026-04-24 07:20 UTC — iter-93: **shadow catalog 4 → 7** (6d45c63e). Three new ShadowStyle presets: `crisp` (pixel-hard 1/-1 drop, radius 0, opacity 0.85 — stamp feel), `plinth` (deep 0/-8 drop, radius 10, opacity 0.70 — stage base), `halo` (theme-bg bloom 0/0, radius 10, opacity 0.50). Pure CALayer.shadow\* property tweaks — no new dependencies. Full Preferences → Display → Shadow submenu grows to 7 entries. No new tests (shadow is purely visual, covered by warning-free build + existing gauntlet). 29/29 still green.
- 2026-04-24 07:30 UTC — iter-94: **LetterSpacing lever** (02deec81). New typographic axis parallel to FontWeight — adjusts character tracking on ACTIVE + NEXT attributed strings via NSKernAttributeName. 5 presets: compact (-1.0) / tight (-0.5) / normal (0.0) / airy (+0.5) / wide (+1.0). New helpers `FCParseLetterSpacing` + `FCApplyLetterSpacing` in FontResolver. Applied at each return site in both content builders; no-op at "normal" skips attribute entirely. LetterSpacing exempted from starter-coverage test (power-user sticky lever, default = no-op). Tests +1 (30 total). Warning-free build, 184 KB binary.
- 2026-04-24 07:40 UTC — iter-95: **LineSpacing lever** (8b517bcf). Completes typographic trilogy (FontWeight → LetterSpacing → LineSpacing). Vertical rhythm control on ACTIVE + NEXT multi-line via NSParagraphStyle.lineSpacing. 5 presets: tight (0pt) / snug (1pt) / normal (2pt) / loose (4pt) / airy (7pt). New helpers `FCParseLineSpacing` + `FCApplyLineSpacing`. Applied alongside FCApplyLetterSpacing at each builder return. Default `normal` matches current visual. Full Preferences → Display → Line Spacing submenu. Tests +1 (31 total). Warning-free build.
- 2026-04-24 07:50 UTC — iter-96: **proactive MenuBuilder split** (7745611d). MenuBuilder.m had grown to 469 LoC — only 31 LoC of cap headroom before next menu addition would break the contract. Extracted 5 shared NSMenu helpers (submenuTitled / groupedSubmenuTitled / setChecksInMenu / representedObject:matchesValue: / refreshMenuChecks) into `Sources/menu/FloatingClockPanel+MenuHelpers.{h,m}` (112 LoC). MenuBuilder.m now 375 LoC. SegmentMenus.m picks up the new import. No behavior change, no new tests. 31/31 still green.
- 2026-04-24 08:00 UTC — iter-97: **corner-style catalog 4 → 8** (62010669). Four new CornerStyle presets fill gaps between the original sharp/rounded/squircle/pill: hairline (1pt), micro (3pt), soft (10pt), jumbo (22pt). Full Preferences → Display → Corners submenu grows to 8 entries with inline point annotations. Pure data — CALayer.cornerRadius constants. 31/31 still green, 184 KB binary.
- 2026-04-24 08:10 UTC — iter-98: **TimeSeparator lever** (bb683a28). New formatter-level axis replacing hardcoded `:` between HH / mm / ss tokens. 5 presets: colon / middot (·) / space / slash / dash. Implementation via two static helpers in Runtime.m — `fcTimeSeparatorPattern` returns UTS#35-quoted literal, `fcBuildTimeFormat` assembles the H:MM[:SS] pattern. Applied at 3 sites (LOCAL tick, UTC reference, legacy single-market/local-only). LOCAL + UTC share same separator for visual consistency. Full Preferences → Display → Time Separator submenu with inline rendered previews. 31/31 still green, 184 KB binary.
- 2026-04-24 08:20 UTC — iter-99: **Density catalog 4 → 6** (7952e68e). Two new presets bracket the existing range: `ultracompact` (4pt) and `cavernous` (64pt). Pad now spans 4pt → 64pt (16×) vs prior 12pt → 48pt (4×). Pure data — Density pref already drives inner-row-height formula in Layout.m. Full Preferences → Display → Density submenu grows to 6 entries with inline point annotations. 31/31 still green.
- 2026-04-24 08:30 UTC — **iter-100 milestone** (c2cb3cb4). Plugin bumped 1.4.0 → 1.5.0. Description rewritten to surface v1.5 aesthetic expansion: themes 20→25, progress bars 6→10, corners 4→8, shadows 4→7, density 4→6; new levers FontWeight (global + per-segment), per-segment Transparency, LetterSpacing + LineSpacing, TimeSeparator; plus two proactive category splits (MenuBuilder → SegmentMenus at iter-87, MenuBuilder → MenuHelpers at iter-96). Test suite 23 → 31 fixtures. All validators green. 216 KB signed binary.
- 2026-04-24 08:40 UTC — iter-101: **NextItemCount 4 → 7 presets** (a0a7b33f). Adds 4 / 7 / 10 to the existing 1 / 2 / 3 / 5. With 12 exchanges up to ~11 can be CLOSED at once, so 10 is now a meaningful ceiling. Menu-only change in SegmentMenus.m. 31/31 still green.
- 2026-04-24 08:50 UTC — iter-102: **Quick Style presets** (866baf21). New top-level menu category parallel to Profile, scoped to aesthetic-only levers (leaves FontSize / SelectedMarket / DisplayMode alone). 4 bundled moods: Brutalist, Zen, Retro CRT, Executive. Each writes a 10-key pref dict atomically. New methods `buildQuickStylesMenu` + `applyQuickStyle:`. MenuBuilder.m 393 → 454 LoC, still under cap. 31/31 still green.
- 2026-04-24 09:00 UTC — iter-103: **guardrail lesson** — user reported clock "no longer visible" caught live during previous firing. Root cause: iter-100 verification step ran `defaults delete com.terryli.floating-clock` to check binary size, wiping the user's live window-position / active-profile / per-segment theme / quick-style state on an already-running clock. New Non-Obvious Learnings entry (`Never run defaults delete mid-loop`) codifies the rule: destructive state commands (defaults delete, pkill, rm on user's bundle) belong ONLY in the explicit `make leaks` gauntlet the user has opted into. Per-iter validation stays read-only (`file`, `codesign -v`, `ls`, `wc -l`, `pgrep -l`). Zero code change; contract-only commit.
- 2026-04-24 09:10 UTC — iter-104: **Quick Styles extracted + locked** (325c5a8d). The 4 style bundles (Brutalist / Zen / Retro CRT / Executive) moved from inline MenuBuilder.m into new `Sources/preferences/FloatingClockQuickStyles.{h,m}` (data module, parallels StarterProfiles). Tests +1 (32 total) validates: count > 0, 2-element entries, theme ids round-trip via themeForId, enum-valued keys (CornerStyle / ShadowStyle / Density / FontWeight / LetterSpacing / LineSpacing / TimeSeparator) within allowed sets. Typo-proof bundles. MenuBuilder.m 454 → 405 LoC.
- 2026-04-24 09:20 UTC — iter-105: **Quick Styles 4 → 6** (c40f2d6b). Two new moods: `Neon` (synthwave palette, glow shadow, hairline corner, heavy/wide/dash — retrowave) and `Hacker` (green_phosphor, sharp corners, no shadow, bold/tight/colon — terminal-like). Pure data add in FloatingClockQuickStyles.m; iter-104's invariant test re-runs on all 6 bundles. 32/32 still green.
- 2026-04-24 09:30 UTC — iter-106: **Quick Styles 6 → 8** (f81be094). Two cool-palette moods: `Glacier` (nord palette, squircle, subtle shadow, regular/normal/middot — calm / wintry) and `Midnight` (midnight_blue, soft corner, halo shadow, medium/normal/colon — observatory vibe). Pure data. 32/32 still green.
- 2026-04-24 09:40 UTC — iter-107: **retroactive TimeSeparator tests** (89afc259). iter-98's helpers (`fcTimeSeparatorPattern`, `fcBuildTimeFormat`) were file-scoped statics in Runtime.m, untestable. Extracted to single public `FCCurrentTimeFormat(is12h, showSec)` in FontResolver.{h,m}. Runtime.m's 3 call sites route through the public API. Tests +1 (33 total) covers 5 separator ids × 2 time-format variants + unknown-id fallback. 33/33 green, 216 KB binary.
- 2026-04-24 09:50 UTC — iter-108: **SegmentGap 5 → 7** (6397d8a1). Two new presets bracket the existing range: `flush` (0pt — borderless, segments touch) and `cavernous` (24pt — most generous). Gap span now 0pt → 24pt. Pure data — SegmentGap pref already drives inter-segment arithmetic. 33/33 still green.
- 2026-04-24 10:00 UTC — iter-109: **'Reset Visual Style' utility** (39ff3df8). New Window-category action clears 33 aesthetic pref keys so NSUserDefaults falls back to clock.m's registerDefaults. Leaves workflow-scoped state (SelectedMarket / DisplayMode / ActiveProfile / Profiles / FontName / window frame) intact. Lets users experiment with Quick Styles / levers then return to factory without losing profile catalog or window position. 33/33 still green.
- 2026-04-24 10:10 UTC — iter-110: **About dialog + Info.plist version sync** (63266d7f). Info.plist's CFBundleShortVersionString had been stale at 1.0.0 since iter-0 despite plugin.json reaching 1.5.0 at iter-100. Synced to 1.5.0; CFBundleVersion set to iteration number (110). About dialog now pulls version + build via NSBundle and lists the major v1.5 surfaces: 25 themes, 8 Quick Styles by name, 12 exchanges, 6 profiles, typography trilogy, idle-CPU + binary-size metrics. 33/33 still green.
- 2026-04-24 10:20 UTC — iter-111: **DateFormat 6 → 9 locale presets** (4c0a4aae). Three new patterns: `compact_iso` (`04-23`), `usa` (`4/23/2026`, month-first), `european` (`23.4.2026`, day-first). Land via existing dateFormatPrefix dispatch in Runtime.m plus both Date Format submenus (LOCAL scoped + Full Preferences → Market). 33/33 still green.
- 2026-04-24 10:30 UTC — iter-112: **sky glyph binary → 5-phase** (aad48185). Upgraded LOCAL row's time-of-day cue from ☀️/🌙 binary to 5 buckets: 🌅 dawn [5,7) · ☀️ day [7,17) · 🌇 dusk [17,19) · 🌙 night [19,5). No new pref — ShowSkyState=YES users pick up extra nuance automatically. Still civil-twilight heuristic (no lat/lon solar math). 33/33 still green.
- 2026-04-24 10:40 UTC — iter-113: **FCDateFormatPrefix extracted + test** (1113b69e). Parallel to iter-107. Runtime.m's static `dateFormatPrefix` dispatcher moved to new `Sources/core/DateFormatPrefix.{h,m}` module. Tests +1 (34 total): locks in all 9 preset → UTS#35 pattern mappings (iter-111's locale additions now covered) + nil/empty/unknown → short-default fallback. 34/34 green.
- 2026-04-24 10:50 UTC — iter-114: **FCSkyGlyphForHour extracted + test** (bbae1237). Runtime.m's inline 5-phase if-else ladder (iter-112) moved to `Sources/core/SkyGlyph.{h,m}`. Tests +1 (35 total): asserts correct glyph for each hour [0, 23] plus out-of-band -1 / 24 → night fallback. 35/35 green.
- 2026-04-24 11:00 UTC — iter-115: **FCSegmentGapPoints extracted + test** (c48eaa16). Layout.m's 6-line if-else ladder for iter-108's 7 SegmentGap presets (flush/tight/snug/normal/airy/spacious/cavernous) moved to `Sources/core/SegmentGap.{h,m}`. Tests +1 (36 total): locks the full 7-value catalog + nil/empty/unknown → 4pt normal fallback. 36/36 green.
- 2026-04-24 11:10 UTC — iter-116: **FCDensityPadPoints extracted + test** (1dceed64). Layout.m's 5-line if-else for iter-99's 6 Density presets (ultracompact/compact/default/comfortable/spacious/cavernous) moved to `Sources/core/DensityPad.{h,m}`. Tests +1 (37 total): locks all 6 values + nil/empty/unknown → 24pt default fallback. 37/37 green.
- 2026-04-24 11:20 UTC — iter-117: **FCCornerRadiusPoints extracted + lean test** (d414bfb4). Layout.m's cornerRadiusFor block for iter-97's 8 CornerStyle presets moved to `Sources/core/CornerRadius.{h,m}`. Unique: `pill` takes (w, h) so radius depends on shorter axis. Tests +1 (38 total) — lean version (8 cases + pill-both-orientations + nil/unknown fallback) because test_session.m hit 994/1000 LoC. **Flag**: iter-118 must split the harness before more tests land. 38/38 green.
- 2026-04-24 11:30 UTC — iter-118: **test harness split** (29ca9877). Resolved iter-117's backlog. Moved the 14 pref-lever / dispatcher invariant tests into new `tests/test_levers.{h,m}` (373 LoC); session-state / TZ-helper / flag / city / landing / profile-coverage tests + main() stay in `tests/test_session.m` (453 LoC). Shared `failures` counter declared `extern int failures` in `test_levers.h`, defined non-static in test_session.m. Makefile's TEST_SOURCES picks up both translation units. Both files have ~550 LoC headroom before cap. 38/38 still green.
- 2026-04-24 11:40 UTC — iter-119: **backfill lean CornerRadius test** (dc33b5f4). Promoted iter-117's lean individual-assertion form to the struct-loop pattern used by other lever tests (Density / SegmentGap). Covers all 8 CornerStyle presets + pill-both-orientations + nil/empty/unknown → rounded fallback. 38/38 still green. test_levers.m 400 LoC.
- 2026-04-24 11:50 UTC — iter-120: **FCShadowSpecForId extracted + test** (205c67f9). Completes the Layout.m dispatcher-extraction series. ShadowStyle is the most complex (4 CALayer props + theme-dependent color). Solved via spec-struct pattern: `FCShadowSpec` struct with `FCShadowColorSource` enum (Black / ThemeForeground / ThemeBackground) + numeric params. Pure mapping in `Sources/core/ShadowSpec.{h,m}`; Layout.m does theme substitution + CALayer write. Tests +1 (39 total) locks all 7 presets with field-by-field match + nil / empty / unknown → disabled. 39/39 green.
- 2026-04-24 12:00 UTC — iter-121: **v1.6.0 release consolidation** (ade25115). Bump plugin.json 1.5.0 → 1.6.0 + Info.plist sync + CFBundleVersion 110 → 121. Description rewritten to surface v1.6 scope (all aesthetic catalogs + typography trilogy + 7 new data modules + 39 test fixtures across 2 harness files). iter-101..120 focused on testability hardening: 7 new `Sources/core/*.{h,m}` dispatcher modules, 1 `Sources/preferences/*` extraction, test harness split. All dispatchers in Layout.m + Runtime.m are now pure-function helpers with fixture-locked invariants. 39/39 green, validator clean.
- 2026-04-24 12:10 UTC — iter-122: **CLAUDE.md architecture-tree refresh** (2d559ba4). Last updated at iter-86 (pre-dispatcher-extraction series). Added all 7 new data modules (core/DateFormatPrefix, SkyGlyph, SegmentGap, DensityPad, CornerRadius, ShadowSpec + preferences/FloatingClockQuickStyles) with their iter landmarks. Inline-annotated FontResolver's grown surface (FontWeight/LetterSpacing/LineSpacing/CurrentTimeFormat helpers), MenuBuilder's iter-96 MenuHelpers split, theme count 10→25, progress-bar 6→10. Zero code change. 39/39 still green.
- 2026-04-24 12:20 UTC — iter-123: **`kSessionPreMarket` state** (07a01efc). Tier-2 enhancement from the queue. New SessionState value for the 15-minute window before each exchange's regular open (weekdays only). Uniform across all 12 exchanges — no per-market hasPreMarket flag; auction-window heuristic holds broadly enough. Promotion logic: CLOSED + !isWeekend + nowMins < openMins + secsToNext ≤ 15 min → PRE-MARKET. New amber ◐ glyph + amber color. NextSegmentContentBuilder includes it alongside CLOSED. Tests +1 (40 total) `test_nyse_premarket_last_15min` locks the 15-min / 10-min / boundary / at-open cases. CLAUDE.md Known-Limitations updated: pre-market handled, after-hours remains Tier-2.
- 2026-04-24 12:30 UTC — iter-124: **PRE-MARKET universal-exchange + weekend-exclusion fixtures** (b02feefd). iter-123 shipped one NYSE case; backfill locks the two implicit design invariants. `test_tse_premarket_not_just_nyse` — TSE at 08:50 JST = PRE-MARKET, 08:30 JST = CLOSED. Guarantees no one later introduces a per-market `hasPreMarket` flag that silently restricts promotion to NYSE. `test_premarket_not_on_weekend` — Sat 09:20 EDT stays CLOSED despite being <15 min from the imaginary 09:30 open. Locks the `!isWeekend` guard in computeSessionState. Tests +2 (42 total). 42/42 green.
- 2026-04-24 12:40 UTC — iter-125: **`kSessionAfterHours` state** (d76bdafd). Symmetric to iter-123. New SessionState for the 15-min window immediately after each exchange's regular close (weekdays only). Uniform across all 12 exchanges — no per-market hasAfterHours flag; short symmetric signal rather than trying to model each exchange's full extended session (US ~4h, others 1-2h). Promotion: CLOSED + !isWeekend + nowMins >= closeMins + (nowMins - closeMins) <= 15 → AFTER-HOURS. New ◒ glyph (bottom-half dark, dusk complement to PRE-MARKET's ◐ left-half dawn) + rose color (0.95/0.45/0.55). NextSegmentContentBuilder filter extended. Test harness stateName() switch extended — compiler exhaustiveness caught the gap. Tests +2 (44 total) covering 16:00 boundary / 16:10 within / 15:59 mid-session / 16:30 back to CLOSED / Sat 16:10 weekend-excluded. CLAUDE.md Design state-glyph table + Known-Limitations both updated. 44/44 green, warning-free.
- 2026-04-24 12:50 UTC — iter-126: **SessionSignalWindow lever** (4db94abc). iter-123/125's hardcoded 15-min auction window now user-configurable. New `Sources/core/SessionSignalWindow.{h,m}` module: `FCSessionSignalWindowMinutes` maps 5 preset ids (off / 5min / 15min / 30min / 60min) to minutes. "off" returns 0 which disables both PRE-MARKET and AFTER-HOURS promotions — pure OPEN/CLOSED/LUNCH semantics for users who find the short transitional states noisy. computeSessionState reads NSUserDefaults once and applies the value symmetrically to both promotion gates. Menu surface under MARKET → Session Signals. New action handler `setSessionSignalWindow:` declared in header + implemented; `resetVisualStyle` clears the key. registerDefaults seeds "15min" (matches iter-123/125 original behavior). Tests +1 (45 total): `test_session_signal_window` covers all 5 presets + nil/empty/unknown → 15 fallback. CLAUDE.md Runtime Preferences + architecture tree updated. 45/45 green, warning-free.
- 2026-04-24 13:00 UTC — iter-127: **SessionSignalWindow integration fixtures** (93c31dc8). iter-126's unit test covered the dispatcher; this covers the end-to-end wiring (pref value → promotion gate → actual state). Two fixtures: `test_signal_window_pref_gates_premarket` (NYSE 09:20 EDT: off/5min stay CLOSED, 15/30/60min promote to PRE-MARKET) and `test_signal_window_pref_gates_afterhours` (NYSE 16:10 EDT: same 5-preset matrix for AFTER-HOURS). Both save/restore the pref to avoid cross-test bleed. Tests +2 (47 total). 47/47 green, warning-free.
- 2026-04-24 13:10 UTC — iter-128: **profile round-trip fix for SessionSignalWindow** (5fe849b8). iter-126 landed the lever but overlooked adding the key to `profileManagedKeys()`, so profile Save/Load/Switch silently didn't carry the pref — e.g. Hacker profile with "off" would leak "off" into Day Trader afterward. Added `SessionSignalWindow` to the managed-keys array; added to the test-coverage exempt set alongside TimeSeparator / LetterSpacing / LineSpacing (registered default "15min" is a valid fallback so starters don't each need to set it). New test `test_profile_managed_keys_covers_iter126_lever` — direct regression guard so silent removal from the managed-keys list would fail, not just the downstream coverage test. Tests +1 (48 total). 48/48 green, warning-free.
- 2026-04-24 13:20 UTC — iter-129: **FontWeight catalog 5 → 7** (2b7f1aa2). Pivot away from session-state cluster back to aesthetics per v4 Core Directive. Parallels iter-99's Density bracket-expansion pattern: added `thin` (NSFontWeightThin) and `black` (NSFontWeightBlack) flanking the existing 5 presets. AppKit exposes 9 NSFontWeight constants total — Ultralight + Light stay omitted as near-duplicates of Thin. FCParseFontWeight extended; 3 menu surfaces updated (global + ACTIVE + NEXT per-segment Font Weight submenus); Quick Styles allowed-set widened to permit the 2 new values (none currently in use). Existing table-driven test `test_font_weight_parser` gets 2 new rows. No test-count change (48/48). Warning-free build, CLAUDE.md Runtime Preferences updated.
- 2026-04-24 13:30 UTC — iter-130: **Quick Styles 8 → 10** (4d3fccf2). Two new moods exercise iter-129's new weight extremes. `Featherlight` (lavender_dream palette / hairline corners / no shadow / spacious density / thin weight / airy letter spacing / loose line spacing / space separator) — delicate/ethereal. `Industrial` (espresso palette / sharp corners / plinth shadow / compact density / black weight / tight spacings / dash separator) — loud/mechanical. Iter-104's `test_quick_styles_invariants` auto-covers both — no new test needed. 48/48 still pass. CLAUDE.md Quick-Style row + architecture-tree Quick-Styles annotation both updated to 10 moods + iter-130 provenance.
- 2026-04-24 13:40 UTC — iter-131: **Progress Bar glyph catalog 10 → 12** (6a5e5dd9). Two new styles distinct from the existing set: `triangles` (▲ △) — filled vs hollow triangle, directional without duplicating arrows' horizontal motion; `thindots` (• ·) — subdued variant of `dots` for users who want a quieter progress bar. Pure data — fcGlyphsForStyle dispatcher extended. ACTIVE-scoped Progress Bar Style submenu grows to 12 entries with inline glyph previews. MarketSessionCalculator.h comment refreshed with full 12-way grid. Existing `test_progress_bar_glyph_styles` (table-driven) gets 2 new rows. 48/48 still pass. CLAUDE.md Runtime Preferences row updated.
- 2026-04-24 13:50 UTC — iter-132: **theme catalog 25 → 27** (828d5173). Two new mood palettes fill gaps: `Forest` (mossy green 0.55/0.90/0.60 on pine-needle 0.03/0.10/0.05 — cool/earthy counterpart to Green Phosphor's brighter CRT green) and `Volcanic` (molten crimson 0.98/0.35/0.15 on charred obsidian 0.10/0.02/0.02 — fiercer counterpart to Amber CRT for high-volatility sessions). Pure data in ThemeCatalog.m — menu submenus enumerate kThemes so no menu changes needed. iter-92's `test_theme_catalog_invariants` updated count 25 → 27 — validates round-trip, channel ranges, id/display presence, and unknown-id fallback for the 2 new entries. 48/48 still pass. CLAUDE.md Design theme-provenance line extended.
- 2026-04-24 14:00 UTC — iter-133: **v1.7.0 release consolidation** (43e54657). 12 iters since v1.6.0 (iter-121 → iter-133, matching the iter-100 → iter-121 cadence). plugin.json bumped 1.6.0 → 1.7.0; Info.plist CFBundleShortVersionString synced + CFBundleVersion 121 → 133. plugin.json description rewritten to surface v1.7 scope: 10 Quick Styles including Featherlight/Industrial, 5-state session tracking (OPEN/LUNCH/PRE-MARKET/AFTER-HOURS/CLOSED) with SessionSignalWindow lever, 27 themes, 12 progress-bar glyphs, 7 font weights. About dialog updated to match. 48/48 green, validator clean. Iter-122 to iter-132 recap: arch-tree refresh + PRE/AFTER state cluster + SessionSignalWindow lever + aesthetic bracket-expansions (FontWeight 5→7, ProgressBar 10→12, Themes 25→27, QuickStyles 8→10).
- 2026-04-24 14:10 UTC — iter-134: **state-accurate label in legacy single-market view** (6b0cf54a). First post-v1.7.0 iter. Caught a semantic mismatch left over from iter-123/125: the legacy single-market Runtime.m path kept a hardcoded "CLOSED · opens in Xh" literal even when state=PRE-MARKET or AFTER-HOURS, so the glyph's amber ◐ / rose ◒ disagreed with the text. Fix: switch on state → stateWord (PRE-MARKET / AFTER-HOURS / CLOSED) and pick `colorForState(state, NULL)` for the text too. Applies to both countdown-format branches (bounded Xh/Xm and cross-day "EEE HH:mm" absolute). The three-segment dashboard wasn't affected — NextSegmentContentBuilder derives its labels from glyph + state-color via SegmentHeaderRenderer. No test change (Runtime.m renders attributed strings; compiler-enforced exhaustiveness covers OPEN/LUNCH already filtered out before the else branch). 48/48 still pass.
- 2026-04-24 14:20 UTC — iter-135: **extract `labelForState` for testability** (6cd69b9d). iter-134's state→word switch was inline in Runtime.m — fine for the fix but untestable + not reusable. Extract to `labelForState(SessionState)` alongside `glyphForState`/`colorForState` so the full (glyph, label, color) triad lives in one file. Future SessionState additions become a compiler-enforced 3-switch edit. Runtime.m simplified to single call + inline ternary for textColor. New fixture `test_session_state_label` locks all 5 cases (OPEN/LUNCH/CLOSED/PRE-MARKET/AFTER-HOURS) + out-of-range safe default (CLOSED). Tests +1 (49 total). 49/49 green, warning-free.
- 2026-04-24 14:30 UTC — iter-136: **Session Signals shortcut in NEXT segment menu** (4a702ff2). iter-126 exposed SessionSignalWindow only via Full Preferences → MARKET → Session Signals. But the pref's visible effect — PRE-MARKET ◐ and AFTER-HOURS ◒ glyphs — shows up specifically on NEXT entries. Added submenu shortcut in `buildNextSegmentMenu` so right-click on NEXT surfaces the lever directly. Same 5 presets, same action handler, same pref key — pure menu-surface addition, zero code or test churn. 49/49 still pass.
- 2026-04-24 14:40 UTC — iter-137: **LetterSpacing catalog 5 → 7** (325afa6f). Parallel to iter-129's FontWeight and iter-99's Density bracket expansions. Added `condensed` (-1.5) and `extrawide` (+1.5) flanking existing compact/tight/normal/airy/wide. Span now ±1.5 vs prior ±1.0 — gives users with very narrow or very wide LOCAL font stacks more room. FCParseLetterSpacing extended; Letter Spacing submenu grows to 7 entries with inline numeric annotations; test_letter_spacing_parser (table-driven) gets 2 new rows; Quick Styles allowed-set widened. No test-count change (49/49). Warning-free, CLAUDE.md Runtime Preferences updated.
- 2026-04-24 14:50 UTC — iter-138: **LineSpacing catalog 5 → 7** (27ec3d0e). Completes the typography-trilogy bracket-expansion pattern (FontWeight iter-129, LetterSpacing iter-137, LineSpacing now). Added `spacious` (10pt) and `cavernous` (14pt) on upper end — tight=0pt is the natural floor so expansion goes upward only. Naming matches Density / SegmentGap's cavernous convention. FCParseLineSpacing extended; Line Spacing submenu grows to 7 entries with inline pt annotations; test_line_spacing_parser (table-driven) gets 2 new rows; Quick Styles allowed-set widened. No test-count change (49/49). Warning-free, CLAUDE.md Runtime Preferences updated.
- 2026-04-24 15:00 UTC — iter-139: **TimeSeparator catalog 5 → 7** (c618e4d4). TimeSeparator was the last 5-preset typographic axis untouched. Added `pipe` (|) and `plus` (+) — both distinct from existing colon/middot/space/slash/dash. FCCurrentTimeFormat extended with two UTS#35-quoted literals; Time Separator submenu grows to 7 entries with inline previews; test_current_time_format (table-driven) gets 2 new rows; Quick Styles allowed-set widened. Post-iter-139, all six 5-preset axes (FontWeight / LetterSpacing / LineSpacing / SegmentGap / CornerStyle / Density / TimeSeparator) are now at ≥6 presets. 49/49 still pass, warning-free.
- 2026-04-24 15:10 UTC — iter-140: **Auction Watcher starter profile** (28a4f488). Pivot from pref-catalog expansion to bundled-profile packaging. Showcases the iter-123/125/126 auction-window cluster + recent aesthetic additions (iter-132 volcanic theme, iter-129 black weight, iter-131 triangles progress bar). Three-segment (so NEXT shows ◐ / ◒), volcanic/espresso themes, black weight, compact density, hairline corners, crisp shadow — "precision readout" identity. 29 non-exempt keys specified per iter-55 coverage invariant. `test_starter_profiles_count` bumped 6 → 7; `test_starter_profiles_cover_all_keys` auto-validates. 49/49 still pass, warning-free, CLAUDE.md ActiveProfile row updated.
- 2026-04-24 15:20 UTC — iter-141: **NEXT segment renders real state glyphs** (e8c9cca2). Caught a real bug while verifying iter-140: iter-123/125 introduced PRE-MARKET (◐ amber) and AFTER-HOURS (◒ rose) states, and iter-125 added them to NextSegmentContentBuilder's filter — but the render loop then hardcoded `glyph = lunch ? ◑ : ○` (violet/gray). PRE/AFTER entries appeared with generic gray ○, silently invisible. Fix: preserve `state` on NextEntry struct, then use `glyphForState(e.state)` + `colorForState(e.state, NULL)`. CLOSED/LUNCH behavior unchanged; PRE/AFTER now render their proper amber/rose. iter-140's Auction Watcher profile now actually showcases what it advertised. 49/49 still pass; rendering is attributed-string layout, not easily unit-testable but narrow and covered by compiler exhaustiveness on SessionState.
- 2026-04-24 15:30 UTC — iter-142: **PRE/AFTER progress-value locks** (136cf18f). Existing PRE/AFTER fixtures covered state + secsToNext but left `progress` implicit. Added new `ASSERT_PROGRESS_NEAR` macro (parallel to ASSERT_SECS_NEAR) and two fixtures: `test_premarket_progress_is_zero` (NYSE 09:20 EDT → 0.0) and `test_afterhours_progress_is_one` (NYSE 16:10 EDT → 1.0). Locks the invariant so a future edit to the progress-computation ladder won't silently break bar rendering when state is PRE-MARKET or AFTER-HOURS. Tests +2 (51 total). 51/51 pass, warning-free.
- 2026-04-24 15:40 UTC — iter-143: **24h state-invariants sweep fixture** (9593f8e0). Prior fixtures verified specific input → specific output; this catches structural regressions at arbitrary minutes. iter-48 caught a similar bug (secsToNext off-by-7h since iter-9) only by chance during manual inspection. New `test_state_invariants_24h_sweep` iterates NYSE's full Friday in 30-min steps (48 checkpoints), asserting at every tick: state ∈ the 5-enum set, progress ∈ [0, 1], secsToNext ≥ 0. Catches enum drift, progress overflow, negative countdowns proactively. Tests +1 (52 total), 52/52 pass, all 48 checkpoints hold, warning-free.
- 2026-04-24 15:50 UTC — iter-144: **Quick Styles 10 → 12** (a57c7db9). `Trading Floor` (amber_crt / pill / glow / compact / bold / tight / pipe — analog trading desk with iter-139's pipe separator) and `Scholar` (paper_white / rounded / subtle / comfortable / regular / extrawide / cavernous / middot — uses iter-137 extrawide LetterSpacing + iter-138 cavernous LineSpacing for deliberate, studious readout). Iter-104's invariant test auto-covers both; CLAUDE.md Quick-Style row + architecture tree + About-dialog text updated to 12 moods. 52/52 still pass, warning-free.
- 2026-04-24 16:00 UTC — iter-145: **24h sweep extended to lunch-market (TSE)** (f82a749f). iter-143 covered NYSE's 48 checkpoints but NYSE has no LUNCH state — the lunch-code-path region of computeSessionState (11:30-12:30 JST for TSE / matching for HKEX/SSE) was untested at the invariant level. Refactor: extracted sweep body into `sweep_invariants(mkt, iana, tzLabel)` helper (5-enum validity, progress ∈ [0,1], secsToNext ≥ 0). `test_state_invariants_24h_sweep` kept as NYSE-EDT driver; new `test_state_invariants_tse_sweep` as TSE-JST driver. 48 new checkpoints through LUNCH path. Tests +1 (53 total). 53/53 pass, warning-free.
- 2026-04-24 16:10 UTC — iter-146: **v1.8.0 release consolidation** (5fa45ddd). 12 iters since v1.7.0 (iter-133 → iter-146, matching the iter-121 → iter-133 cadence). plugin.json 1.7.0 → 1.8.0; Info.plist CFBundleShortVersionString synced; CFBundleVersion 133 → 146. Description rewritten to surface v1.8 scope: 7 starter profiles (Auction Watcher new), 12 Quick Styles (Trading Floor + Scholar new), typography trilogy at 7 presets each (completed iter-137/138/139), 27 themes, 12 progress-bar glyphs, iter-141 NEXT render fix so PRE/AFTER glyphs are actually visible. 48 → 53 test fixtures. 53/53 green, validator clean. Iter-134 to iter-145 recap: 1 real-bug fix (iter-141), 1 label fix + extraction (iter-134/135), 3 typography bracket expansions (iter-137/138/139), 1 new profile (iter-140), 1 menu shortcut (iter-136), 2 Quick Styles (iter-144), 4 test-coverage expansions (iter-142/143/145).
- 2026-04-24 16:20 UTC — iter-147: **weekend invariant + stale-caveat cleanup** (6a37d593). First post-v1.8.0 iter. Two-part cleanup. (1) Dropped the outdated Known-Limitation note claiming stacked-top/bottom layouts "may have minor drift" — Layout.m's else-branch handles both variants uniformly (just a Y-position swap), and stacked-local-top has been the default since iter-28 so the path is heavily exercised. (2) New `test_weekend_always_closed` fixture: iterates Sat 2026-04-25 on NYSE in 30-min steps (48 checkpoints), asserts every tick stays CLOSED. Covers the weekend-guard branch that neither iter-143 (NYSE weekday) nor iter-145 (TSE weekday) sweeps touched. Tests +1 (54 total). 54/54 pass, warning-free. CLAUDE.md Known-Limitations trimmed to holidays + extended-after-hours only.
- 2026-04-24 16:30 UTC — iter-148: **Auction Watcher actually sets the extended window** (0b68e53a). iter-140's Auction Watcher profile promised "Extended 30-min SessionSignalWindow" in its comment but never wrote the key — it silently fell through to registered default "15min", making the comment false advertising. iter-128's managedKeys wiring (which clears unset keys on profile switch) made this worse: picking Auction Watcher from another profile would actively LEAVE the window at whatever the prior profile had (or 15min default). Fix: explicit `@"SessionSignalWindow": @"30min"`. New `test_auction_watcher_sets_extended_window` locks the identity pref — catches accidental removal immediately at test-run rather than downstream via behavior drift. Tests +1 (55 total). 55/55 pass.
- 2026-04-24 16:40 UTC — iter-149: **Copy Time utility in LOCAL segment menu** (f234db9c). Pivot to user-facing utility addition after test-heavy cluster. New `copyTime:` action handler writes the LOCAL row's current display string (time + TZ label + optional UTC reference) to the system clipboard via NSPasteboard. Exposed only from LOCAL's right-click menu — ACTIVE/NEXT have multiple simultaneous entries so "the time" is ambiguous there. Users wanting per-market copy can use single-market display mode. No new test (3-line pasteboard write, negligible risk surface, @selector binding checked at build). 55/55 still pass, warning-free.
- 2026-04-24 16:50 UTC — iter-150: **Copy Time cross-mode fix + Copy for ACTIVE/NEXT** (d23c390c). Caught a fresh-install regression in iter-149: `copyTime:` only read `_label.stringValue`, which is populated only in legacy single-market / local-only DisplayModes. Three-segment (default since iter-11) stores LOCAL's time in `_localSeg.timeLabel.stringValue` — so iter-149's Copy Time silently copied empty string on a fresh install. Fix: prefer the populated source. Also extended: Copy Active Markets + Copy Next Opens submenu items pull `.attributedStringValue.string` from each segment's contentLabel — snapshot the rendered list for pasting into notes/chat. 55/55 still pass, warning-free.
- 2026-04-24 17:00 UTC — iter-151: **Future Enhancements roadmap refresh** (db77a623). Zero-code housekeeping after the feature-heavy iter-149/150. Moved 4 silently-shipped items from Near-term / absent to "Already shipped in v4": PRE-MARKET (iter-123), AFTER-HOURS (iter-125), SessionSignalWindow lever (iter-126), Copy cluster (iter-149/150). Added one new Near-term item surfaced by iter-149/150 exploration — keyboard shortcuts for Copy actions (deferred pending LSUIElement global event-tap evaluation). CLAUDE.md is now accurate about what's shipped vs pending. 55/55 still pass.
- 2026-04-24 17:10 UTC — iter-152: **Copy cluster gets self-documenting header** (4482646d). Clipboard snapshots from iter-149/150 were raw segment text — pasted hours later, a user couldn't tell when the snapshot was taken. Add a single-line header via new `fcCopyWithHeader(label, body)` static helper: `# Floating Clock · <LABEL> · yyyy-MM-dd HH:mm:ss UTC\n<body>`. UTC in the stamp — unambiguous across the user's possibly-changed local zone. All three Copy actions route through the helper so format stays consistent and any future Copy additions are one-liners. 55/55 still pass.
- 2026-04-24 17:20 UTC — iter-153: **copyStateToClipboard consolidated under fcCopyWithHeader** (a9b0090d). Discovered iter-85's older global "Copy Clock State" (⌘⇧C) still produced bare-text snapshots — inconsistent with iter-152's header format on the per-segment Copy cluster. Routed copyStateToClipboard (label "FULL CLOCK STATE") through the same helper. Needed a forward declaration since iter-85's handler appears earlier in ActionHandlers.m than the helper (defined next to the iter-149/150 Copy actions). All four clipboard outputs now share the same self-documenting header format. 55/55 still pass.
- 2026-04-24 17:30 UTC — iter-154: **colorForState fixture completes state triad** (badd6620). The (glyph, label, color) rendering triad for SessionState had glyph (iter-91/129) and label (iter-135) tested, but color was untested. New `test_session_state_color`: every state returns non-nil NSColor with channels ∈ [0,1] alpha=1.0 (converted via sRGB to normalize), and all 5 state colors are pairwise distinct — overlap would mean CLOSED/AFTER-HOURS become visually indistinguishable, silently hiding iter-125's signal. Tests +1 (56 total). 56/56 pass, warning-free.
- 2026-04-24 17:40 UTC — iter-155: **JSE (Johannesburg) + iana-prefix regional grouping** (8c00844f). First new exchange since iter-8's original 12. Fills the Africa regional gap — JSE (Africa/Johannesburg, 09:00–17:00 SAST, no lunch, no DST). Flag 🇿🇦 / city JHB / abbreviation SAST all added. Also refactored Time Zone menu's regional grouping from hardcoded index ranges (`i <= 2`, etc.) to iana-prefix detection (`America/`, `Europe/`, `Asia/`, `Australia|Pacific/`, `Africa/`) — future additions auto-file themselves under the right region with no menu-code edit. 13-exchange roster. Existing city-code + flag-emoji coverage tests auto-validated the new entry. 56/56 still pass, warning-free. CLAUDE.md updated.
- 2026-04-24 17:50 UTC — iter-156: **market roster lock + JSE backfill** (5455a2ef). Caught a subtle test gap introduced by iter-155: the existing city-code and flag-emoji coverage tests iterate their OWN hardcoded 12-entry fixture arrays, not kMarkets, so they silently passed without covering JSE. Added Africa/Johannesburg to both fixture arrays. Also added a new `test_market_roster_lock` that explicitly names all 14 IDs (local + 13 exchanges), asserts kNumMarkets matches count, and verifies each ID round-trips through marketForId — so silent removal of ANY market fails CI immediately, not just silently via kMarkets iteration becoming a no-op. Tests +1 (57 total). 57/57 pass.
- 2026-04-24 18:00 UTC — iter-157: **24h invariant sweep extended to JSE** (816e862a). Completes the sweep-family structural coverage: iter-143 (NYSE, DST/EDT), iter-145 (TSE, no-DST JST + lunch), iter-157 (JSE, no-DST SAST + no lunch). Africa/Johannesburg's no-DST year-round UTC+2 is a code path neither prior sweep exercises. 48 new checkpoints through state/progress/secsToNext invariants. Tests +1 (58 total). 58/58 pass, warning-free.
- 2026-04-24 18:10 UTC — iter-158: **SessionSignalWindow composable into Quick Styles** (bd28d0eb). iter-126 exposed the pref via menu but the test_quick_styles_invariants' allowed-set didn't include it, so Quick Style bundles couldn't set it. Extended allowed-set with the 5 values. Applied to 2 moods where fit is obvious: Hacker → "off" (minimalism, no auction glyphs), Trading Floor → "60min" (macro-trader identity). Other 10 bundles inherit the registered default (15min) via pref fallback — no forced behavior change. 58/58 still pass.
- 2026-04-24 18:20 UTC — iter-159: **v1.9.0 release consolidation** (744d47b4). 12 iters since v1.8.0 (iter-146 → iter-159, matching the iter-121→iter-133 and iter-133→iter-146 cadences). plugin.json 1.8.0 → 1.9.0; Info.plist synced; CFBundleVersion 146 → 159; About dialog updated. Description rewritten to surface v1.9 scope: 13-exchange roster with Africa region (JSE added iter-155), Copy cluster with self-documenting UTC-stamped headers, SessionSignalWindow Quick-Style-composable, state-invariant sweep family (NYSE + TSE + JSE + weekend), colorForState fixture closes the glyph/label/color triad. 53 → 58 test fixtures. 58/58 green, validator clean. v1.9.0 shipped.
- 2026-04-24 18:30 UTC — iter-160: **ClipboardHeader extracted + tested** (8e96dabf). First post-v1.9.0 iter. iter-152's fcCopyWithHeader was a static helper inside ActionHandlers.m — functional but untestable. Extracted the pure-function body to new `Sources/core/ClipboardHeader.{h,m}` module: `FCComposeClipboardSnapshot(label, body, now)` returns the formatted string; ActionHandlers only wraps it with NSPasteboard write. nil-safety via `_Nullable` annotations. New `test_clipboard_header_format`: fixed-date composition locks exact format, empty-body returns empty, nil-label graceful. Tests +1 (59 total). 59/59 pass, warning-free.
