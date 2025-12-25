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

# ===== HOLISTIC PROJECT DIRECTORY RESOLUTION =====
# Uses multiple detection methods with priority and validation
# Fix for: cross-directory invocation bug (v7.16.0)

resolve_project_dir() {
    local resolved=""

    # Priority 1: CLAUDE_PROJECT_DIR (highest priority - set by Claude Code)
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "$CLAUDE_PROJECT_DIR" ]]; then
        resolved="$CLAUDE_PROJECT_DIR"
    fi

    # Priority 2: Git root (provides repo boundary)
    if [[ -z "$resolved" ]]; then
        local git_root
        git_root=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$git_root" && -d "$git_root" ]]; then
            resolved="$git_root"
        fi
    fi

    # Priority 3: pwd (lowest priority fallback)
    if [[ -z "$resolved" ]]; then
        resolved="$(pwd)"
    fi

    echo "$resolved"
}

# ===== SESSION DISCOVERY =====
SESSIONS_DIR="$HOME/.claude/automation/loop-orchestrator/state/sessions"
STOPPED_COUNT=0
declare -A STOPPED_PROJECTS  # Track already-stopped projects (dedup)

stop_project() {
    local PROJECT_DIR="$1"
    local SOURCE="$2"
    local STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"
    local CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"

    # Skip if already stopped this project (dedup)
    if [[ -n "${STOPPED_PROJECTS[$PROJECT_DIR]:-}" ]]; then
        return 0
    fi

    # Skip if no .claude directory (not a Ralph-enabled project)
    if [[ ! -d "$PROJECT_DIR/.claude" ]]; then
        return 0
    fi

    # Set state to stopped
    echo '{"state": "stopped"}' > "$STATE_FILE"

    # Create kill switch
    touch "$PROJECT_DIR/.claude/STOP_LOOP"

    # Update config if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        jq '.state = "stopped"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    # Clean legacy markers
    rm -f "$PROJECT_DIR/.claude/loop-enabled"
    rm -f "$PROJECT_DIR/.claude/loop-start-timestamp"

    echo "  [$SOURCE] Stopped: $PROJECT_DIR"
    STOPPED_PROJECTS["$PROJECT_DIR"]=1
    ((STOPPED_COUNT++))
}

echo "Discovering active sessions (holistic resolution)..."

# Method 1: Scan session state files for project_path
if [[ -d "$SESSIONS_DIR" ]]; then
    for STATE_FILE in "$SESSIONS_DIR"/*.json; do
        [[ -f "$STATE_FILE" ]] || continue

        PROJECT_PATH=$(jq -r '.project_path // empty' "$STATE_FILE" 2>/dev/null)

        if [[ -n "$PROJECT_PATH" && -d "$PROJECT_PATH" ]]; then
            stop_project "$PROJECT_PATH" "session-state"

            # Also update session state to prevent continuation
            jq '.adapter_convergence.should_continue = false' "$STATE_FILE" > "$STATE_FILE.tmp" \
                && mv "$STATE_FILE.tmp" "$STATE_FILE"
        fi
    done
fi

# Method 2: Resolve current context using holistic detection
CURRENT_PROJECT=$(resolve_project_dir)
if [[ -d "$CURRENT_PROJECT/.claude" ]]; then
    CURRENT_STATE=$(jq -r '.state // "stopped"' "$CURRENT_PROJECT/.claude/ralph-state.json" 2>/dev/null || echo "stopped")
    if [[ "$CURRENT_STATE" != "stopped" ]]; then
        stop_project "$CURRENT_PROJECT" "holistic"
    fi
fi

# Method 3: Check parent directories for nested repos (monorepo support)
check_parents() {
    local dir="$1"
    local max_depth=3
    local depth=0

    while [[ "$dir" != "/" && $depth -lt $max_depth ]]; do
        if [[ -f "$dir/.claude/ralph-state.json" ]]; then
            local state
            state=$(jq -r '.state // "stopped"' "$dir/.claude/ralph-state.json" 2>/dev/null || echo "stopped")
            if [[ "$state" != "stopped" ]]; then
                stop_project "$dir" "parent-walk"
            fi
        fi
        dir=$(dirname "$dir")
        ((depth++))
    done
}
check_parents "$(pwd)"

# Method 4: Create global stop signal (version-agnostic, works across cached versions)
# This signal is checked by the Stop hook BEFORE any project-specific checks
echo '{"state": "stopped", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$HOME/.claude/ralph-global-stop.json"
echo "  [global] Created ~/.claude/ralph-global-stop.json"
((STOPPED_COUNT++))

# Summary
echo ""
echo "Stopped $STOPPED_COUNT location(s)."
echo "Loop stop complete."
RALPH_STOP_SCRIPT
```

Run the bash script above to disable loop mode.
