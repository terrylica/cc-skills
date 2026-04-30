---
name: reclaim
description: "Reclaim a stuck loop from a dead or unresponsive owner. Check reclaim candidacy, prompt confirmation, atomically take ownership and increment generation. TRIGGERS - autonomous-loop reclaim, recover stuck loop, take over dead loop, seize ownership."
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: "[loop-id]"
disable-model-invocation: false
---

# autonomous-loop: Reclaim

Forcibly reclaim ownership of a loop that appears stuck (dead owner or stale heartbeat). This skill performs an atomic takeover, increments the generation counter, and logs the event in the revision-log.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- Positional (optional): `loop_id` (12 hex characters). If not provided, prompt user or search registry.

## Step 1: Identify the loop

If `loop_id` not provided as argument:

```bash
LOOP_ID="${1:-}"
if [ -z "$LOOP_ID" ]; then
  # Prompt user to select from registry
  # Or search for LOOP_CONTRACT.md files and derive their IDs
  # For simplicity: require explicit loop_id argument
  echo "ERROR: loop_id required. Provide as argument: /autonomous-loop:reclaim <loop_id>"
  exit 1
fi
```

Validate format (must be 12 hex characters):

```bash
if ! [[ "$LOOP_ID" =~ ^[0-9a-f]{12}$ ]]; then
  echo "ERROR: Invalid loop_id format. Expected 12 hex characters, got: $LOOP_ID"
  exit 1
fi
```

## Step 2: Source ownership library and check reclaim candidacy

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
source "$PLUGIN_ROOT/scripts/ownership-lib.sh" || {
  echo "ERROR: Failed to source ownership-lib.sh" >&2
  exit 1
}
```

Check if the loop is a reclaim candidate:

```bash
CANDIDATE=$(is_reclaim_candidate "$LOOP_ID")

if [ "$CANDIDATE" = "no" ]; then
  echo "ERROR: Loop $LOOP_ID does not exist in the registry."
  exit 1
elif [ "$CANDIDATE" = "owner_alive" ]; then
  echo "ERROR: Loop $LOOP_ID has a live owner and fresh heartbeat. Reclaim not needed."
  echo "       Use /autonomous-loop:stop to cleanly terminate an active loop."
  exit 1
fi
```

If `$CANDIDATE = "yes"`, proceed to Step 3.

## Step 3: Show owner info and prompt confirmation

Read the registry entry to display owner information:

```bash
ENTRY=$(jq ".loops[] | select(.loop_id == \"$LOOP_ID\")" "$HOME/.claude/loops/registry.json" 2>/dev/null)

if [ -z "$ENTRY" ] || [ "$ENTRY" = "{}" ]; then
  echo "ERROR: Registry entry not found for loop $LOOP_ID"
  exit 1
fi

OWNER_PID=$(echo "$ENTRY" | jq -r '.owner_pid // "unknown"')
OWNER_SESSION=$(echo "$ENTRY" | jq -r '.owner_session_id // "unknown"')
GENERATION=$(echo "$ENTRY" | jq -r '.generation // 0')
CONTRACT_PATH=$(echo "$ENTRY" | jq -r '.contract_path // "unknown"')
STALENESS=$(staleness_seconds "$LOOP_ID")
```

Format confirmation message:

```
Loop: $LOOP_ID
Current owner PID: $OWNER_PID
Current owner session: $OWNER_SESSION (last seen $STALENESS seconds ago)
Current generation: $GENERATION
Contract path: $CONTRACT_PATH

WARNING: Reclaiming will:
  1. Increment generation counter to $(($GENERATION + 1))
  2. Transfer ownership to this session
  3. Log a takeover event in the revision-log
  4. The original owner may conflict if it resumes

Proceed with reclaim?
```

Use `AskUserQuestion` with "Yes, reclaim" / "Cancel" options.

If user selects "Cancel", exit with status 0 (not an error).

## Step 4: Atomically reclaim the loop

Once confirmed:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
source "$PLUGIN_ROOT/scripts/ownership-lib.sh" || exit 1

if reclaim_loop "$LOOP_ID" --reason "user_request"; then
  echo "✓ Loop reclaimed successfully"
  echo "  New generation: $(($(jq ".loops[] | select(.loop_id == \"$LOOP_ID\") | .generation" "$HOME/.claude/loops/registry.json"))))"
  exit 0
else
  echo "ERROR: Failed to reclaim loop (it may have been reclaimed or deleted)"
  exit 1
fi
```

## Step 5: Print next steps

After successful reclaim:

```
Ready to resume the loop. Next steps:

1. Review the contract at: $CONTRACT_PATH
2. Verify its state (iteration, Current State section, etc.)
3. Run /autonomous-loop:start $CONTRACT_PATH to resume

Or, to clean up:
4. Run /autonomous-loop:stop $CONTRACT_PATH if the loop is no longer needed
```

## Anti-patterns

- Do NOT reclaim an active loop without confirmation — this will conflict with the running owner
- Do NOT change the contract file before the new owner reads it — generation mismatch will cause confusion
- Do NOT use reclaim as a workaround for slow loops — use `/autonomous-loop:stop` and `/autonomous-loop:start` instead

## Troubleshooting

| Symptom                                | Fix                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------- |
| "does not exist in the registry"       | Loop was never registered; use `/autonomous-loop:start` instead             |
| "has a live owner and fresh heartbeat" | Don't forcibly reclaim; use `/autonomous-loop:stop` to shut it down cleanly |
| "Failed to reclaim loop"               | Registry file was deleted or unreadable; reinstall the plugin               |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update confirmation message template if needed.
3. **Log it.** — Evolution-log entry.
