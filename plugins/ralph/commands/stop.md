---
description: Disable autonomous loop mode immediately
allowed-tools: Bash
argument-hint: ""
---

# Ralph Loop: Stop

Immediately disable the Ralph Wiggum autonomous improvement loop.

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_STOP_SCRIPT'
# RALPH_STOP_SCRIPT marker - required for PreToolUse hook bypass
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Create kill switch FIRST as backup (not blocked by PreToolUse guard)
# This ensures the Stop hook will see it and clean up properly
touch "$PROJECT_DIR/.claude/STOP_LOOP"
echo "Created kill switch for Stop hook"

# Remove loop-enabled marker and timestamp
if [[ -f "$PROJECT_DIR/.claude/loop-enabled" ]]; then
    rm "$PROJECT_DIR/.claude/loop-enabled"
    rm -f "$PROJECT_DIR/.claude/loop-start-timestamp"
    echo "Ralph loop mode DEACTIVATED"
else
    echo "Loop mode was not active"
fi

# Show remaining state files
echo ""
echo "Remaining state files:"
ls -la "$PROJECT_DIR/.claude/" 2>/dev/null | grep -E "(loop|session|STOP)" || echo "  (none)"
RALPH_STOP_SCRIPT
```

Run the bash script above to disable loop mode.
