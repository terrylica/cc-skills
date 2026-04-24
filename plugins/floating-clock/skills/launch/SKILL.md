---
name: launch
description: "Launch FloatingClock. Prefers the installed /Applications version; falls back to the local build. Use when the user wants to open the floating-clock app."
allowed-tools: Bash
---

# /floating-clock:launch

Open the FloatingClock app.

## Steps

Prefer the installed app; fall back to the local build if the user hasn't installed yet:

```bash
if [ -d /Applications/FloatingClock.app ]; then
  open /Applications/FloatingClock.app
  echo "Launched from /Applications/"
else
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/floating-clock}"
  LOCAL_APP="$PLUGIN_ROOT/build/FloatingClock.app"
  if [ -d "$LOCAL_APP" ]; then
    open "$LOCAL_APP"
    echo "Launched from local build at $LOCAL_APP"
    echo "Tip: run /floating-clock:install to put it in /Applications/ for Spotlight access."
  else
    echo "No app found. Run /floating-clock:install first."
    exit 1
  fi
fi
```
