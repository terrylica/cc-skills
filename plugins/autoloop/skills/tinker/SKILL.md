---
name: tinker
description: Diagnose and repair the documented autoloop bootstrap failure modes for a registered loop. Idempotent. Use when a loop is registered but doesn't fire, when owner_session_id is stuck at "pending-bind", or after a marketplace update that may have left stale plists. Renamed from "doctor" to avoid clashing with Claude Code's /doctor. TRIGGERS - autoloop doctor, autoloop repair, autoloop fix, fix loop, repair loop, pending-bind, loop won't fire, loop not firing.
allowed-tools: Bash, Read
argument-hint: "[loop_id_or_AL_slug]"
disable-model-invocation: false
---

# autoloop: Tinker

Diagnose and repair a registered autoloop that won't fire.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Why this exists

`/autoloop:start` can finish without surfacing partial failures:

- The launchd plist may have failed to load (no fire schedule).
- The four autoloop hooks may not be in `~/.claude/settings.json` (session-bind never runs, so `owner_session_id` stays at `pending-bind` forever).
- The plist's runner script may point at a stale waker path (e.g. after a marketplace upgrade moved the plugin tree).
- `owner_session_id == "pending-bind"` may persist beyond the bind grace window.

`autoloop:tinker` runs all four diagnoses, prints a JSON report, and applies idempotent repairs. Safe to invoke at any time — healthy loops produce no changes.

## Arguments

- Positional (optional): a loop identifier in any of the three forms accepted by `resolve_loop_identifier`:
  - `<loop_id>` — bare 12 hex chars (e.g. `293399ce8573`)
  - `AL-<slug>--<hash>` — display name (e.g. `AL-mowfo-rollout--598311`)
  - `AL-<slug>` — slug only (errors with candidates if ambiguous)
- If no argument is given AND exactly one `.autoloop/<slug>--<hash>/CONTRACT.md` exists in the current working directory, infer the loop_id from the contract path. Otherwise prompt the user.

## Step 1: Resolve loop_id

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  # Try to infer from cwd
  candidates=$(compgen -G "$(pwd)/.autoloop/*--[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/CONTRACT.md" 2>/dev/null || true)
  count=$(echo -n "$candidates" | grep -c '^' || echo 0)
  if [ "$count" = "1" ]; then
    LOOP_ID=$(derive_loop_id "$candidates")
    echo "  inferred loop_id $LOOP_ID from $candidates" >&2
  else
    echo "ERROR: no argument given and could not unambiguously infer loop_id from cwd" >&2
    echo "       Try /autoloop:muster to list registered loops, then call /autoloop:tinker <loop_id>." >&2
    exit 1
  fi
else
  LOOP_ID=$(resolve_loop_identifier "$INPUT") || exit 1
fi
```

## Step 2: Diagnose

```bash
source "$PLUGIN_ROOT/scripts/tinker-lib.sh"
diagnosis=$(diagnose_loop "$LOOP_ID")
echo "$diagnosis" | jq .
```

Show the user the diagnosis JSON before any repair. If `failure_modes` is empty, print `[HEALTHY]` and exit 0.

## Step 3: Confirm before repair

If `failure_modes` is non-empty, summarize what each repair will do:

| Mode                    | Repair                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------- |
| `F1_missing_plist`      | `generate_plist` + `load_plist` for the loop's state_dir + cadence                                |
| `F2_missing_hooks`      | Install all 4 autoloop hooks (heartbeat / session-bind / pacing-veto / empty-firing) idempotently |
| `F3_pending_bind_stale` | Patch `owner_session_id` from `pending-bind` → caller's session UUID (atomic)                     |
| `F4_stale_waker_path`   | Unload + delete + regenerate plist using the current plugin's waker.sh                            |

Use `AskUserQuestion` with options `Repair all` / `Diagnose only`. Default: `Repair all`.

## Step 4: Repair

If user chose `Repair all`:

```bash
# CLAUDE_SESSION_ID is reliably set in the SKILL.md tool-invocation environment
# even though it is NOT set in subprocess Bash (anthropics/claude-code#47018).
# When this skill is invoked, $CLAUDE_SESSION_ID is what the user's current
# session-bind would have written, so we pass it through to F3 repair.
SESSION_UUID="${CLAUDE_SESSION_ID:-}"
tinker_repair_all_for_loop "$LOOP_ID" "$SESSION_UUID"
```

If `SESSION_UUID` is empty (not set in this Claude version), F3 is skipped with a printed instruction telling the user to open a fresh session in the loop's cwd to trigger session-bind.sh naturally.

## Step 5: Verify

After repair, re-run `diagnose_loop` and assert `failure_modes == []`. If any failure mode persists, print the residual diagnosis and exit 1 so the user knows manual intervention is needed.

```bash
post=$(diagnose_loop "$LOOP_ID")
remaining=$(echo "$post" | jq -r '.failure_modes | length')
if [ "$remaining" = "0" ]; then
  echo "  [HEALTHY] all repairs succeeded"
  exit 0
else
  echo "  [PARTIAL] residual failure modes:"
  echo "$post" | jq '.failure_modes'
  exit 1
fi
```

## Anti-patterns

- Do NOT delete the contract file or the revision-log when repairing. Tinker is non-destructive.
- Do NOT overwrite a real owner_session_id (e.g. when another session legitimately holds the loop). The F3 repair refuses to patch when the registry's `owner_session_id` is already a valid UUID.
- Do NOT use tinker as a substitute for `/autoloop:reclaim` when ownership transfer is the actual goal — those are different operations.

## Troubleshooting

| Symptom                                | Likely cause                                                                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F2 keeps reappearing after repair      | Another tool is rewriting `~/.claude/settings.json` and stripping autoloop hooks. Inspect the SessionStart / PostToolUse arrays for any wrapper that overwrites them. |
| F1 repair fails with "waker not found" | Plugin install is broken. Try `claude plugin reinstall autoloop@cc-skills`.                                                                                           |
| F3 SKIPPED ("no session_uuid")         | Open a fresh Claude Code session in the loop's contract dir; session-bind.sh fires automatically.                                                                     |
| F4 false-positive after fresh install  | Should not happen — the F4 check no longer compares paths literally; only checks file existence on disk. If you see it, file an issue against the cc-skills plugin.   |

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md's path before any edit.
1. **What failed?** — Fix the instruction that caused it.
2. **What drifted?** — Update the failure-mode table if a new mode appeared.
3. **Log it.** — Evolution-log entry with trigger, fix, evidence.
