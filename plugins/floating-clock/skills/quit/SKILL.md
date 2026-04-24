---
name: quit
description: "Terminate the running FloatingClock process. Use when the user wants to stop or close the floating-clock app."
allowed-tools: Bash
---

# /floating-clock:quit

Terminate any running FloatingClock process.

## Steps

```bash
if pgrep -f "FloatingClock.app/Contents/MacOS/floating-clock" >/dev/null 2>&1; then
  pkill -f "FloatingClock.app/Contents/MacOS/floating-clock"
  echo "FloatingClock quit."
else
  echo "FloatingClock is not running."
fi
```
