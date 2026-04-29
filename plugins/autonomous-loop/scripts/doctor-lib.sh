#!/usr/bin/env bash
# doctor-lib.sh — Self-diagnostic for autonomous-loop fleet (v4.10.0 Phase 38).
# Provides: loop_doctor_report, loop_doctor_fix
#
# Cross-references registry.json, heartbeat.json files, launchctl list output,
# plist files in ~/Library/LaunchAgents, and ~/.claude/projects JSONL transcripts
# to surface zombies, orphans, label collisions, multi-cwd contamination, stale
# bindings, and missing heartbeats.
#
# Severity model:
#   RED    — known-broken state requiring action
#   YELLOW — probably-OK but worth attention
#   GREEN  — healthy
#
# loop_doctor_fix performs ONLY safe remediations: unload orphan launchctl
# entries, archive corrupted/stale registry entries to registry.archive.jsonl.
# NEVER spawns claude. NEVER auto-reclaims a live owner.

set -euo pipefail

DOCTOR_PENDING_BIND_THRESHOLD_S="${DOCTOR_PENDING_BIND_THRESHOLD_S:-3600}"

_DOCTOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$_DOCTOR_SCRIPT_DIR/registry-lib.sh" ] && source "$_DOCTOR_SCRIPT_DIR/registry-lib.sh"
# shellcheck source=/dev/null
[ -f "$_DOCTOR_SCRIPT_DIR/provenance-lib.sh" ] && source "$_DOCTOR_SCRIPT_DIR/provenance-lib.sh" 2>/dev/null || true
export _PROV_AGENT="doctor-lib.sh"

# _doctor_check_loop <entry> — emits one JSON line with verdict per loop.
_doctor_check_loop() {
  local entry="$1"
  local issues=()
  local verdict="GREEN"

  local loop_id state_dir contract_path owner_sid owner_pid owner_start_us
  loop_id=$(echo "$entry" | jq -r '.loop_id // ""')
  state_dir=$(echo "$entry" | jq -r '.state_dir // ""' | sed 's:/*$::')
  contract_path=$(echo "$entry" | jq -r '.contract_path // ""')
  owner_sid=$(echo "$entry" | jq -r '.owner_session_id // ""')
  owner_pid=$(echo "$entry" | jq -r '.owner_pid // ""')
  owner_start_us=$(echo "$entry" | jq -r '.owner_start_time_us // 0')

  # Check 1: contract file exists
  if [ -n "$contract_path" ] && [ ! -f "$contract_path" ]; then
    issues+=("RED: contract file missing at $contract_path")
    verdict="RED"
  fi

  # Check 2: pending-bind staleness
  if [ "$owner_sid" = "pending-bind" ] || [ "$owner_sid" = "unknown" ] || [ "$owner_sid" = "unknown-session" ] || [ -z "$owner_sid" ]; then
    local now_us age_s
    now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)
    age_s=$(( (now_us - owner_start_us) / 1000000 ))
    if [ "$age_s" -gt "$DOCTOR_PENDING_BIND_THRESHOLD_S" ]; then
      issues+=("YELLOW: pending-bind for ${age_s}s (>${DOCTOR_PENDING_BIND_THRESHOLD_S}s); session never started or never used the contract dir")
      [ "$verdict" = "GREEN" ] && verdict="YELLOW"
    fi
  fi

  # Check 3: heartbeat freshness
  local hb_file="$state_dir/heartbeat.json"
  if [ -n "$state_dir" ] && [ ! -f "$hb_file" ]; then
    local age_s
    age_s=$(( ($(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0) - owner_start_us) / 1000000 ))
    if [ "$age_s" -gt 3600 ]; then
      issues+=("YELLOW: no heartbeat.json (loop registered ${age_s}s ago; never ticked)")
      [ "$verdict" = "GREEN" ] && verdict="YELLOW"
    fi
  fi

  # Check 4: heartbeat cwd_drift_detected flag
  if [ -f "$hb_file" ]; then
    local drift
    drift=$(jq -r '.cwd_drift_detected // false' "$hb_file" 2>/dev/null)
    if [ "$drift" = "true" ]; then
      issues+=("RED: cwd_drift_detected — session went outside contract dir; resume disabled until /autonomous-loop:reclaim")
      verdict="RED"
    fi
  fi

  # Check 5: launchd label uniqueness (collision)
  if command -v launchctl >/dev/null 2>&1; then
    local label count
    label="com.user.claude.loop.$loop_id"
    count=$(launchctl list 2>/dev/null | awk -v lbl="$label" '$3 == lbl' | wc -l | tr -d ' ')
    if [ "${count:-0}" -ge 2 ]; then
      issues+=("RED: launchd label collision ($count entries for $label)")
      verdict="RED"
    fi
  fi

  # Check 6: owner_pid liveness vs heartbeat freshness
  if [ -n "$owner_pid" ] && [ "$owner_pid" != "null" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
    if [ -f "$hb_file" ]; then
      local last_wake_us hb_age_s
      last_wake_us=$(jq -r '.last_wake_us // 0' "$hb_file" 2>/dev/null)
      local now_us
      now_us=$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)
      hb_age_s=$(( (now_us - last_wake_us) / 1000000 ))
      if [ "$hb_age_s" -gt 3600 ]; then
        issues+=("YELLOW: owner_pid $owner_pid dead AND heartbeat ${hb_age_s}s old; reclaim candidate")
        [ "$verdict" = "GREEN" ] && verdict="YELLOW"
      fi
    fi
  fi

  # Emit JSON line for this loop
  jq -nc \
    --arg loop_id "$loop_id" \
    --arg verdict "$verdict" \
    --argjson issues "$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)" \
    --arg owner_session_id "$owner_sid" \
    --arg state_dir "$state_dir" \
    '{loop_id: $loop_id, verdict: $verdict, owner_session_id: $owner_session_id, state_dir: $state_dir, issues: $issues}'
}

# _doctor_check_zombies — scan launchctl for entries with no registry record.
_doctor_check_zombies() {
  local registry_path="${1:-$HOME/.claude/loops/registry.json}"
  if ! command -v launchctl >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -f "$registry_path" ]; then
    return 0
  fi

  local labels
  labels=$(launchctl list 2>/dev/null | awk '/com\.user\.claude\.loop\./ {print $3}')
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    local loop_id
    loop_id="${label##*.}"
    local exists
    exists=$(jq -r --arg id "$loop_id" '.loops[] | select(.loop_id == $id) | .loop_id' "$registry_path" 2>/dev/null)
    if [ -z "$exists" ]; then
      jq -nc \
        --arg loop_id "$loop_id" \
        --arg verdict "RED" \
        --arg label "$label" \
        --argjson issues "[\"RED: zombie launchctl entry ($label) — no matching registry record; run: launchctl bootout gui/\$(id -u)/$label\"]" \
        '{loop_id: $loop_id, verdict: $verdict, issues: $issues, kind: "zombie_launchctl"}'
    fi
  done <<< "$labels"
}

# loop_doctor_report [--json]
loop_doctor_report() {
  local json_mode=false
  for arg in "$@"; do
    [ "$arg" = "--json" ] && json_mode=true
  done

  local registry_path="$HOME/.claude/loops/registry.json"
  local loops_json="[]"
  if [ -f "$registry_path" ]; then
    loops_json=$(jq '.loops // []' "$registry_path" 2>/dev/null)
  fi

  local results=""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    [ "$entry" = "null" ] && continue
    local report_line
    report_line=$(_doctor_check_loop "$entry")
    results+="$report_line"$'\n'
  done < <(echo "$loops_json" | jq -c '.[]?' 2>/dev/null)

  while IFS= read -r zombie; do
    [ -z "$zombie" ] && continue
    results+="$zombie"$'\n'
  done < <(_doctor_check_zombies "$registry_path")

  if [ "$json_mode" = true ]; then
    echo "$results" | jq -s '{loops: ., generated_at_iso: (now | todate)}'
    return 0
  fi

  # Pretty terminal output
  if [ -z "$results" ]; then
    echo "No loops registered. (GREEN — nothing to diagnose.)"
    return 0
  fi
  local total green yellow red
  total=$(echo "$results" | jq -s 'length')
  green=$(echo "$results" | jq -s '[.[] | select(.verdict == "GREEN")] | length')
  yellow=$(echo "$results" | jq -s '[.[] | select(.verdict == "YELLOW")] | length')
  red=$(echo "$results" | jq -s '[.[] | select(.verdict == "RED")] | length')
  echo "autonomous-loop doctor — $total loop(s)  GREEN=$green  YELLOW=$yellow  RED=$red"
  echo "================================================================"
  echo "$results" | jq -r '.loop_id + " [" + .verdict + "]" + (if .issues|length > 0 then "\n  - " + (.issues | join("\n  - ")) else "" end)'
}

# loop_doctor_fix — applies SAFE remediations only.
loop_doctor_fix() {
  local registry_path="$HOME/.claude/loops/registry.json"
  local fixed=0

  # Fix 1: zombie launchctl entries — bootout each
  if command -v launchctl >/dev/null 2>&1 && [ -f "$registry_path" ]; then
    local labels
    labels=$(launchctl list 2>/dev/null | awk '/com\.user\.claude\.loop\./ {print $3}')
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      local loop_id
      loop_id="${label##*.}"
      local exists
      exists=$(jq -r --arg id "$loop_id" '.loops[] | select(.loop_id == $id) | .loop_id' "$registry_path" 2>/dev/null)
      if [ -z "$exists" ]; then
        echo "Unloading zombie launchctl entry: $label"
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/$label.plist" 2>/dev/null || true
        fixed=$((fixed + 1))
        if command -v emit_provenance >/dev/null 2>&1; then
          emit_provenance "$loop_id" "doctor_fixed_zombie" \
            reason="bootout + plist removal for label $label" \
            decision="proceeded" 2>/dev/null || true
        fi
      fi
    done <<< "$labels"
  fi

  # Fix 2: tmp-folder registry entries (test artefacts)
  if [ -f "$registry_path" ]; then
    local removed
    removed=$(jq '[.loops[] | select(.contract_path | startswith("/var/folders/"))] | length' "$registry_path")
    if [ "$removed" -gt 0 ]; then
      echo "Pruning $removed /var/folders/* test entries from registry"
      jq '.loops |= map(select(.contract_path | startswith("/var/folders/") | not))' "$registry_path" >"$registry_path.tmp" && mv "$registry_path.tmp" "$registry_path"
      fixed=$((fixed + removed))
    fi
  fi

  echo "Doctor fix complete. Remediations applied: $fixed"
  return 0
}

export -f loop_doctor_report
export -f loop_doctor_fix
