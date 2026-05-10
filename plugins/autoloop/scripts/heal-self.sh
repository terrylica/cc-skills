#!/usr/bin/env bash
# heal-self.sh — Idempotent self-migration archiving stale unknown-owner
# registry entries (v4.10.0 Phase 38 DOC-03).
#
# On invocation:
#   1. Compute SHA256 of registry.json content.
#   2. If matches ~/.claude/loops/.last-healed-hash → exit 0 (gated).
#   3. Archive entries with owner_session_id ∈ {unknown, unknown-session, '',
#      pending-bind} older than 1 hour to registry.archive.jsonl.
#   4. Update .last-healed-hash to current hash.
#
# Returns 0 always (graceful — must not block SessionStart hook caller).

set -euo pipefail

LOOPS_DIR="${HOME}/.claude/loops"
REGISTRY_PATH="${CLAUDE_LOOPS_REGISTRY:-$LOOPS_DIR/registry.json}"
ARCHIVE_PATH="${LOOPS_DIR}/registry.archive.jsonl"
HASH_PATH="${LOOPS_DIR}/.last-healed-hash"
STALE_THRESHOLD_S="${HEAL_STALE_THRESHOLD_S:-3600}"

trap 'exit 0' ERR

[ -f "$REGISTRY_PATH" ] || exit 0

# Try shasum first (macOS), fall back to sha256sum (Linux)
_compute_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$REGISTRY_PATH" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$REGISTRY_PATH" 2>/dev/null | awk '{print $1}'
  else
    return 0
  fi
}

CURRENT_HASH=$(_compute_hash)
[ -z "$CURRENT_HASH" ] && exit 0

if [ -f "$HASH_PATH" ]; then
  LAST_HASH=$(cat "$HASH_PATH" 2>/dev/null || echo "")
  if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
    exit 0
  fi
fi

NOW_US=$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo 0)
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Filter stale entries: owner_session_id stale AND owner_start_time_us older than threshold.
STALE_ENTRIES=$(jq -c --argjson now "$NOW_US" --argjson threshold_us "$((STALE_THRESHOLD_S * 1000000))" \
  '.loops[] | select(
    (.owner_session_id == "unknown" or .owner_session_id == "unknown-session" or
     .owner_session_id == "" or .owner_session_id == "pending-bind" or .owner_session_id == null)
    and ((.owner_start_time_us | tonumber) > 0)
    and (($now - (.owner_start_time_us | tonumber)) > $threshold_us)
  )' "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -z "$STALE_ENTRIES" ]; then
  # Nothing stale — still update hash so we don't re-scan unchanged registry next time
  echo "$CURRENT_HASH" >"$HASH_PATH" 2>/dev/null || true
  exit 0
fi

# Wave 6 anti-fragility: BEFORE archiving, try to auto-bind each stale
# pending-bind entry to a live Claude session whose cwd matches the
# loop's project_root. This rescues loops the bind hook missed because
# the user's session opened with cwd at project_root rather than inside
# .autoloop/<slug>--<hash>/.
#
# Detection signal: ~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
# with mtime within the last 5 minutes. The encoding maps absolute path
# to "-" separators (e.g. /Users/x/eon/foo → -Users-x-eon-foo). The
# JSONL filename IS the session UUID. If a recent JSONL exists at the
# matching encoded path, that session is the natural new owner.
RESCUED_LOOP_IDS=""
PROJECTS_DIR="$HOME/.claude/projects"
if [ -d "$PROJECTS_DIR" ]; then
  RESCUED_LIST=$(mktemp -t autoloop-heal.XXXXXX) || RESCUED_LIST=""
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local_loop_id=$(echo "$entry" | jq -r '.loop_id // ""' 2>/dev/null)
    local_root=$(echo "$entry" | jq -r '.created_at_cwd // ""' 2>/dev/null)
    local_contract=$(echo "$entry" | jq -r '.contract_path // ""' 2>/dev/null)
    # Derive project_root if registry doesn't have it (legacy entries)
    if [ -z "$local_root" ] && [ -n "$local_contract" ]; then
      case "$local_contract" in
        */.autoloop/*--[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/CONTRACT.md)
          local_root="${local_contract%/.autoloop/*}"
          ;;
      esac
    fi
    [ -z "$local_root" ] && continue

    # Encode: leading-slash path with "/" replaced by "-"
    encoded="${local_root//\//-}"
    project_jsonl_dir="$PROJECTS_DIR/$encoded"
    [ -d "$project_jsonl_dir" ] || continue

    # Find the most recent JSONL (mtime within 5min = live session)
    candidate=$(find "$project_jsonl_dir" -maxdepth 1 -name '*.jsonl' -mmin -5 -print 2>/dev/null | head -1)
    [ -z "$candidate" ] && continue

    candidate_sid=$(basename "$candidate" .jsonl)
    # Validate UUID shape before mutating registry
    if ! [[ "$candidate_sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
      continue
    fi

    # Source registry-lib for atomic update_loop_field
    REG_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/registry-lib.sh"
    if [ -f "$REG_LIB" ]; then
      # shellcheck source=/dev/null
      source "$REG_LIB" 2>/dev/null || continue
      if command -v update_loop_field >/dev/null 2>&1; then
        if update_loop_field "$local_loop_id" ".owner_session_id" "\"$candidate_sid\"" 2>/dev/null; then
          update_loop_field "$local_loop_id" ".owner_start_time_us" "\"$NOW_US\"" 2>/dev/null || true
          if command -v emit_provenance >/dev/null 2>&1; then
            emit_provenance "$local_loop_id" "heal_auto_bound" \
              session_id="$candidate_sid" \
              project_root="$local_root" \
              project_root_source="heal-self.sh" \
              reason="rescued from pending-bind: live JSONL at $candidate (mtime <5min)" \
              decision="proceeded" 2>/dev/null || true
          fi
          [ -n "$RESCUED_LIST" ] && echo "$local_loop_id" >>"$RESCUED_LIST"
        fi
      fi
    fi
  done <<< "$STALE_ENTRIES"

  # Re-filter STALE_ENTRIES to drop loops we just rescued (so they don't
  # get archived in the next block).
  if [ -n "$RESCUED_LIST" ] && [ -s "$RESCUED_LIST" ]; then
    RESCUED_LOOP_IDS=$(tr '\n' '|' <"$RESCUED_LIST" | sed 's/|$//')
    if [ -n "$RESCUED_LOOP_IDS" ]; then
      STALE_ENTRIES=$(echo "$STALE_ENTRIES" | jq -c --arg rescued "$RESCUED_LOOP_IDS" \
        'select(.loop_id | test("^(" + $rescued + ")$") | not)' 2>/dev/null || echo "$STALE_ENTRIES")
    fi
    rm -f "$RESCUED_LIST"
  fi
fi

# Re-check after rescue — if everything got auto-bound, no archival needed.
if [ -z "$STALE_ENTRIES" ]; then
  echo "$CURRENT_HASH" >"$HASH_PATH" 2>/dev/null || true
  exit 0
fi

# Append each stale entry to archive (with archived_ts annotation), then remove from registry.
mkdir -p "$LOOPS_DIR" 2>/dev/null || true
ARCHIVED=0
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  local_archived=$(echo "$entry" | jq -c --arg ts "$NOW_ISO" '. + {archived_ts_iso: $ts}')
  echo "$local_archived" >>"$ARCHIVE_PATH" 2>/dev/null || true
  ARCHIVED=$((ARCHIVED + 1))
done <<< "$STALE_ENTRIES"

# Remove archived entries from registry (filter out those matching the stale predicate).
TMP_REG=$(mktemp "$REGISTRY_PATH.heal.XXXXXX") || exit 0
jq --argjson now "$NOW_US" --argjson threshold_us "$((STALE_THRESHOLD_S * 1000000))" '
  .loops |= map(select(
    (.owner_session_id == "unknown" or .owner_session_id == "unknown-session" or
     .owner_session_id == "" or .owner_session_id == "pending-bind" or .owner_session_id == null)
    and ((.owner_start_time_us | tonumber) > 0)
    and (($now - (.owner_start_time_us | tonumber)) > $threshold_us)
    | not
  ))
' "$REGISTRY_PATH" >"$TMP_REG" 2>/dev/null || {
  rm -f "$TMP_REG"
  exit 0
}
mv "$TMP_REG" "$REGISTRY_PATH" || {
  rm -f "$TMP_REG"
  exit 0
}

# Emit provenance event (best-effort)
PROV_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/provenance-lib.sh"
if [ -f "$PROV_LIB" ]; then
  # shellcheck source=/dev/null
  source "$PROV_LIB" 2>/dev/null || true
  if command -v emit_provenance >/dev/null 2>&1; then
    emit_provenance "" "heal_archived" \
      agent="heal-self.sh" \
      reason="archived $ARCHIVED stale entries with unknown/pending-bind owner" \
      decision="proceeded" 2>/dev/null || true
  fi
fi

# Update hash AFTER archival so a partial run on retry still archives remaining stale entries.
NEW_HASH=$(_compute_hash)
[ -n "$NEW_HASH" ] && echo "$NEW_HASH" >"$HASH_PATH" 2>/dev/null || true

# Wave-6 anti-fragility: scan for live registry entries missing their plist
# and best-effort regenerate via tinker-lib. This catches the documented F1
# failure mode (registered loop, no plist on disk) without waiting for the
# user to invoke /autoloop:tinker manually.
#
# Conservative: only operate on entries whose owner_session_id is a real
# UUID (already-bound loop) — never touch pending-bind entries the operator
# may still be wiring up. Logs to provenance and exits 0 either way.
DOCTOR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/tinker-lib.sh"
if [ -f "$DOCTOR_LIB" ] && [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  # Find loop_ids whose owner_session_id is a real UUID
  BOUND_LOOPS=$(jq -r '
    .loops[]?
    | select(.owner_session_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"))
    | .loop_id
  ' "$REGISTRY_PATH" 2>/dev/null || echo "")

  if [ -n "$BOUND_LOOPS" ]; then
    # shellcheck source=/dev/null
    source "$DOCTOR_LIB" 2>/dev/null || BOUND_LOOPS=""
    while IFS= read -r LID; do
      [ -z "$LID" ] && continue
      PLIST="$HOME/Library/LaunchAgents/com.user.claude.loop.${LID}.plist"
      if [ ! -f "$PLIST" ]; then
        if command -v emit_provenance >/dev/null 2>&1; then
          emit_provenance "$LID" "heal_self_repairing_missing_plist" \
            reason="bound loop with missing plist detected" \
            decision="repair_attempt" 2>/dev/null || true
        fi
        repair_missing_plist "$LID" 2>/dev/null || true
      fi
    done <<<"$BOUND_LOOPS"
  fi
fi

exit 0
