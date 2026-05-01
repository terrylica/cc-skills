#!/usr/bin/env bash
# doctor-lib.sh — Self-diagnostic for autoloop fleet (v4.10.0 Phase 38).
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
# v16.9.1: defensively silence inherited xtrace at source time so function
# definitions don't dump to stderr/stdout when this file is sourced.
set +x 2>/dev/null || true

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
    # v16.9.1: defensive — owner_start_us must be a positive integer in
    # microseconds. Empty/0/non-numeric → flag as corrupted entry instead
    # of computing absurd 56-year ages.
    case "$owner_start_us" in
      ''|*[!0-9]*|0)
        issues+=("YELLOW: owner_start_time_us is invalid or zero (\"${owner_start_us}\") — registry entry corrupt")
        [ "$verdict" = "GREEN" ] && verdict="YELLOW"
        ;;
      *)
        age_s=$(( (now_us - owner_start_us) / 1000000 ))
        if [ "$age_s" -gt "$DOCTOR_PENDING_BIND_THRESHOLD_S" ]; then
          issues+=("YELLOW: pending-bind for ${age_s}s (>${DOCTOR_PENDING_BIND_THRESHOLD_S}s); session never started or never used the contract dir")
          [ "$verdict" = "GREEN" ] && verdict="YELLOW"
        fi
        ;;
    esac
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
      issues+=("RED: cwd_drift_detected — session went outside contract dir; resume disabled until /autoloop:reclaim")
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

  # Check 6.5 (v16.8.1): DONE-status contract still loaded.
  # Reads contract frontmatter for `status:` line. If it starts with DONE,
  # COMPLETE, FINISHED, or SUPERSEDED (case-insensitive), the loop is stale
  # and should be cleaned. Eligible for auto-fix.
  if [ -n "$contract_path" ] && [ -f "$contract_path" ]; then
    local contract_status
    contract_status=$(awk '
      /^---$/{n++; next}
      n==1 && /^status:[[:space:]]*/ {
        sub(/^status:[[:space:]]*/, "")
        gsub(/^"|"$|^'\''|'\''$/, "")
        print
        exit
      }
      n==1 && NR > 30 { exit }
    ' "$contract_path" 2>/dev/null || echo "")
    if echo "$contract_status" | grep -qiE '^(done|complete|finished|superseded|stopped|aborted)\b'; then
      issues+=("YELLOW: contract status='${contract_status:0:60}' but loop still loaded — run doctor --fix to clean (auto-fix removes plist + registry entry + state dir)")
      [ "$verdict" = "GREEN" ] && verdict="YELLOW"
    fi
  fi

  # Pacing-vetoed and empty-firing patterns are FLEET-level metrics — moved
  # out of _doctor_check_loop in v16.9.1 because the counts are global but
  # the attribution-per-loop was misleading (every loop showed the same N
  # pacing-vetoed). Now surfaced once at the top of loop_doctor_report.

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
  # v16.9.1: defensively silence any inherited xtrace so trace output can't
  # leak into our JSON-emitting pipeline.
  set +x 2>/dev/null || true

  local json_mode=false
  for arg in "$@"; do
    [ "$arg" = "--json" ] && json_mode=true
  done

  local registry_path="$HOME/.claude/loops/registry.json"
  local loops_json="[]"
  # W2.1 (a): explicit registry corruption check. The pre-existing `jq … 2>/dev/null`
  # below silently fell through to `loops_json="[]"` on parse failure, so a
  # corrupted registry looked identical to an empty one. Surface as RED.
  local registry_corrupt=false
  if [ -f "$registry_path" ]; then
    if ! jq empty "$registry_path" >/dev/null 2>&1; then
      registry_corrupt=true
    else
      loops_json=$(jq '.loops // []' "$registry_path" 2>/dev/null)
    fi
  fi

  # v16.9.1: filter _doctor_check_loop output to only JSON lines.
  # Defends against trace bleed, debug echoes, or other stray stdout.
  local results=""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    [ "$entry" = "null" ] && continue
    local report_line
    report_line=$(_doctor_check_loop "$entry" 2>/dev/null | grep -E '^\{.*\}$' | head -1)
    [ -z "$report_line" ] && continue
    results+="$report_line"$'\n'
  done < <(echo "$loops_json" | jq -c '.[]?' 2>/dev/null)

  while IFS= read -r zombie; do
    [ -z "$zombie" ] && continue
    case "$zombie" in
      \{*\}) results+="$zombie"$'\n' ;;
      *) ;;
    esac
  done < <(_doctor_check_zombies "$registry_path" 2>/dev/null)

  # v16.9.1: fleet-level metrics computed once at the report level.
  local global_prov pacing_vetoed empty_firings
  global_prov="${PROVENANCE_GLOBAL_FILE:-$HOME/.claude/loops/global-provenance.jsonl}"
  pacing_vetoed=0
  empty_firings=0
  if [ -f "$global_prov" ]; then
    # v16.9.1: grep -c ALWAYS outputs the count (even 0); the non-zero exit
    # on no-match is swallowed by `|| true` without writing extra output to
    # the captured stdout (avoids SIGPIPE / "0\n0" concatenation).
    pacing_vetoed=$(grep -c '"event":"pacing_vetoed"' "$global_prov" 2>/dev/null || true)
    empty_firings=$(grep -c '"event":"empty_firing_detected"' "$global_prov" 2>/dev/null || true)
  fi
  pacing_vetoed=${pacing_vetoed:-0}
  empty_firings=${empty_firings:-0}

  # W2.1 (b): recent .hook-errors.log entries. Hooks log validation rejections
  # and unexpected errors there; without surfacing them, a misbehaving session
  # is invisible until /autoloop:status shows GREEN-everywhere despite repeated
  # rejection events. Count newer than 1h, retain newest 3 as samples.
  local hook_errors_log="$HOME/.claude/loops/.hook-errors.log"
  local hook_errors_recent=0
  local hook_errors_samples="[]"
  if [ -f "$hook_errors_log" ]; then
    local cutoff_iso
    cutoff_iso=$(date -u -v-1H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
      || date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
      || echo "")
    if [ -n "$cutoff_iso" ]; then
      hook_errors_recent=$(jq -c --arg cutoff "$cutoff_iso" \
        'select((.ts // "") > $cutoff)' "$hook_errors_log" 2>/dev/null | wc -l | tr -d ' ')
      # `-s` slurps newline-delimited JSON values into one array.
      hook_errors_samples=$(jq -sc --arg cutoff "$cutoff_iso" \
        'map(select((.ts // "") > $cutoff)) | sort_by(.ts) | reverse | .[0:3]' \
        "$hook_errors_log" 2>/dev/null || echo "[]")
    fi
  fi
  hook_errors_recent=${hook_errors_recent:-0}
  [ -z "$hook_errors_samples" ] && hook_errors_samples="[]"

  # W2.1 (c): rapid-reclaim signal — per-loop count of revision-log/superseded-*.json
  # files newer than 24h. >3 indicates the loop is being repeatedly reclaimed,
  # often from competing sessions or a stuck owner that won't die.
  local rapid_reclaim_count=0
  if [ -n "$loops_json" ] && [ "$loops_json" != "[]" ] && [ "$loops_json" != "null" ]; then
    while IFS= read -r sd; do
      [ -z "$sd" ] && continue
      local rl_dir="$sd/revision-log"
      [ ! -d "$rl_dir" ] && continue
      local n
      n=$(find "$rl_dir" -name 'superseded-*.json' -type f -mtime -1 2>/dev/null | wc -l | tr -d ' ')
      if [ "${n:-0}" -gt 3 ]; then
        rapid_reclaim_count=$((rapid_reclaim_count + 1))
      fi
    done < <(echo "$loops_json" | jq -r '.[].state_dir // ""' 2>/dev/null | sed 's:/*$::')
  fi

  if [ "$json_mode" = true ]; then
    echo "$results" | jq -s \
      --argjson pv "${pacing_vetoed:-0}" \
      --argjson ef "${empty_firings:-0}" \
      --argjson her "${hook_errors_recent:-0}" \
      --argjson hes "$hook_errors_samples" \
      --argjson rrc "${rapid_reclaim_count:-0}" \
      --argjson registry_corrupt "$($registry_corrupt && echo true || echo false)" \
      '{loops: .,
        fleet: {pacing_vetoed: $pv,
                empty_firings: $ef,
                hook_errors_recent_1h: $her,
                hook_errors_samples: $hes,
                loops_with_rapid_reclaim_24h: $rrc,
                registry_corrupt: $registry_corrupt},
        generated_at_iso: (now | todate)}'
    return 0
  fi

  # Pretty terminal output
  if [ "$registry_corrupt" = true ]; then
    echo "RED: ~/.claude/loops/registry.json is NOT valid JSON — doctor cannot enumerate loops."
    echo "     Inspect:  jq empty $registry_path"
    echo "     Recover:  cp $registry_path $registry_path.corrupted; restore from backup or rebuild via /autoloop:start in each repo"
    if [ "${hook_errors_recent:-0}" -gt 0 ]; then
      echo "     Also:    $hook_errors_recent hook errors in last 1h (see $hook_errors_log)"
    fi
    return 1
  fi
  if [ -z "$results" ]; then
    echo "No loops registered. (GREEN — nothing to diagnose.)"
    if [ "${pacing_vetoed:-0}" -gt 0 ] || [ "${empty_firings:-0}" -gt 0 ]; then
      echo "Fleet provenance: $pacing_vetoed pacing-vetoed, $empty_firings empty-firings (cumulative)."
    fi
    if [ "${hook_errors_recent:-0}" -gt 0 ]; then
      echo "YELLOW: $hook_errors_recent hook errors in the last 1h — see $hook_errors_log"
    fi
    return 0
  fi
  local total green yellow red
  total=$(echo "$results" | jq -s 'length' 2>/dev/null || echo 0)
  green=$(echo "$results" | jq -s '[.[] | select(.verdict == "GREEN")] | length' 2>/dev/null || echo 0)
  yellow=$(echo "$results" | jq -s '[.[] | select(.verdict == "YELLOW")] | length' 2>/dev/null || echo 0)
  red=$(echo "$results" | jq -s '[.[] | select(.verdict == "RED")] | length' 2>/dev/null || echo 0)
  echo "autoloop doctor — $total loop(s)  GREEN=$green  YELLOW=$yellow  RED=$red"
  echo "Fleet provenance: $pacing_vetoed pacing-vetoed, $empty_firings empty-firings (cumulative)"
  if [ "${hook_errors_recent:-0}" -gt 0 ]; then
    echo "YELLOW: $hook_errors_recent hook errors in last 1h — newest 3:"
    echo "$hook_errors_samples" | jq -r '.[] | "  - " + (.ts // "?") + " " + (.kind // "?") + " field=" + (.field // "?") + " value=" + (.value_truncated // "?")' 2>/dev/null
  fi
  if [ "${rapid_reclaim_count:-0}" -gt 0 ]; then
    echo "YELLOW: $rapid_reclaim_count loop(s) had >3 reclaims in last 24h (rapid-reclaim signal — competing sessions or stuck owner)"
  fi
  echo "================================================================"
  echo "$results" | jq -r '.loop_id + " [" + .verdict + "]" + (if .issues|length > 0 then "\n  - " + (.issues | join("\n  - ")) else "" end)' 2>/dev/null
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

  # Fix 2: tmp-folder registry entries (test artefacts).
  # Match the precise mktemp leftover pattern only:
  # /var/folders/<seg1>/<seg2>/T/tmp.<rand>/LOOP_CONTRACT.md
  # Avoids false positives when a user's HOME or repo lives under /var/folders
  # (e.g. test environments using mktemp -d as HOME).
  local tmp_re='^/var/folders/[^/]+/[^/]+/T/tmp\.[^/]+/LOOP_CONTRACT\.md$'
  if [ -f "$registry_path" ]; then
    local removed
    removed=$(jq --arg re "$tmp_re" '[.loops[] | select(.contract_path | test($re))] | length' "$registry_path")
    if [ "$removed" -gt 0 ]; then
      echo "Pruning $removed mktemp LOOP_CONTRACT.md test entries from registry"
      jq --arg re "$tmp_re" '.loops |= map(select(.contract_path | test($re) | not))' "$registry_path" >"$registry_path.tmp" && mv "$registry_path.tmp" "$registry_path"
      fixed=$((fixed + removed))
    fi
  fi

  # Fix 3 (v16.8.1): clean DONE-marked contracts.
  # User marks contract status: DONE but forgets to run /autoloop:stop —
  # the plist keeps firing forever. Doctor --fix detects DONE status, boots
  # out the launchd job, removes the plist, archives the registry entry, and
  # leaves the .loop-state/ dir in place for forensics.
  if [ -f "$registry_path" ]; then
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      [ "$entry" = "null" ] && continue
      local cp lid sid_label
      cp=$(echo "$entry" | jq -r '.contract_path // ""')
      lid=$(echo "$entry" | jq -r '.loop_id // ""')
      [ -z "$cp" ] || [ -z "$lid" ] && continue
      [ ! -f "$cp" ] && continue
      local cstatus
      cstatus=$(awk '
        /^---$/{n++; next}
        n==1 && /^status:[[:space:]]*/ {
          sub(/^status:[[:space:]]*/, "")
          gsub(/^"|"$|^'\''|'\''$/, "")
          print
          exit
        }
        n==1 && NR > 30 { exit }
      ' "$cp" 2>/dev/null || echo "")
      if echo "$cstatus" | grep -qiE '^(done|complete|finished|superseded|stopped|aborted)\b'; then
        sid_label="com.user.claude.loop.$lid"
        echo "Cleaning DONE loop $lid (status='${cstatus:0:50}') — bootout + plist + registry"
        if command -v launchctl >/dev/null 2>&1; then
          launchctl bootout "gui/$(id -u)/$sid_label" 2>/dev/null || true
        fi
        rm -f "$HOME/Library/LaunchAgents/$sid_label.plist" 2>/dev/null || true
        # Archive registry entry instead of hard delete (forensics)
        local archive="$HOME/.claude/loops/registry.archive.jsonl"
        local now_iso
        now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "$entry" | jq -c --arg ts "$now_iso" --arg s "$cstatus" '. + {archived_ts_iso: $ts, archived_reason: ("contract status=" + $s)}' >>"$archive" 2>/dev/null || true
        # Remove from active registry
        jq --arg id "$lid" '.loops |= map(select(.loop_id != $id))' "$registry_path" >"$registry_path.tmp" && mv "$registry_path.tmp" "$registry_path"
        if command -v emit_provenance >/dev/null 2>&1; then
          emit_provenance "$lid" "doctor_fixed_done_loop" \
            reason="auto-cleanup of DONE-marked loop; status=${cstatus:0:80}" \
            decision="proceeded" 2>/dev/null || true
        fi
        fixed=$((fixed + 1))
      fi
    done < <(jq -c '.loops[]' "$registry_path" 2>/dev/null)
  fi

  echo "Doctor fix complete. Remediations applied: $fixed"
  return 0
}

export -f loop_doctor_report
export -f loop_doctor_fix
