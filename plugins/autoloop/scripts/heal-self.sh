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

exit 0
