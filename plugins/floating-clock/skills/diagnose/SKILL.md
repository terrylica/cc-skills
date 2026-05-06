---
name: diagnose
description: Print a compact health report for FloatingClock. Covers binary info, code-sign status, running process, and test-suite status. Use when a user.
allowed-tools: Bash
---

# /floating-clock:diagnose

Emit a one-page diagnostic summary.

> **Self-Evolving Skill**: This skill improves through use. If a check is wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Steps

Run a sequence of read-only checks. Safe to invoke at any time — does
not modify files, does not touch NSUserDefaults.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/floating-clock}"
APP_SYS="/Applications/FloatingClock.app"
APP_LOCAL="$PLUGIN_ROOT/build/FloatingClock.app"

echo "=== FloatingClock diagnostic ==="
echo

# Installed app
if [ -d "$APP_SYS" ]; then
  echo "[installed]  $APP_SYS"
  BIN="$APP_SYS/Contents/MacOS/floating-clock"
  if [ -x "$BIN" ]; then
    file "$BIN" | sed 's/^/             /'
    stat -f "             size: %z bytes" "$BIN"
  fi
  codesign -dv --verbose=0 "$APP_SYS" 2>&1 | sed 's/^/             /'
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    -c "Print :CFBundleVersion" "$APP_SYS/Contents/Info.plist" 2>/dev/null \
    | paste - - | sed 's/^/             version: /; s/\t/ · build /'
else
  echo "[installed]  not found (use /floating-clock:install)"
fi
echo

# Local build
if [ -d "$APP_LOCAL" ]; then
  echo "[local]      $APP_LOCAL"
  BIN="$APP_LOCAL/Contents/MacOS/floating-clock"
  if [ -x "$BIN" ]; then
    stat -f "             size: %z bytes" "$BIN"
  fi
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    -c "Print :CFBundleVersion" "$APP_LOCAL/Contents/Info.plist" 2>/dev/null \
    | paste - - | sed 's/^/             version: /; s/\t/ · build /'
else
  echo "[local]      not built (run: cd $PLUGIN_ROOT && make all)"
fi
echo

# Running process
PIDS=$(pgrep -f "FloatingClock.app/Contents/MacOS/floating-clock" 2>/dev/null)
if [ -n "$PIDS" ]; then
  echo "[process]    running · pid(s) $PIDS"
  ps -o pid,rss,%cpu,etime -p $PIDS | tail -n +2 | sed 's/^/             /'
else
  echo "[process]    not running"
fi
echo

# Current profile (if defaults exist)
ACTIVE=$(defaults read com.terryli.floating-clock ActiveProfile 2>/dev/null)
if [ -n "$ACTIVE" ]; then
  echo "[profile]    active: $ACTIVE"
else
  echo "[profile]    defaults not initialized (run the app first)"
fi
echo

# Test-suite status (quick — just runs existing test binary, skips rebuild)
TEST_BIN="$PLUGIN_ROOT/build/test_session"
if [ -x "$TEST_BIN" ]; then
  echo "[tests]      running cached test binary…"
  "$TEST_BIN" 2>&1 | tail -1 | sed 's/^/             /'
else
  echo "[tests]      build/test_session not found (run: cd $PLUGIN_ROOT && make check)"
fi

echo
echo "=== diagnostic complete ==="
```

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the report surface what the user needed?** — If a missing field would have helped (signing details, plist key, recent crash log), add it.
2. **Did any check produce false signals?** — Tighten the predicate or remove the check.
3. **Did paths or artifact names drift?** — Update the script (binary path, app bundle path, test binary location) so the next invocation matches reality.

Only update if the issue is real and reproducible — not speculative.
