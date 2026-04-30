---
name: stop
description: "Mark LOOP_CONTRACT.md completed, append DONE section, send PushNotification, let loop terminate naturally. TRIGGERS - autonomous-loop stop, end loop, terminate contract, stop self-revising loop, complete loop."
allowed-tools: Bash, Read, Edit, AskUserQuestion, Skill
argument-hint: "[reason]"
disable-model-invocation: false
---

# autonomous-loop: Stop

Cleanly terminate a self-revising loop. Appends a `## DONE` section with timestamp + reason, sends a `PushNotification` summarizing final state, and stops scheduling new wake-ups. The next `/loop` firing will see the DONE marker and exit without acting.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Arguments

- Positional (optional): reason string. Defaults to "user-requested stop".

## Step 1: Locate contract

```bash
CONTRACT_PATH="${CONTRACT_PATH:-./LOOP_CONTRACT.md}"
if [ ! -f "$CONTRACT_PATH" ]; then
  echo "No contract at $CONTRACT_PATH — nothing to stop."
  exit 0
fi
```

If the user hasn't specified which contract, and multiple `LOOP_CONTRACT.md` files exist under the cwd, use `AskUserQuestion` to pick.

## Step 2: Confirm stop reason

Use `AskUserQuestion` to pick a stop reason:

- `Research saturation` — 3 consecutive null-rescue firings
- `Goal achieved` — completion criterion met
- `User request` — manual termination
- `Blocked on external dependency` — can't proceed without intervention

Record the chosen reason plus the free-text user note (if provided) into the DONE section.

## Step 3: Append DONE section

Append this block to the contract (use `Edit` or a Bash `cat >>`):

```markdown
---

## DONE

- **Stopped at**: <ISO 8601 UTC>
- **Iteration**: <current value from frontmatter>
- **Reason**: <chosen reason>
- **User note**: <free-text if any>
- **Final state summary**:
  <one-paragraph synthesis of the Current State section at time of stop>

The next /loop firing will observe this section and exit without further action.
```

## Step 4: Send PushNotification

Load `PushNotification` via `ToolSearch` if not already available, then send:

```
<loop-name> stopped at iter <N>. Reason: <reason>. Final state: <one-line summary>.
```

Keep under 200 chars.

## Step 5: Unload launchd plist

Before unregistering, unload the launchd plist:

```bash
# Source the launchd library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
source "$PLUGIN_ROOT/scripts/launchd-lib.sh"
source "$PLUGIN_ROOT/scripts/state-lib.sh"

# Derive loop_id and state_dir
loop_id=$(derive_loop_id "$CONTRACT_PATH")
state_dir=$(state_dir_path "$loop_id" "$CONTRACT_PATH")

# Unload plist (idempotent; no-op on non-macOS)
if ! unload_plist "$loop_id" "$state_dir" 2>/dev/null; then
  echo "WARNING: Failed to unload launchd plist" >&2
fi
```

## Step 6: Unregister loop from machine registry

After unloading the plist, clean up the machine registry entry:

```bash
# Source the registry library
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"

# Derive loop_id from contract path
loop_id=$(derive_loop_id "$CONTRACT_PATH")

# Unregister from machine registry (idempotent; no error if already absent)
if ! unregister_loop "$loop_id"; then
  echo "WARNING: Failed to unregister loop from machine registry" >&2
fi
```

## Step 7: Update frontmatter

Edit the YAML frontmatter `exit_condition` field to include `DONE` so the next firing detects it immediately without scanning the body.

## Step 8: Suggest final commit

Print a suggested commit:

```bash
git add "$CONTRACT_PATH"
git commit -m "$(cat <<'EOF'
loop(stop): <loop-name> complete — <reason>

Final iteration: <N>
Last action: <summary from Current State>
EOF
)"
```

## Anti-patterns

- Do NOT `kill -9` any running process from this skill — that's out of scope. This skill only signals the loop; separate skills (like `ru:stop` or `pueue kill`) handle process termination.
- Do NOT rewrite the Revision Log — append-only. Add a DONE section instead.
- Do NOT send `PushNotification` if the user is actively present (watch for a recent user turn in the last 60 seconds); that would be annoying. When in doubt, skip the push.

## Troubleshooting

| Symptom                            | Fix                                                                                            |
| ---------------------------------- | ---------------------------------------------------------------------------------------------- |
| `PushNotification` tool not loaded | `ToolSearch` with query `select:PushNotification` before step 4                                |
| DONE section already exists        | Loop was already stopped; print confirmation and exit                                          |
| Loop keeps firing after DONE       | The next `/loop` reading the contract should short-circuit — verify pointer trigger is correct |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update DONE-section template if needed.
3. **Log it.** — Evolution-log entry.
