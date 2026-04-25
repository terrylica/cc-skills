---
name: install
description: "Build FloatingClock from source and install to /Applications, then launch. Use when user wants to install the floating-clock plugin's macOS app."
allowed-tools: Bash
---

# /floating-clock:install

Install the FloatingClock macOS app from this plugin's source to `/Applications/` so it's available from Spotlight, Launchpad, and Finder.

> **Self-Evolving Skill**: This skill improves through use. If the build, copy, or launch step breaks (signing change, path drift, macOS gatekeeper update) — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Steps

1. Resolve plugin root:

   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/floating-clock}"
   if [ ! -f "$PLUGIN_ROOT/Makefile" ]; then
     echo "ERROR: plugin root not found at $PLUGIN_ROOT" >&2
     exit 1
   fi
   ```

2. Build, bundle, sign:

   ```bash
   cd "$PLUGIN_ROOT" && make all
   ```

3. Copy to /Applications:

   ```bash
   cp -R "$PLUGIN_ROOT/build/FloatingClock.app" /Applications/
   ```

4. Launch:

   ```bash
   open /Applications/FloatingClock.app
   ```

5. Confirm:
   > Installed to `/Applications/FloatingClock.app` and launched. The app is now discoverable via Spotlight (⌘Space → FloatingClock) and Launchpad. Right-click the clock for options.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did `make all` produce the expected `build/FloatingClock.app`?** — If not, fix the Makefile or the build prerequisite.
2. **Did the copy/launch step succeed silently?** — If macOS prompted (gatekeeper, permission), document the bypass.
3. **Did paths drift?** — Plugin root, Makefile target, or app bundle name change → update the script.

Only update if the issue is real and reproducible — not speculative.
