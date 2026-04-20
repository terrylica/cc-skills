---
name: status
description: "Read LOOP_CONTRACT.md frontmatter and report current iteration, last update, active monitors, and next queue item. TRIGGERS - autonomous-loop status, loop state, contract status, show loop."
allowed-tools: Bash, Read
argument-hint: "[path-to-contract]"
disable-model-invocation: false
---

# autonomous-loop: Status

Read a `LOOP_CONTRACT.md` and report concise state. Works during active firings and when inspecting a paused loop.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- Positional (optional): contract file path. Defaults to `./LOOP_CONTRACT.md`.

## Step 1: Locate contract

```bash
CONTRACT_PATH="${1:-./LOOP_CONTRACT.md}"
if [ ! -f "$CONTRACT_PATH" ]; then
  echo "No contract at $CONTRACT_PATH. Run /autonomous-loop:start first."
  exit 0
fi
```

## Step 2: Parse frontmatter

Read the file and extract YAML frontmatter between the first pair of `---` markers. Report:

| Field            | Meaning                                 |
| ---------------- | --------------------------------------- |
| `name`           | Loop identifier                         |
| `iteration`      | Current firing count                    |
| `last_updated`   | ISO timestamp of last contract revision |
| `exit_condition` | Termination rule                        |
| `max_iterations` | Soft cap                                |

Compute `minutes_since_last_update = now − last_updated` for drift detection.

## Step 3: Scan for DONE marker

Grep the body for `## DONE`, `COMPLETION_PROMISE`, or `exit_condition: done` style markers. If found, print:

```
LOOP COMPLETE — see DONE section for summary.
```

and skip remaining steps.

## Step 4: Extract recent revision log entries

Read the last 3 lines of the `## Revision Log` section to surface what the last 3 firings decided.

## Step 5: Report next queue item

Read the `## Implementation Queue` section and find the first unchecked `- [ ]` item across tiers T1 → T4.

## Step 6: Report active monitors

Run a best-effort check for armed monitors. If you have pueue installed and the user runs gpu-host-style remote jobs, check typical locations:

```bash
# Local pueue
pueue status 2>/dev/null | grep -E "Running|Queued" | head -5 || echo "no local pueue jobs"
# TaskList for in-session Monitors
```

The model should use `TaskList` / `TaskGet` to enumerate any currently-armed Monitors spawned in this session.

## Step 7: Print the report

```
=== autonomous-loop status ===
  Contract:       $CONTRACT_PATH
  Name:           <name>
  Iteration:      <n> / <max_iterations>
  Last updated:   <ISO> (<N> minutes ago)
  Exit condition: <condition>

  Last 3 firings:
    - <revision log entry>
    - <revision log entry>
    - <revision log entry>

  Next queue item: <first unchecked - [ ]>

  Active monitors: <count + one-line summary>
  Active pueue jobs: <count>
```

## Anti-patterns

- Do NOT modify the contract in this skill (read-only)
- Do NOT reformat or "fix" the frontmatter even if it looks malformed — report the issue instead

## Troubleshooting

| Symptom                      | Fix                                                        |
| ---------------------------- | ---------------------------------------------------------- |
| Frontmatter parsing fails    | Check first few lines begin with `---` and end with `---`  |
| `last_updated` shows "stale" | Contract may be orphaned — user should `:stop` or `:start` |
| Empty Revision Log           | First firing hasn't completed yet; normal                  |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update parsing if template frontmatter keys changed.
3. **Log it.** — Evolution-log entry.
