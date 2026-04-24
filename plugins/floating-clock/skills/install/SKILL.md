---
name: install
description: "Build FloatingClock from source and install to /Applications, then launch. Use when user wants to install the floating-clock plugin's macOS app."
allowed-tools: Bash
---

# /floating-clock:install

Install the FloatingClock macOS app from this plugin's source to `/Applications/` so it's available from Spotlight, Launchpad, and Finder.

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
