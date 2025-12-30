---
implementation-status: in_progress
created: 2024-12-19
mode: POC
purpose: E2E validation of Ralph workflow
---

# Ralph POC Validation Task

This task validates the complete Ralph workflow in POC mode.

## Phase 1: Basic Operations (Implementation Mode)

- [ ] Read this file and confirm you understand the task
- [ ] Create a simple Python function in `/tmp/ralph-poc-test.py` that adds two numbers
- [ ] Add a docstring to the function

## Phase 2: Documentation (Triggers Completion Detection)

- [ ] Add a brief comment explaining the test purpose
- [ ] Confirm all Phase 1 items are complete

## Phase 3: Validation Triggers

After checking all items above, Ralph should:

1. Detect task completion (all checkboxes checked = 0.9 confidence)
2. Enter VALIDATION phase (3 rounds)
3. Run validation sub-agents
4. Compute validation score

## Phase 4: Exploration Triggers

If validation passes (score >= 0.8), Ralph should:

1. Enter EXPLORATION mode
2. Scan for work opportunities
3. Report findings

## Completion Marker

- [ ] TASK_COMPLETE

---

## POC Success Criteria

When this POC completes successfully, the following should be observable:

1. **State file** at `~/.claude/automation/loop-orchestrator/state/loop-hook.json`:
   - `iteration` should increment with each loop
   - `validation_round` should progress 0 → 1 → 2 → 3
   - `validation_exhausted` should become `true`
   - `completion_signals` should contain detection method

2. **Archives** at `~/.claude/automation/loop-orchestrator/state/archives/`:
   - Multiple timestamped copies of this file as it's edited

3. **Mode transitions** in continuation prompts:
   - IMPLEMENTATION → VALIDATION → EXPLORATION → ALLOW STOP

## How to Run This POC

```bash
# 1. Ensure hooks are installed
/ralph:hooks install

# 2. Restart Claude Code

# 3. Start Ralph in POC mode with this file
/ralph:start -f plugins/ralph/hooks/tests/poc-task.md --poc

# 4. Monitor progress
/ralph:status

# 5. Emergency stop if needed
/ralph:stop
# OR: touch .claude/STOP_LOOP
```

## Expected Duration

- POC mode: 10 min max, 20 iterations max
- Typical completion: 5-10 iterations
- Validation phase: 3-6 iterations (one per round × possible retries)
