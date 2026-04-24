---
name: floating-clock-v2-enhancements
version: 1
iteration: 0
last_updated: 2026-04-23T23:59:00Z
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

## Current State (auto-maintained — rewrite each firing)

**Last completed iteration**: iter-0 — scaffold this contract, loop not yet started.

**Full current apex** (v1 shipped earlier this session, commits 05a0cc44 + f1350a49 + 53f6167c + 209a8852):

- Always-on-top borderless translucent NSPanel with monospaced digits
- iTerm2 font resolution cascade (4-tier fallback)
- Bottom-center-of-primary default position
- Multi-monitor-aware persistence with antifragile fallback
- 58 KB binary, 12.8 MB physical footprint peak, 0 leaks, 0.0% idle CPU
- 0 build warnings with `-Wall`

**Active monitors**: none.

**Outstanding housekeeping**:

- [ ] Scaffold LOOP_CONTRACT.md ← DOING NOW
- [ ] Start the autonomous loop via `/loop`

---

## Implementation Queue

### Tier 1 (start here — build atomically, validate each, commit)

- [ ] **iter-1 — NSMenu context menu with persistent options**
      Implement right-click context menu on the clock window with the following items:
      `✓ Show Seconds        (toggle, default ON)
      Show Date           (toggle, default OFF)
      Time Format    ▶    24-hour ✓ | 12-hour
      Font Size      ▶    18 | 20 | 22 | 24 ✓ | 28 | 32
      Opacity        ▶    10% | 20% | 32% ✓ | 50% | 70% | Opaque
      Text Color     ▶    White ✓ | Amber | Green | Cyan | Red
      ─────
      Reset Position
      ─────
      About Floating Clock
      Quit                ⌘Q
   `
      Each selection persists to NSUserDefaults immediately (keys: `ShowSeconds`, `ShowDate`, `TimeFormat`, `FontSize`, `BackgroundAlpha`, `TextColor`). Window resizes to fit text when format changes. Menu triggered via NSTrackingArea + `rightMouseDown:` override OR `menuForEvent:` on the panel's contentView. `⌘Q` quits via standard NSApplication termination.
      Validation: run the Validation Gauntlet, plus verify `defaults read com.terryli.floating-clock` shows the new keys after toggling each option.
      Commit: `feat(floating-clock): NSMenu context menu with persistent options`

- [ ] **iter-2 — App icon for Spotlight / Launchpad / Alfred indexing**
      Generate a minimal icon at build time inside the Makefile — no external assets. Approach: draw a 1024×1024 SVG (clock face: dark rounded square background with a white circle outline and hour/minute hands at 10:10), convert via `rsvg-convert` or `qlmanage`+`sips`, pipe through `iconutil` to produce `Icon.icns`, bundle into `FloatingClock.app/Contents/Resources/`. If `rsvg-convert` unavailable, fall back to a pure-CoreGraphics one-shot Swift-less generator written in `Sources/gen-icon.m` (also compiled as a tiny helper binary run once at build time). Add `CFBundleIconFile = Icon` to Info.plist. Verify: `mdimport -d1 /Applications/FloatingClock.app` indexes it, `mdfind "kMDItemDisplayName == 'FloatingClock'"` returns the path.
      Validation: run Validation Gauntlet + `file build/FloatingClock.app/Contents/Resources/Icon.icns` shows `Mac OS X icon`.
      Commit: `feat(floating-clock): generate app icon at build time for Spotlight indexing`

- [ ] **iter-3 — Claude Code slash commands (4 total)**
      Add `plugins/floating-clock/commands/` with four command files: - `install.md` — runs `make all && cp -R build/FloatingClock.app /Applications/ && open /Applications/FloatingClock.app` - `launch.md` — runs `open /Applications/FloatingClock.app || ./build/FloatingClock.app` (prefers installed over local build) - `quit.md` — runs `pkill -f "FloatingClock.app/Contents/MacOS/floating-clock"` - `uninstall.md` — runs `pkill -f ... && rm -rf /Applications/FloatingClock.app && defaults delete com.terryli.floating-clock`
      Register the plugin's commands in `marketplace.json` if required by the validator, and ensure each command's SKILL-style frontmatter is correct. Match the pattern of existing plugins (inspect `plugins/mise/skills/` or `plugins/gmail-commander/commands/` for reference).
      Validation: `bun scripts/validate-plugins.mjs` must still exit 0. Verify the commands show up when the plugin is re-loaded by Claude Code (best-effort: spawn `claude --help` or check the plugin's SKILL list).
      Commit: `feat(floating-clock): add install/launch/quit/uninstall slash commands`

- [ ] **iter-4 — Touchpoint manifest in CLAUDE.md**
      Add a new **## Touchpoints** section to `plugins/floating-clock/CLAUDE.md` enumerating every system interaction with a 2-column table: `Kind | Details`. Cover: reads, writes, install path, build artifacts, bundles loaded (frameworks from `otool -L`), entitlements (none), network (none), launchd integration (none), Dock/menubar presence (LSUIElement hides from Dock). Include exact path(s) for every entry — no vague descriptions.
      Validation: `bun scripts/validate-plugins.mjs` exit 0. Lint-check the CLAUDE.md markdown (if the repo has a linter) or at minimum run `grep -c "Touchpoints" plugins/floating-clock/CLAUDE.md`.
      Commit: `docs(floating-clock): add Touchpoints section to CLAUDE.md`

- [ ] **iter-5 — Final validation + release decision**
      Run the full Validation Gauntlet. Check: no regressions on leaks, RSS, footprint; binary under 100 KB bundled; all 4 slash commands discoverable; icon visible in Finder/Spotlight. Update the plugin's `plugin.json` version from `1.0.0` → `1.1.0`. Consider triggering `mise run release:full` to cut a new marketplace release (tier completion per Release Decision Rule).
      Commit: `chore(floating-clock): bump to 1.1.0 after iter-1 through iter-4`

### Tier 2 (post-MVP — nice-to-have)

- [ ] System appearance (light/dark) auto-adjust background + text color
- [ ] Timezone label under clock (optional toggle)
- [ ] Weekday abbreviation (Mon/Tue/…) when Show Date is on
- [ ] Clickable calendar popup on left double-click
- [ ] Multi-clock support (e.g. local + UTC side by side)

### Tier 3 (deferred)

- [ ] Settings export/import (JSON)
- [ ] Theme presets (user-definable color + font + opacity bundles)

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
