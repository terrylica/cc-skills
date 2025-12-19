---
description: Disable autonomous loop mode immediately
allowed-tools: Bash
argument-hint: ""
---

# Ralph Loop: Stop

Immediately disable the Ralph Wiggum autonomous improvement loop.

## Execution

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Remove loop-enabled marker
if [[ -f "$PROJECT_DIR/.claude/loop-enabled" ]]; then
    rm "$PROJECT_DIR/.claude/loop-enabled"
    echo "Ralph loop mode DEACTIVATED"
else
    echo "Loop mode was not active"
fi

# Also remove any kill switch if present
if [[ -f "$PROJECT_DIR/.claude/STOP_LOOP" ]]; then
    rm "$PROJECT_DIR/.claude/STOP_LOOP"
    echo "Removed kill switch file"
fi

# Show remaining state files
echo ""
echo "Remaining state files:"
ls -la "$PROJECT_DIR/.claude/" 2>/dev/null | grep -E "(loop|session)" || echo "  (none)"
```

Run the bash script above to disable loop mode.
