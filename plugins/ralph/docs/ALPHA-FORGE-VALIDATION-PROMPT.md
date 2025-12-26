# Ralph Hook Validation - Alpha-Forge Meta-Prompt

**Version**: 8.1.5+
**Purpose**: Validate Ralph hooks function correctly within alpha-forge

Copy this prompt to Claude Code when working in `~/eon/alpha-forge`:

---

## Meta-Prompt for Alpha-Forge Maintainer

````
I need you to validate Ralph hooks are functioning correctly in alpha-forge. Run these tests:

### Test 1: Verify Project Detection
Run this command and confirm alpha-forge is detected:

cd ~/eon/alpha-forge && python3 -c "
import sys
sys.path.insert(0, '$HOME/.claude/plugins/cache/cc-skills/ralph/$(cat $HOME/.claude/plugins/cache/cc-skills/.claude-plugin/manifest.json 2>/dev/null | jq -r '.version' || echo 'latest')/hooks')
from core.project_detection import is_alpha_forge_project
print(f'alpha-forge detected: {is_alpha_forge_project(\".\")}')"

Expected: `alpha-forge detected: True`

### Test 2: Verify Loop Guard Activates (Not Early-Exit)
This should show Ralph processing the command (not early-exit):

CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/pretooluse-loop-guard.py <<< '{"command": "echo test"}'

Expected (modern permissionDecision format):
`{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}`

### Test 3: Verify Stop Hook Activates
This tests the Stop hook processes normally (doesn't early-exit):

CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "validation-test", "stop_hook_active": false}'

Expected: Output with Ralph processing (session state, metrics, etc.) or `{}` for allow stop
Note: Stop hooks use `systemMessage` for informational output (NOT hookSpecificOutput)

### Test 4: Functional Test - Start/Stop Loop
1. Run `/ralph:start` - should activate loop mode
2. Verify `.claude/loop-enabled` is created
3. Run `/ralph:stop` - should deactivate
4. Verify `.claude/loop-enabled` is removed

### Test 5: Hook Status Check
Run `/ralph:hooks status` and verify:
- All 3 hooks show as registered
- No "legacy install" warnings
- Dependencies (uv, jq, Python 3.11+) all present

---

## Expected Behavior Summary

| Hook | In alpha-forge | Outside alpha-forge |
|------|---------------|---------------------|
| Stop (loop-until-done.py) | Full RSSI processing | Early-exit `{}` |
| PreToolUse (loop-guard.py) | Full protection, `permissionDecision` output | Early-exit with `permissionDecision: allow` |
| PreToolUse (archive-plan.sh) | Archives plans | Early-exit (no-op) |

## Hook Output Formats (v8.1.5+)

**PreToolUse hooks** use `hookSpecificOutput` with `permissionDecision`:
```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}
````

**Stop hooks** use top-level fields (NOT hookSpecificOutput):

```json
{}                                    // Allow stop normally
{"systemMessage": "..."}              // Informational (non-blocking)
{"decision": "block", "reason": "..."} // Block stopping (force continuation)
```

## Troubleshooting

If hooks early-exit in alpha-forge, check detection markers:

- `packages/alpha-forge-core/` directory exists
- `outputs/runs/` directory exists
- `pyproject.toml` contains "alpha-forge" or "alpha_forge"

Report any issues to cc-skills maintainer.

````

---

## Quick Validation Commands (Copy-Paste Ready)

```bash
# 1. Check plugin version
cat ~/.claude/plugins/cache/cc-skills/.claude-plugin/manifest.json | jq -r '.version'

# 2. Check hooks are installed
jq '.hooks' ~/.claude/settings.json | grep -A2 ralph

# 3. Run hooks status
# (invoke /ralph:hooks status in Claude Code)

# 4. Test detection
cd ~/eon/alpha-forge && ls -la packages/alpha-forge-core outputs/runs pyproject.toml
````
