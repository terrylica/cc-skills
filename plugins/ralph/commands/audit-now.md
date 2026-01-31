---
description: Force immediate validation round
allowed-tools: Bash
argument-hint: "[round-number]"
---

# Ralph Loop: Audit Now

Force the loop to enter validation mode on the next iteration.
Useful for triggering early validation before natural completion signals.

## Usage

- `/ralph:audit-now` - Start validation from round 1
- `/ralph:audit-now 4` - Start from round 4 (Adversarial Probing)
- `/ralph:audit-now 5` - Start from round 5 (Cross-Period Robustness)

## Execution

```bash
# Use /usr/bin/env bash for macOS zsh compatibility
/usr/bin/env bash << 'RALPH_AUDIT_SCRIPT'
# RALPH_AUDIT_SCRIPT marker - required for PreToolUse hook bypass
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_FILE="$PROJECT_DIR/.claude/ralph-config.json"
STATE_FILE="$PROJECT_DIR/.claude/ralph-state.json"

# Get optional round number argument
ROUND="${ARGUMENTS:-1}"

# Validate round number (1-5)
if ! [[ "$ROUND" =~ ^[1-5]$ ]]; then
    echo "Error: Round must be 1-5"
    echo ""
    echo "5-Round Validation System:"
    echo "  1: Critical Issues (ruff errors, imports, syntax)"
    echo "  2: Verification (verify fixes, regression check)"
    echo "  3: Documentation (docstrings, coverage gaps)"
    echo "  4: Adversarial Probing (edge cases, math validation)"
    echo "  5: Cross-Period Robustness (Bull/Bear/Sideways)"
    exit 1
fi

# Ensure config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{}' > "$CONFIG_FILE"
fi

# Check if loop is running
CURRENT_STATE="stopped"
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE=$(jq -r '.state // "stopped"' "$STATE_FILE" 2>/dev/null || echo "stopped")
fi

if [[ "$CURRENT_STATE" != "running" ]]; then
    echo "Warning: Ralph loop not running (state: $CURRENT_STATE)"
    echo "Force validation flag will be set but may not take effect until loop starts."
fi

# Set force validation flag
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if ! jq --argjson round "$ROUND" --arg ts "$TIMESTAMP" \
    '.force_validation = {enabled: true, round: $round, timestamp: $ts}' \
    "$CONFIG_FILE" > "$CONFIG_FILE.tmp"; then
    echo "ERROR: Failed to update config file (jq error)" >&2
    rm -f "$CONFIG_FILE.tmp"
    exit 1
fi
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Force validation enabled"
echo ""
echo "Settings:"
echo "  Starting round: $ROUND"
echo "  Timestamp: $TIMESTAMP"
echo ""
echo "5-Round Validation System:"
case "$ROUND" in
    1) echo "  → Round 1: Critical Issues (ruff errors, imports, syntax)" ;;
    2) echo "  → Round 2: Verification (verify fixes, regression check)" ;;
    3) echo "  → Round 3: Documentation (docstrings, coverage gaps)" ;;
    4) echo "  → Round 4: Adversarial Probing (edge cases, math validation)" ;;
    5) echo "  → Round 5: Cross-Period Robustness (Bull/Bear/Sideways)" ;;
esac
echo ""
echo "Effect: Loop will enter validation mode on next iteration"
echo "The force_validation flag will be cleared after validation starts"
RALPH_AUDIT_SCRIPT
```

Run the bash script above to force validation mode.

## How It Works

1. **Sets force_validation flag**: Written to `.claude/ralph-config.json`
2. **Loop checks flag**: On next Stop hook, enters validation mode
3. **Flag cleared**: After validation starts, flag is reset to prevent loops
4. **Round selection**: Can start from any round (1-5) for targeted auditing

## 5-Round Validation System

| Round | Name                    | Purpose                                           |
| ----- | ----------------------- | ------------------------------------------------- |
| 1     | Critical Issues         | Find blocking bugs (ruff errors, imports, syntax) |
| 2     | Verification            | Confirm round 1 fixes, regression check           |
| 3     | Documentation           | Docstrings, coverage gaps                         |
| 4     | Adversarial Probing     | Edge cases, math validation, stress testing       |
| 5     | Cross-Period Robustness | Bull/Bear/Sideways market regime testing          |

## Use Cases

- **Early validation**: Trigger before natural completion
- **Targeted auditing**: Skip to round 4/5 for specific checks
- **Math validation**: Use `/ralph:audit-now 4` for adversarial probing
- **Robustness check**: Use `/ralph:audit-now 5` for regime testing

## Troubleshooting

| Issue                  | Cause                    | Solution                          |
| ---------------------- | ------------------------ | --------------------------------- |
| Round must be 1-5      | Invalid round number     | Use a number between 1 and 5      |
| Loop not running       | State is stopped/paused  | Run `/ralph:start` first          |
| Config file error      | Invalid JSON in config   | Delete and recreate config        |
| Validation not running | Loop hasn't iterated yet | Wait for next Stop hook iteration |
