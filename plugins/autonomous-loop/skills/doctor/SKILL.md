---
name: doctor
description: "Diagnose autonomous-loop fleet health. Reports GREEN/YELLOW/RED per loop with remediation hints. TRIGGERS - autonomous-loop doctor, fleet diagnose, loop health check, find zombie loops, loop status report."
allowed-tools: Bash
argument-hint: "[--json] [--fix]"
disable-model-invocation: false
---

<!-- # SSoT-OK -->

# autonomous-loop: Doctor

Self-diagnostic for the autonomous-loop fleet. Cross-references registry.json, heartbeat.json files, launchctl list output, plist files, and (lightly) `~/.claude/projects` JSONL transcripts to surface zombies, orphans, label collisions, multi-cwd contamination, stale bindings, and missing heartbeats.

## Arguments

- `--json` — emit structured JSON output instead of human-readable terminal report
- `--fix` — apply SAFE auto-remediations only (see "What gets fixed" below)

## Severity model

- 🔴 **RED** — known-broken state requiring action (zombie launchctl entry, multi-cwd contamination, label collision, contract file missing, cwd_drift_detected)
- 🟡 **YELLOW** — probably-OK but worth attention (pending-bind >1h, dead pid + recent heartbeat)
- 🟢 **GREEN** — healthy

## Run

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop}"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/doctor-lib.sh"

JSON=false
FIX=false
for arg in "$@"; do
  case "$arg" in
    --json) JSON=true ;;
    --fix)  FIX=true  ;;
  esac
done

if [ "$FIX" = true ]; then
  loop_doctor_fix
else
  if [ "$JSON" = true ]; then
    loop_doctor_report --json
  else
    loop_doctor_report
  fi
fi
```

## What gets fixed automatically (`--fix`)

Only operations that are reversible OR have no live side effects:

1. **Unload zombie launchctl entries** — labels matching `com.user.claude.loop.*` with no registry record. Calls `launchctl bootout gui/$(id -u)/<label>` and removes the orphan plist file.
2. **Prune `/var/folders/*` test entries** — registry entries whose `contract_path` starts with `/var/folders/` (mktemp leftovers from tests).

What `--fix` will **NEVER** do (intentionally — operator decision required):

- Spawn `claude --resume` for any reason.
- Auto-reclaim a loop with a live owner (use `/autonomous-loop:reclaim <loop_id>` instead).
- Modify a loop's `bound_cwd` or clear `cwd_drift_detected` (these mean the session went somewhere it shouldn't — only the operator can authorize recovery).
- Delete heartbeat files or state directories.

## Companion: automatic self-healing

`heal-self.sh` runs automatically on every fresh SessionStart hook fire (gated by content-hash so it does no work when the registry is unchanged). It archives entries with `owner_session_id ∈ {unknown, unknown-session, '', pending-bind}` older than 1 hour to `~/.claude/loops/registry.archive.jsonl`. The archive is append-only and forensics-friendly.

## Refs

- Library: `plugins/autonomous-loop/scripts/doctor-lib.sh`
- Companion script: `plugins/autonomous-loop/scripts/heal-self.sh`
