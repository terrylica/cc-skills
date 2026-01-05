---
description: View or modify loop configuration
allowed-tools: Read, Write, Bash, AskUserQuestion
argument-hint: "[show|edit|reset|set <key>=<value>] (runtime configurable)"
---

# Ralph Loop: Config

View or modify the Ralph Wiggum loop configuration (v3.0 unified schema).

**Runtime configurable**: Works with or without active Ralph loop. Changes apply on next iteration.

## Arguments

- `show` (default): Display current configuration with all sections
- `edit`: Interactively modify settings via AskUserQuestion
- `reset`: Reset to defaults (removes project config)
- `set <key>=<value>`: Set a specific config value (e.g., `set loop_limits.min_hours=2`)

## Configuration Schema (v3.0)

The unified config file `.claude/ralph-config.json` contains all configurable values:

### Loop Limits

| Setting          | Default | POC Mode | Description                          |
| ---------------- | ------- | -------- | ------------------------------------ |
| `min_hours`      | 4.0     | 0.083    | Minimum runtime before completion    |
| `max_hours`      | 9.0     | 0.167    | Maximum runtime (hard stop)          |
| `min_iterations` | 50      | 10       | Minimum iterations before completion |
| `max_iterations` | 99      | 20       | Maximum iterations (safety limit)    |

### Loop Detection

| Setting                | Default | Description                              |
| ---------------------- | ------- | ---------------------------------------- |
| `similarity_threshold` | 0.9     | RapidFuzz ratio for detecting repetition |
| `window_size`          | 5       | Number of outputs to track for detection |

### Completion Detection

| Setting                         | Default | Description                              |
| ------------------------------- | ------- | ---------------------------------------- |
| `confidence_threshold`          | 0.7     | Minimum confidence to trigger completion |
| `explicit_marker_confidence`    | 1.0     | Confidence for `[x] TASK_COMPLETE`       |
| `frontmatter_status_confidence` | 0.95    | Confidence for `implementation-status`   |
| `all_checkboxes_confidence`     | 0.9     | Confidence when all checkboxes checked   |
| `no_pending_items_confidence`   | 0.85    | Confidence when has `[x]` but no `[ ]`   |
| `semantic_phrases_confidence`   | 0.7     | Confidence for "task complete" phrases   |

### Validation Phase

| Setting                 | Default | Description                      |
| ----------------------- | ------- | -------------------------------- |
| `enabled`               | true    | Enable 3-round validation phase  |
| `score_threshold`       | 0.8     | Score needed to pass validation  |
| `max_iterations`        | 3       | Maximum validation cycles        |
| `improvement_threshold` | 0.1     | Required improvement to continue |

### Protection

| Setting              | Default                                   | Description                       |
| -------------------- | ----------------------------------------- | --------------------------------- |
| `protected_files`    | `loop-enabled`, `ralph-config.json`, etc. | Files protected from deletion     |
| `stop_script_marker` | `RALPH_STOP_SCRIPT`                       | Marker to bypass PreToolUse guard |

### Guidance (v3.0.0+)

| Setting      | Default | Description                                   |
| ------------ | ------- | --------------------------------------------- |
| `forbidden`  | `[]`    | Items Ralph should avoid (from AUQ or manual) |
| `encouraged` | `[]`    | Items Ralph should prioritize                 |
| `timestamp`  | `""`    | ISO 8601 timestamp of last update             |

### Constraint Scanning (v3.0.0+)

| Setting                | Default | Description                       |
| ---------------------- | ------- | --------------------------------- |
| `skip_constraint_scan` | `false` | Skip preflight constraint scanner |
| `constraint_scan`      | `null`  | Results from last constraint scan |

### Mode Flags (v3.0.0+)

| Setting           | Default | Description                            |
| ----------------- | ------- | -------------------------------------- |
| `poc_mode`        | `false` | Use POC time/iteration limits          |
| `production_mode` | `false` | Use production settings (auditability) |
| `no_focus`        | `false` | Skip focus file tracking               |

## Execution

Based on `$ARGUMENTS`:

### For `show` or empty

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_CONFIG_SHOW'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
echo "=== Ralph Configuration (v3.0) ==="
echo ""

# State
echo "--- State ---"
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"
if [[ -f "$STATE_FILE" ]]; then
    echo "State: $(jq -r '.state // "stopped"' "$STATE_FILE")"
else
    echo "State: stopped (no state file)"
fi
echo ""

# Project config
echo "--- Project Config ---"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    cat "$CONFIG_FILE" | python3 -m json.tool
else
    echo "(using defaults - no project config)"
fi
echo ""

# Legacy config (if different)
LEGACY_FILE="$PROJECT_DIR/.claude/loop-config.json"
if [[ -f "$LEGACY_FILE" ]]; then
    echo "--- Legacy Config (backward compat) ---"
    cat "$LEGACY_FILE" | python3 -m json.tool
fi

# Global defaults
echo ""
echo "--- Global Defaults Location ---"
echo "$HOME/.claude/ralph-defaults.json"
if [[ -f "$HOME/.claude/ralph-defaults.json" ]]; then
    cat "$HOME/.claude/ralph-defaults.json" | python3 -m json.tool
else
    echo "(not found - using built-in defaults)"
fi
RALPH_CONFIG_SHOW
```

### For `reset`

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_CONFIG_RESET'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rm -f "$PROJECT_DIR/.claude/ralph-config.json"
rm -f "$PROJECT_DIR/.claude/loop-config.json"
rm -f "$PROJECT_DIR/.claude/ralph-state.json"
echo "Project config reset. Using built-in defaults."
echo ""
echo "To create global defaults, write to: $HOME/.claude/ralph-defaults.json"
RALPH_CONFIG_RESET
```

### For `set <key>=<value>`

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_CONFIG_SET'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"

# Parse key=value from ARGUMENTS
ARGS="${ARGUMENTS:-}"
KEY_VALUE=$(echo "$ARGS" | sed 's/^set //')
KEY=$(echo "$KEY_VALUE" | cut -d= -f1)
VALUE=$(echo "$KEY_VALUE" | cut -d= -f2-)

if [[ -z "$KEY" || -z "$VALUE" ]]; then
    echo "Usage: /ralph:config set <key>=<value>"
    echo "Example: /ralph:config set loop_limits.min_hours=2"
    exit 1
fi

# Create config if doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"version": "3.0.0"}' > "$CONFIG_FILE"
fi

# Use jq to set nested key (supports dot notation)
# Convert dot notation to jq path: loop_limits.min_hours -> .loop_limits.min_hours
JQ_PATH=".$(echo "$KEY" | sed 's/\./\./g')"

# Detect if value is numeric or string and apply with error handling
update_config() {
    local jq_expr="$1"
    if ! jq "$jq_expr" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
        echo "ERROR: Failed to update config (jq error)" >&2
        rm -f "$CONFIG_FILE.tmp"
        exit 1
    fi
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

if [[ "$VALUE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    # Numeric value
    update_config "$JQ_PATH = $VALUE"
elif [[ "$VALUE" == "true" || "$VALUE" == "false" ]]; then
    # Boolean value
    update_config "$JQ_PATH = $VALUE"
else
    # String value
    update_config "$JQ_PATH = \"$VALUE\""
fi

echo "Set $KEY = $VALUE"
echo ""
cat "$CONFIG_FILE" | python3 -m json.tool
RALPH_CONFIG_SET
```

### For `edit`

Use the AskUserQuestion tool to prompt for new values across all configuration sections, then write to `$PROJECT_DIR/.claude/ralph-config.json`.

Example full config:

```json
{
  "version": "3.0.0",
  "state": "stopped",
  "poc_mode": false,
  "production_mode": false,
  "no_focus": false,
  "skip_constraint_scan": false,
  "loop_limits": {
    "min_hours": 4.0,
    "max_hours": 9.0,
    "min_iterations": 50,
    "max_iterations": 99
  },
  "loop_detection": {
    "similarity_threshold": 0.99,
    "window_size": 5
  },
  "completion": {
    "confidence_threshold": 0.7,
    "explicit_marker_confidence": 1.0,
    "frontmatter_status_confidence": 0.95,
    "all_checkboxes_confidence": 0.9,
    "no_pending_items_confidence": 0.85,
    "semantic_phrases_confidence": 0.7,
    "completion_phrases": ["task complete", "all done", "finished"]
  },
  "validation": {
    "enabled": true,
    "score_threshold": 0.8,
    "max_rounds": 5,
    "improvement_threshold": 0.1
  },
  "protection": {
    "protected_files": [
      ".claude/loop-enabled",
      ".claude/ralph-config.json",
      ".claude/ralph-state.json"
    ],
    "bypass_markers": ["RALPH_STOP_SCRIPT", "RALPH_START_SCRIPT"],
    "stop_script_marker": "RALPH_STOP_SCRIPT"
  },
  "guidance": {
    "forbidden": [],
    "encouraged": [],
    "timestamp": ""
  }
}
```
