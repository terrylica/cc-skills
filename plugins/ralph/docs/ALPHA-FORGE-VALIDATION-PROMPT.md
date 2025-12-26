# Ralph Hook Validation - Alpha-Forge Comprehensive Test Suite

**Version**: 8.1.6+
**Purpose**: Comprehensive validation of Ralph hooks for alpha-forge ML research workflows
**Scope**: All 3 hooks, 8 commands, adapters, filters, state management, edge cases

---

## Meta-Prompt for Alpha-Forge Maintainer

Copy this entire prompt to Claude Code when working in `~/eon/alpha-forge` or any alpha-forge worktree:

````
I need you to perform comprehensive validation of Ralph hooks for alpha-forge. Run all tests systematically.

## PHASE 1: Environment Setup

### 1.1 Version Check
```bash
# Check plugin version (should be 8.1.6+)
ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1
````

Expected: `8.1.6` or higher

### 1.2 Hook Registration Check

```bash
jq '.hooks' ~/.claude/settings.json 2>/dev/null | grep -c ralph || echo "0"
```

Expected: `2` (PreToolUse and Stop hook entries)

### 1.3 Dependencies Check

```bash
echo "jq: $(jq --version 2>&1 | head -1)"
echo "uv: $(uv --version 2>&1 | head -1)"
echo "python: $(python3 --version 2>&1)"
```

Expected: jq 1.6+, uv 0.5+, Python 3.11+

---

## PHASE 2: Project Detection (6 Strategies)

### 2.1 Root pyproject.toml Detection

```bash
cd ~/eon/alpha-forge && grep -E "alpha[-_]forge" pyproject.toml | head -3
```

Expected: Lines containing `alpha-forge` or `alpha_forge`

### 2.2 Monorepo Package Detection

```bash
grep -l -r "alpha[-_]forge" ~/eon/alpha-forge/packages/*/pyproject.toml 2>/dev/null | head -3
```

Expected: Paths to package pyproject.toml files

### 2.3 Characteristic Directory Detection

```bash
ls -d ~/eon/alpha-forge/packages/alpha-forge-core 2>/dev/null && echo "✓ Found"
```

Expected: Directory path + "✓ Found"

### 2.4 Outputs Directory Detection

```bash
ls -d ~/eon/alpha-forge/outputs/runs 2>/dev/null && echo "✓ Found" || echo "⚠ Missing (ok for worktrees)"
```

Expected: Either "✓ Found" or "⚠ Missing" (worktrees may not have this)

### 2.5 Git Remote URL Detection (NEW - Handles Sparse Checkouts)

```bash
git -C ~/eon/alpha-forge remote get-url origin 2>/dev/null | grep -qi "alpha.forge" && echo "✓ Git remote detected" || echo "✗ No match"
```

Expected: "✓ Git remote detected"

**Why this matters**: Sparse checkouts, orphan branches (like `asciinema-recordings`), and worktrees may lack file markers but HAVE the correct git remote URL.

### 2.6 Python Detection Function Test

```bash
cd ~/eon/alpha-forge && python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from core.project_detection import is_alpha_forge_project
from pathlib import Path
print(f"Current dir detected: {is_alpha_forge_project(Path.cwd())}")
print(f"Parent dir detected: {is_alpha_forge_project(Path.cwd().parent)}")
PYEOF
```

Expected: Both should be `True` for alpha-forge

---

## PHASE 3: Hook Entry Points

### 3.1 Stop Hook - Alpha-Forge Detection (Should NOT Early-Exit)

```bash
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "test-validation", "stop_hook_active": false}' 2>&1 | head -20
```

Expected: Output with `[ralph]` prefixed messages (NOT empty `{}` which means early-exit)

### 3.2 Stop Hook - Non-Alpha-Forge (SHOULD Early-Exit)

```bash
CLAUDE_PROJECT_DIR="/tmp" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "test-outside", "stop_hook_active": false}' 2>&1
```

Expected: `{}` (empty JSON = early-exit for non-alpha-forge)

### 3.3 PreToolUse Loop Guard - Alpha-Forge (Full Processing)

```bash
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/pretooluse-loop-guard.py <<< '{"command": "echo test"}' 2>&1
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}`

### 3.4 PreToolUse Loop Guard - Deletion Block

```bash
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/pretooluse-loop-guard.py <<< '{"command": "rm .claude/loop-enabled"}' 2>&1
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` with RALPH LOOP GUARD message

### 3.5 PreToolUse Loop Guard - Non-Alpha-Forge (Early-Exit)

```bash
CLAUDE_PROJECT_DIR="/tmp" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/pretooluse-loop-guard.py <<< '{"command": "rm anything"}' 2>&1
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}` (early-exit allows all)

### 3.6 Archive Plan Hook - Markers Check

```bash
cat ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/archive-plan.sh | grep -A5 "ALPHA-FORGE ONLY"
```

Expected: Guard section with `packages/alpha-forge-core`, `outputs/runs` checks

---

## PHASE 4: Command Validation

### 4.1 /ralph:hooks status

Run `/ralph:hooks status` and verify:

- [ ] Plugin location shows correct path
- [ ] All 3 hook scripts found (loop-until-done.py, archive-plan.sh, pretooluse-loop-guard.py)
- [ ] Dependencies (jq, uv, Python) all present
- [ ] No "legacy install" warning
- [ ] Documentation links displayed

### 4.2 /ralph:start (POC mode)

Run `/ralph:start --poc` and verify:

- [ ] Adapter detected as "alpha-forge"
- [ ] .claude/loop-enabled created
- [ ] ralph-config.json created with POC limits (min_hours: 0.5, max_hours: 1.0)
- [ ] State shows RUNNING

### 4.3 /ralph:status

Run `/ralph:status` and verify:

- [ ] Shows current iteration count
- [ ] Shows runtime hours
- [ ] Shows adapter name (alpha-forge)

### 4.4 /ralph:forbid

Run `/ralph:forbid "linting"` and verify:

```bash
jq '.guidance.forbidden' .claude/ralph-config.json
```

Expected: Array containing "linting"

### 4.5 /ralph:encourage

Run `/ralph:encourage "OOS robustness"` and verify:

```bash
jq '.guidance.encouraged' .claude/ralph-config.json
```

Expected: Array containing "OOS robustness"

### 4.6 /ralph:stop

Run `/ralph:stop` and verify:

- [ ] .claude/loop-enabled removed
- [ ] State shows STOPPED
- [ ] Global stop signal created (if applicable)

---

## PHASE 5: Adapter Validation

### 5.1 Adapter Detection

```bash
cd ~/eon/alpha-forge && python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from core.registry import AdapterRegistry
from pathlib import Path
AdapterRegistry.discover(Path(sys.path[0]) / "adapters")
adapter = AdapterRegistry.get_adapter(Path.cwd())
print(f"Adapter: {adapter.name if adapter else 'None'}")
print(f"Detection: {adapter.detect(Path.cwd()) if adapter else 'N/A'}")
PYEOF
```

Expected: `Adapter: alpha-forge`, `Detection: True`

### 5.2 Metrics History (if outputs/runs exists)

```bash
ls ~/eon/alpha-forge/outputs/runs/*/summary.json 2>/dev/null | head -5
```

Expected: List of summary.json paths (if runs exist)

### 5.3 Research Convergence Check

```bash
grep -l "CONVERGED" ~/eon/alpha-forge/outputs/research_sessions/*/research_log.md 2>/dev/null | head -3
```

Expected: Paths to converged sessions (or empty if none)

---

## PHASE 6: Busywork Filter Validation

### 6.1 Busywork Pattern Detection

```bash
cd ~/eon/alpha-forge && python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from alpha_forge_filter import is_busywork, get_allowed_opportunities

# Test busywork detection
test_cases = [
    "Fix ruff issues: E501 line too long",
    "Add type hints to function",
    "Improve OOS robustness",
    "Implement walk-forward validation",
]
for opp in test_cases:
    is_bw, pattern = is_busywork(opp)
    print(f"{'BUSYWORK' if is_bw else 'VALUE   '}: {opp[:50]}")
PYEOF
```

Expected: First 2 = BUSYWORK, Last 2 = VALUE

### 6.2 Encouraged Override Test

```bash
cd ~/eon/alpha-forge && python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from alpha_forge_filter import filter_opportunities, FilterResult

# Test that encouraged overrides busywork
opps = ["Fix ruff issues: E501"]
results = filter_opportunities(opps, custom_encouraged=["ruff"])
for r in results:
    print(f"Result: {r.result.value}, Reason: {r.reason}")
PYEOF
```

Expected: `Result: allow, Reason: Encouraged: matches 'ruff'`

---

## PHASE 7: State Management

### 7.1 State File Location

```bash
ls -la ~/.claude/automation/loop-orchestrator/state/sessions/ 2>/dev/null | head -5
```

Expected: Session state files with pattern `{session}@{hash}.json`

### 7.2 Inheritance Log

```bash
tail -5 ~/.claude/automation/loop-orchestrator/state/sessions/inheritance-log.jsonl 2>/dev/null
```

Expected: JSONL entries with hash chain for verification

### 7.3 Project State File

```bash
cat ~/eon/alpha-forge/.claude/ralph-state.json 2>/dev/null | jq .
```

Expected: JSON with `state`, `iteration`, timestamps

### 7.4 Project Config File

```bash
cat ~/eon/alpha-forge/.claude/ralph-config.json 2>/dev/null | jq 'keys'
```

Expected: Keys including `preset`, `loop_limits`, `guidance`, etc.

---

## PHASE 8: Edge Cases

### 8.1 Worktree Detection (Parent Traversal)

```bash
cd ~/eon/alpha-forge.worktree-*/packages 2>/dev/null && python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from core.project_detection import is_alpha_forge_project
from pathlib import Path
print(f"Nested detection: {is_alpha_forge_project(Path.cwd())}")
PYEOF
```

Expected: `True` (detects via parent traversal)

### 8.2 Stop Hook with stop_hook_active=true (Infinite Loop Prevention)

```bash
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "test", "stop_hook_active": true}' 2>&1 | grep -i "stop_hook_active\|allow"
```

Expected: Should allow stop to prevent infinite loop

### 8.3 Kill Switch Test

```bash
touch ~/eon/alpha-forge/.claude/STOP_LOOP
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "test", "stop_hook_active": false}' 2>&1 | grep -i "kill\|stop"
rm ~/eon/alpha-forge/.claude/STOP_LOOP
```

Expected: References kill switch detection

### 8.4 Sparse Checkout / Orphan Branch Detection (Git Remote)

This tests detection via git remote URL when file markers are missing (e.g., `asciinema-recordings` branch):

```bash
# Simulate sparse checkout: directory with git remote but no file markers
mkdir -p /tmp/alpha-forge-sparse && cd /tmp/alpha-forge-sparse
git init && git remote add origin https://github.com/EonLabs-Spartan/alpha-forge.git
python3 << 'PYEOF'
import sys
sys.path.insert(0, "$HOME/.claude/plugins/cache/cc-skills/ralph/$(ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1)/hooks")
from core.project_detection import is_alpha_forge_project
from pathlib import Path
print(f"Sparse checkout detected: {is_alpha_forge_project(Path.cwd())}")
PYEOF
rm -rf /tmp/alpha-forge-sparse
```

Expected: `Sparse checkout detected: True`

---

## EXPECTED OUTPUT FORMATS (v8.1.5+)

### Stop Hook Outputs

```json
{}                                           // Allow stop normally
{"systemMessage": "info text"}               // Informational (non-blocking)
{"decision": "block", "reason": "..."}       // Block stopping (force continuation)
{"continue": false, "stopReason": "..."}     // Hard stop (emergency)
```

### PreToolUse Hook Outputs

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}
```

**IMPORTANT**: Stop hooks do NOT support `hookSpecificOutput`. PreToolUse hooks do NOT use top-level `decision`.

---

## VALIDATION CHECKLIST

After running all phases, confirm:

| Category       | Test                                    | Status |
| -------------- | --------------------------------------- | ------ |
| **Detection**  | Root pyproject.toml detected            | ☐      |
| **Detection**  | packages/alpha-forge-core/ detected     | ☐      |
| **Detection**  | Git remote URL detected                 | ☐      |
| **Detection**  | Python function returns True            | ☐      |
| **Stop Hook**  | Alpha-forge = full processing           | ☐      |
| **Stop Hook**  | Non-alpha-forge = early-exit `{}`       | ☐      |
| **Loop Guard** | Alpha-forge = permissionDecision output | ☐      |
| **Loop Guard** | Deletion = deny with reason             | ☐      |
| **Loop Guard** | Non-alpha-forge = early-exit allow      | ☐      |
| **Commands**   | /ralph:hooks status works               | ☐      |
| **Commands**   | /ralph:start creates files              | ☐      |
| **Commands**   | /ralph:stop cleans up                   | ☐      |
| **Adapter**    | Alpha-forge adapter detected            | ☐      |
| **Filter**     | Busywork patterns blocked               | ☐      |
| **Filter**     | Encouraged overrides busywork           | ☐      |
| **State**      | Session files exist                     | ☐      |
| **Edge Cases** | Worktree detection works                | ☐      |
| **Edge Cases** | Kill switch triggers stop               | ☐      |
| **Edge Cases** | Sparse checkout (git remote) detected   | ☐      |

---

## TROUBLESHOOTING

If tests fail:

1. **Detection fails**: Check markers exist:

   ```bash
   ls -la ~/eon/alpha-forge/packages/alpha-forge-core ~/eon/alpha-forge/outputs/runs ~/eon/alpha-forge/pyproject.toml
   ```

2. **Hook early-exits unexpectedly**: Check CLAUDE_PROJECT_DIR is set correctly

3. **Wrong output format**: Ensure plugin version is 8.1.5+ (output formats changed)

4. **Permissions errors**: Check ~/.claude/settings.json is writable

Report issues with full test output to cc-skills maintainer.

````

---

## Quick Validation (5-Minute Smoke Test)

For rapid validation, run just these 5 commands:

```bash
# 1. Plugin version
ls ~/.claude/plugins/cache/cc-skills/ralph/ | sort -V | tail -1

# 2. Detection
cd ~/eon/alpha-forge && grep -c alpha-forge pyproject.toml

# 3. Stop hook (should show processing, not early-exit)
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/loop-until-done.py <<< '{"session_id": "smoke", "stop_hook_active": false}' 2>&1 | head -5

# 4. Loop guard (should show permissionDecision)
CLAUDE_PROJECT_DIR="$HOME/eon/alpha-forge" uv run ~/.claude/plugins/cache/cc-skills/ralph/*/hooks/pretooluse-loop-guard.py <<< '{"command": "echo test"}' 2>&1

# 5. Hooks status
/ralph:hooks status
````
