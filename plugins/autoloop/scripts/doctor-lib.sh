#!/usr/bin/env bash
# doctor-lib.sh — Diagnose and repair the four documented autoloop bootstrap
# failure modes.
#
# Provides:
#   diagnose_loop <loop_id>                       — emit JSON diagnosis
#   repair_missing_plist <loop_id>                — generate + load plist
#   repair_missing_hooks                          — install_all_hooks idempotently
#   repair_pending_bind_owner_session <loop_id> <session_uuid>
#                                                 — patch registry owner_session_id
#   repair_stale_waker_path <loop_id>             — regenerate plist if waker drifted
#   doctor_repair_all_for_loop <loop_id> [session_uuid]
#                                                 — orchestrate the four repairs
#
# Failure modes addressed (one PR landed in plugin v12.52.0):
#   F1 — registered loop with no plist on disk
#   F2 — autoloop hooks not installed in settings.json
#   F3 — owner_session_id stuck at "pending-bind" beyond grace window
#   F4 — plist's ProgramArguments[0] points at a stale waker path (e.g. plugin
#        moved between marketplace versions)
#
# Every repair is idempotent. Doctor never deletes contracts or revision-log;
# the worst it does is regenerate a plist or patch a single registry field.
#
# WHY a single doctor: prior to this lib, the same hand-rolled diagnose+repair
# was open-coded in incident response. Concentrating the logic here keeps the
# four failure-mode definitions in one place and guarantees the repair
# sequence stays consistent across human and agent invocations.

set -euo pipefail

# Resolve plugin root so we can source siblings even if BASH_SOURCE[0]
# is empty (zsh-launched bash, etc).
_doctor_lib_resolve_plugin_root() {
  if [ -n "${AUTOLOOP_PLUGIN_ROOT:-}" ] && [ -d "${AUTOLOOP_PLUGIN_ROOT}/scripts" ]; then
    echo "$AUTOLOOP_PLUGIN_ROOT"
    return 0
  fi
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [ -n "$script_dir" ] && [ -d "$(dirname "$script_dir")/scripts" ]; then
      dirname "$script_dir"
      return 0
    fi
  fi
  local marketplace="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop"
  if [ -d "${marketplace}/scripts" ]; then
    echo "$marketplace"
    return 0
  fi
  echo "ERROR: doctor-lib: cannot resolve plugin root" >&2
  return 1
}

_DOCTOR_LIB_PLUGIN_ROOT="$(_doctor_lib_resolve_plugin_root)" || exit 1

# Source siblings (each is idempotent and exports its public functions).
# shellcheck source=/dev/null
source "$_DOCTOR_LIB_PLUGIN_ROOT/scripts/registry-lib.sh"
# shellcheck source=/dev/null
source "$_DOCTOR_LIB_PLUGIN_ROOT/scripts/state-lib.sh"
# shellcheck source=/dev/null
source "$_DOCTOR_LIB_PLUGIN_ROOT/scripts/hook-install-lib.sh"
# shellcheck source=/dev/null
source "$_DOCTOR_LIB_PLUGIN_ROOT/scripts/launchd-lib.sh"

# Grace period before a "pending-bind" owner is considered a real failure
# rather than an in-progress bind. Default 5 minutes.
_DOCTOR_PENDING_BIND_GRACE_SECONDS="${AUTOLOOP_DOCTOR_PENDING_BIND_GRACE_S:-300}"

# diagnose_loop <loop_id>
# Emits a single-line JSON object describing each of the four documented
# failure modes for the given loop. Exit 0 even when failures are detected;
# the JSON is the primary signal.
#
# Output JSON shape:
#   {
#     "loop_id": "...",
#     "registry_present": true|false,
#     "plist_present": true|false,
#     "plist_loaded": true|false,
#     "plist_program": "<path or null>",
#     "waker_script_expected": "<path>",
#     "waker_path_stale": true|false,
#     "hooks_installed": {
#       "heartbeat": "yes"|"no",
#       "session_bind": "yes"|"no",
#       "pacing_veto": "yes"|"no",
#       "empty_firing": "yes"|"no"
#     },
#     "owner_session_id": "<value>",
#     "owner_pending_bind_age_seconds": <int>|null,
#     "failure_modes": ["F1_missing_plist", ...]
#   }
diagnose_loop() {
  local loop_id="$1"
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: diagnose_loop: invalid loop_id format" >&2
    return 1
  fi

  # Registry presence + entry
  local entry
  entry="$(jq --arg id "$loop_id" '.loops[] | select(.loop_id == $id)' \
    "$HOME/.claude/loops/registry.json" 2>/dev/null || echo "")"
  local registry_present=false
  [ -n "$entry" ] && [ "$entry" != "null" ] && registry_present=true

  # Plist presence + load state
  local plist_path="$HOME/Library/LaunchAgents/com.user.claude.loop.${loop_id}.plist"
  local plist_present=false
  [ -f "$plist_path" ] && plist_present=true

  local plist_loaded=false
  if command -v launchctl >/dev/null 2>&1; then
    if launchctl list "com.user.claude.loop.${loop_id}" >/dev/null 2>&1; then
      plist_loaded=true
    fi
  fi

  # Plist's ProgramArguments[0] (potentially-stale runner)
  local plist_program=""
  if [ "$plist_present" = "true" ] && command -v plutil >/dev/null 2>&1; then
    plist_program="$(plutil -extract ProgramArguments.0 raw -o - "$plist_path" 2>/dev/null || echo "")"
  fi

  # Expected waker path (the script the runner should exec)
  local waker_script_expected="$_DOCTOR_LIB_PLUGIN_ROOT/scripts/waker.sh"

  # Detect waker-path drift: the runner contains `exec "<waker_path>" "$loop_id"`.
  # We consider the plist stale ONLY when the actual chain is broken:
  #   - plist exists but its ProgramArguments[0] (the runner) is missing on disk, OR
  #   - runner exists but its exec target (waker.sh) is missing on disk.
  # We DO NOT compare runner_target against $waker_script_expected literally,
  # because an installed loop may legitimately point at the marketplace copy
  # of waker.sh while doctor was sourced from the source repo (or vice-versa).
  # Both paths are valid as long as the file exists.
  local waker_path_stale=false
  if [ "$plist_present" = "true" ]; then
    if [ -z "$plist_program" ] || [ ! -f "$plist_program" ]; then
      waker_path_stale=true
    else
      local runner_target
      runner_target="$(grep -oE '^exec "[^"]+"' "$plist_program" 2>/dev/null | head -1 | sed -E 's/^exec "(.+)"$/\1/')"
      if [ -z "$runner_target" ] || [ ! -f "$runner_target" ]; then
        waker_path_stale=true
      fi
    fi
  fi

  # Hook install status (each returns "yes" or "no")
  local h_heartbeat h_session_bind h_pacing h_empty
  h_heartbeat="$(is_hook_installed "$HOME/.claude/settings.json" 2>/dev/null || echo no)"
  h_session_bind="$(is_session_bind_installed "$HOME/.claude/settings.json" 2>/dev/null || echo no)"
  h_pacing="$(is_pacing_veto_installed "$HOME/.claude/settings.json" 2>/dev/null || echo no)"
  h_empty="$(is_empty_firing_installed "$HOME/.claude/settings.json" 2>/dev/null || echo no)"

  # Owner session_id + pending-bind age
  local owner_session_id="" owner_pending_bind_age="null"
  if [ "$registry_present" = "true" ]; then
    owner_session_id="$(echo "$entry" | jq -r '.owner_session_id // ""')"
    if [ "$owner_session_id" = "pending-bind" ]; then
      local started_us now_us
      started_us="$(echo "$entry" | jq -r '.started_at_us // "0"')"
      now_us="$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)"
      if [ "$started_us" != "0" ] && [ "$now_us" != "0" ]; then
        owner_pending_bind_age="$(((now_us - started_us) / 1000000))"
      fi
    fi
  fi

  # Compute failure_modes
  local -a failure_modes=()
  if [ "$registry_present" = "true" ] && { [ "$plist_present" = "false" ] || [ "$plist_loaded" = "false" ]; }; then
    failure_modes+=("F1_missing_plist")
  fi
  if [ "$h_heartbeat" != "yes" ] || [ "$h_session_bind" != "yes" ] || \
     [ "$h_pacing" != "yes" ] || [ "$h_empty" != "yes" ]; then
    failure_modes+=("F2_missing_hooks")
  fi
  if [ "$owner_session_id" = "pending-bind" ] && \
     [ "$owner_pending_bind_age" != "null" ] && \
     [ "$owner_pending_bind_age" -gt "$_DOCTOR_PENDING_BIND_GRACE_SECONDS" ]; then
    failure_modes+=("F3_pending_bind_stale")
  fi
  if [ "$waker_path_stale" = "true" ]; then
    failure_modes+=("F4_stale_waker_path")
  fi

  jq -n \
    --arg loop_id "$loop_id" \
    --argjson registry_present "$registry_present" \
    --argjson plist_present "$plist_present" \
    --argjson plist_loaded "$plist_loaded" \
    --arg plist_program "$plist_program" \
    --arg waker_script_expected "$waker_script_expected" \
    --argjson waker_path_stale "$waker_path_stale" \
    --arg h_heartbeat "$h_heartbeat" \
    --arg h_session_bind "$h_session_bind" \
    --arg h_pacing "$h_pacing" \
    --arg h_empty "$h_empty" \
    --arg owner_session_id "$owner_session_id" \
    --argjson owner_pending_bind_age "$owner_pending_bind_age" \
    --argjson failure_modes "$(printf '%s\n' "${failure_modes[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
    '{
      loop_id: $loop_id,
      registry_present: $registry_present,
      plist_present: $plist_present,
      plist_loaded: $plist_loaded,
      plist_program: $plist_program,
      waker_script_expected: $waker_script_expected,
      waker_path_stale: $waker_path_stale,
      hooks_installed: {
        heartbeat: $h_heartbeat,
        session_bind: $h_session_bind,
        pacing_veto: $h_pacing,
        empty_firing: $h_empty
      },
      owner_session_id: $owner_session_id,
      owner_pending_bind_age_seconds: $owner_pending_bind_age,
      failure_modes: $failure_modes
    }'
}

# repair_missing_plist <loop_id>
# Generates + loads the plist for the given loop. Idempotent.
# Reads contract_path + state_dir from registry, expected_cadence_seconds
# determines the polling interval (half the cadence, floor 60s).
repair_missing_plist() {
  local loop_id="$1"
  local entry
  entry="$(jq --arg id "$loop_id" '.loops[] | select(.loop_id == $id)' \
    "$HOME/.claude/loops/registry.json" 2>/dev/null || echo "")"
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    echo "ERROR: repair_missing_plist: loop $loop_id not in registry" >&2
    return 1
  fi
  local state_dir cadence
  state_dir="$(echo "$entry" | jq -r '.state_dir // ""')"
  cadence="$(echo "$entry" | jq -r '.expected_cadence_seconds // 1800')"
  local interval=$((cadence / 2))
  [ "$interval" -lt 60 ] && interval=60

  local waker="$_DOCTOR_LIB_PLUGIN_ROOT/scripts/waker.sh"
  echo "  repair_missing_plist: loop=$loop_id state=$state_dir interval=${interval}s" >&2
  generate_plist "$loop_id" "$state_dir" "$waker" "$interval" || return 1
  load_plist "$loop_id" "$state_dir" || return 1
  return 0
}

# repair_missing_hooks
# Installs all four autoloop hooks idempotently. Bypasses the BASH_SOURCE-
# dependent hook_path_default helpers by passing explicit paths derived from
# the plugin root, so this works in non-bash parent shells too.
repair_missing_hooks() {
  local settings_path="$HOME/.claude/settings.json"
  local heartbeat="$_DOCTOR_LIB_PLUGIN_ROOT/hooks/heartbeat-tick.sh"
  local session_bind="$_DOCTOR_LIB_PLUGIN_ROOT/hooks/session-bind.sh"
  local pacing="$_DOCTOR_LIB_PLUGIN_ROOT/hooks/pacing-veto.sh"
  local empty="$_DOCTOR_LIB_PLUGIN_ROOT/hooks/empty-firing-detector.sh"

  for f in "$heartbeat" "$session_bind" "$pacing" "$empty"; do
    if [ ! -f "$f" ]; then
      echo "ERROR: repair_missing_hooks: required hook not found: $f" >&2
      return 1
    fi
  done

  install_hook         "$settings_path" "$heartbeat"   || return 1
  install_session_bind "$settings_path" "$session_bind" || return 1
  install_pacing_veto  "$settings_path" "$pacing"      || return 1
  install_empty_firing "$settings_path" "$empty"       || return 1
  return 0
}

# repair_pending_bind_owner_session <loop_id> <session_uuid>
# Patches the registry's owner_session_id from "pending-bind" to the given
# UUID. Refuses to overwrite an existing real UUID (uses session-bind.sh's
# normal flow for that case). Atomic via tmpfile + mv.
repair_pending_bind_owner_session() {
  local loop_id="$1"
  local session_uuid="$2"

  if ! [[ "$session_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "ERROR: repair_pending_bind_owner_session: invalid session UUID" >&2
    return 1
  fi

  local current
  current="$(jq -r --arg id "$loop_id" \
    '.loops[] | select(.loop_id == $id) | .owner_session_id // ""' \
    "$HOME/.claude/loops/registry.json" 2>/dev/null || echo "")"

  if [ -z "$current" ]; then
    echo "ERROR: repair_pending_bind_owner_session: loop $loop_id not in registry" >&2
    return 1
  fi

  if [ "$current" != "pending-bind" ] && [ "$current" != "" ] && [ "$current" != "unknown" ] && [ "$current" != "unknown-session" ]; then
    echo "  repair_pending_bind_owner_session: loop already bound to $current; refusing to overwrite" >&2
    return 0
  fi

  local now_us
  now_us="$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)"
  local registry_path="$HOME/.claude/loops/registry.json"
  local tmp
  tmp="$(mktemp "${registry_path}.XXXXXX")" || return 1
  jq --arg id "$loop_id" --arg sid "$session_uuid" --arg now_us "$now_us" '
    .loops |= map(
      if .loop_id == $id
      then .owner_session_id = $sid
         | .last_heartbeat_us = $now_us
      else . end
    )
  ' "$registry_path" > "$tmp" && mv "$tmp" "$registry_path"
  return 0
}

# repair_stale_waker_path <loop_id>
# Regenerates the plist when its current ProgramArguments[0] points at a
# missing or stale waker. Just delegates to repair_missing_plist after
# unloading any existing plist.
repair_stale_waker_path() {
  local loop_id="$1"
  local label="com.user.claude.loop.${loop_id}"
  local installed_plist="$HOME/Library/LaunchAgents/${label}.plist"

  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
  fi
  rm -f "$installed_plist" 2>/dev/null || true

  repair_missing_plist "$loop_id" || return 1
  return 0
}

# doctor_repair_all_for_loop <loop_id> [session_uuid]
# Runs diagnose_loop, then applies each repair whose corresponding failure
# mode is present. Prints a one-line summary per repair attempted.
#
# When session_uuid is omitted AND F3_pending_bind_stale is present, the
# repair is skipped (the caller's session UUID isn't known).
doctor_repair_all_for_loop() {
  local loop_id="$1"
  local session_uuid="${2:-}"

  local diagnosis
  diagnosis="$(diagnose_loop "$loop_id")" || return 1
  echo "$diagnosis"

  local modes
  modes="$(echo "$diagnosis" | jq -r '.failure_modes[]?' 2>/dev/null || echo "")"

  if [ -z "$modes" ]; then
    echo "  [HEALTHY] no repair needed" >&2
    return 0
  fi

  local exit_code=0
  while IFS= read -r mode; do
    case "$mode" in
      F1_missing_plist)
        echo "  [F1] repairing missing plist..." >&2
        repair_missing_plist "$loop_id" || exit_code=1
        ;;
      F2_missing_hooks)
        echo "  [F2] installing missing hooks..." >&2
        repair_missing_hooks || exit_code=1
        ;;
      F3_pending_bind_stale)
        if [ -n "$session_uuid" ]; then
          echo "  [F3] patching pending-bind owner_session_id to $session_uuid..." >&2
          repair_pending_bind_owner_session "$loop_id" "$session_uuid" || exit_code=1
        else
          echo "  [F3] SKIPPED: pending-bind detected but no session_uuid provided" >&2
          echo "       open a fresh Claude Code session in the loop's cwd to trigger session-bind" >&2
        fi
        ;;
      F4_stale_waker_path)
        echo "  [F4] regenerating plist with current waker path..." >&2
        repair_stale_waker_path "$loop_id" || exit_code=1
        ;;
      *)
        echo "  [WARN] unknown failure mode: $mode (skipped)" >&2
        ;;
    esac
  done <<< "$modes"

  return $exit_code
}

export -f _doctor_lib_resolve_plugin_root
export -f diagnose_loop
export -f repair_missing_plist
export -f repair_missing_hooks
export -f repair_pending_bind_owner_session
export -f repair_stale_waker_path
export -f doctor_repair_all_for_loop
