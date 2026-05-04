---
name: triage
description: "Triage autoloop fleet health. Reports GREEN/YELLOW/RED per loop with remediation hints. Renamed from 'doctor' to avoid clashing with Claude Code's built-in /doctor. TRIGGERS - autoloop triage, fleet triage, loop health check, find zombie loops, loop status report, autoloop diagnose, autoloop doctor."
allowed-tools: Bash
argument-hint: "[--json] [--fix]"
disable-model-invocation: false
---

<!-- # SSoT-OK -->

# autoloop: Triage

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

Self-diagnostic for the autoloop fleet. Cross-references registry.json, heartbeat.json files, launchctl list output, plist files, and (lightly) `~/.claude/projects` JSONL transcripts to surface zombies, orphans, label collisions, multi-cwd contamination, stale bindings, and missing heartbeats.

## Arguments

- `--json` — emit structured JSON output instead of human-readable terminal report
- `--fix` — apply SAFE auto-remediations only (see "What gets fixed" below)

## Severity model

- 🔴 **RED** — known-broken state requiring action (zombie launchctl entry, multi-cwd contamination, label collision, contract file missing, cwd_drift_detected)
- 🟡 **YELLOW** — probably-OK but worth attention (pending-bind >1h, dead pid + recent heartbeat)
- 🟢 **GREEN** — healthy

## Run

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/triage-lib.sh"

JSON=false
FIX=false
for arg in "$@"; do
  case "$arg" in
    --json) JSON=true ;;
    --fix)  FIX=true  ;;
  esac
done

if [ "$FIX" = true ]; then
  loop_triage_fix
else
  if [ "$JSON" = true ]; then
    loop_triage_report --json
  else
    loop_triage_report
  fi
fi
```

## What gets fixed automatically (`--fix`)

Only operations that are reversible OR have no live side effects:

1. **Unload zombie launchctl entries** — labels matching `com.user.claude.loop.*` with no registry record. Calls `launchctl bootout gui/$(id -u)/<label>` and removes the orphan plist file.
2. **Prune `/var/folders/*` test entries** — registry entries whose `contract_path` starts with `/var/folders/` (mktemp leftovers from tests).

What `--fix` will **NEVER** do (intentionally — operator decision required):

- Spawn `claude --resume` for any reason.
- Auto-reclaim a loop with a live owner (use `/autoloop:reclaim <loop_id>` instead).
- Modify a loop's `bound_cwd` or clear `cwd_drift_detected` (these mean the session went somewhere it shouldn't — only the operator can authorize recovery).
- Delete heartbeat files or state directories.

## Companion: automatic self-healing

`heal-self.sh` runs automatically on every fresh SessionStart hook fire (gated by content-hash so it does no work when the registry is unchanged). It archives entries with `owner_session_id ∈ {unknown, unknown-session, '', pending-bind}` older than 1 hour to `~/.claude/loops/registry.archive.jsonl`. The archive is append-only and forensics-friendly.

## Refs

- Library: `plugins/autoloop/scripts/triage-lib.sh`
- Companion script: `plugins/autoloop/scripts/heal-self.sh`

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this SKILL.md is the canonical file before any edit.
1. **What failed?** — Fix the instruction that caused it (e.g., a detection that produced false positives, a `--fix` op that wasn't actually safe).
2. **What drifted?** — Update if the registry schema, heartbeat fields, or launchctl output format changed.
3. **Log it.** — Evolution-log entry with trigger, fix, evidence.
