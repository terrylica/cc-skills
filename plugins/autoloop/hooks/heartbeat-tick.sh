#!/usr/bin/env bash
# FILE-SIZE-OK — intentionally monolithic. This is the PostToolUse hook
# entry point that fires on every Claude Code tool invocation; splitting it
# into multiple files would add subprocess overhead (extra source / dispatch
# layer) that defeats the iter-25/26/27 perf work (12→7 jq spawns, 165ms→13ms
# fast path). The file is dense but the hot path is single-pass top-to-bottom
# with clearly labeled FAST-PATH and SLOW-PATH sections.
# heartbeat-tick.sh — PostToolUse hook for autoloop
# Ticks the heartbeat for the current loop on each tool invocation.
#
# v4.10.0 Phase 36 (BIND-03): now reads session_id and cwd from stdin JSON
# payload (Claude Code's documented hook contract); env-var path retained as
# back-compat fallback only (anthropics/claude-code#47018 — env vars are NOT
# populated for skill Bash subprocesses, so the env path is unreliable).
#
# Logic:
# 1. Read stdin JSON payload {session_id, cwd}; fall back to $CLAUDE_SESSION_ID
#    + $(pwd) only if stdin is empty.
# 2. Read registry; find matching loop via contract_path prefix match.
# 3. Verify owner_session_id matches session_id (no-op if mismatch).
# 4. Check generation match (no-op + superseded event if generation drifted).
# 5. cwd-drift detection: compare CWD vs heartbeat.bound_cwd; on first tick
#    record bound_cwd; on subsequent ticks if mismatch flag cwd_drift_detected
#    in heartbeat.json AND emit cwd_drift_detected provenance event.
# 6. Increment iteration and write heartbeat via write_heartbeat.
# 7. All paths exit 0 (never block user tool call).

set -euo pipefail

# Iter-34 bash-5.2-patsub-replacement-defense:
# Disable bash 5.2+'s `patsub_replacement` shell option so that `&` in
# the REPLACEMENT field of ${VAR//PATTERN/REPLACEMENT} stays LITERAL
# instead of expanding to "the matched pattern text". Bash 5.2 (Sept 2022)
# enabled this sed-style backreference BY DEFAULT, silently breaking any
# script that puts `&` in a substitution replacement — including XML-
# escaped strings like `&amp;`, JSON-escaped strings like `\&`, query
# strings, and URL fragments. The iter-33 plist-amp-backreference fix
# patched the two known sites in launchd-lib.sh; this directive prevents
# the entire class of bug from recurring in FUTURE code added to any
# library this hook sources (registry-lib.sh, state-lib.sh, provenance-
# lib.sh, hook-install-lib.sh). Source: bash maintainer + Arch Linux
# pacman patch (Dec 2022) both recommend this as the upstream-blessed
# workaround. `|| true` makes it a graceful no-op on bash <5.2 where the
# option doesn't exist.
shopt -u patsub_replacement 2>/dev/null || true

# ===== Configuration =====
LOOPS_DIR="${HOME}/.claude/loops"
REGISTRY_PATH="${CLAUDE_LOOPS_REGISTRY:-$LOOPS_DIR/registry.json}"
HOOK_ERRORS_LOG="$LOOPS_DIR/.hook-errors.log"

# ===== Iter-27: tool-burst-tick-deduplication throttle =====
#
# Why this exists: Claude Code fires PostToolUse on EVERY tool invocation. A
# single user message can produce a burst of 5-20 tool calls (read+grep+edit
# flurries) in tens of milliseconds. Pre-iter-27 each tool call paid the full
# 130-165ms heartbeat-tick cost, so a 10-tool burst stacked ~1.5 SECONDS of
# hook latency in front of the user's response.
#
# The throttle: when a tick fires within $AUTOLOOP_TICK_DEDUP_INTERVAL_US of
# the previous successful tick (default 500_000 μs = 500ms), skip the entire
# heavy hot path. The skipped tick costs ~5ms (one gdate + one cat + bash
# arithmetic) instead of 130-165ms — a ~26× speedup on bursty workloads.
#
# Correctness: stuck-loop detection relies on heartbeat.last_wake_us
# freshness. With a 500ms throttle the worst-case staleness latency increases
# by ≤500ms — well within the 3×-expected_cadence reclaim threshold (the
# tightest cadence is "continuous", which is interpreted as >60s). The
# throttle is therefore semantically invisible to consumers.
#
# Tunable via env var (set to 0 to disable):
AUTOLOOP_TICK_DEDUP_INTERVAL_US="${AUTOLOOP_TICK_DEDUP_INTERVAL_US:-500000}"

# Throttle file lives in $TMPDIR/autoloop-tick-dedup-<session_id>.us. Keyed by
# session_id so distinct Claude Code sessions don't interfere. Auto-cleaned
# by the OS's tmp-reaper (no manual cleanup needed).
AUTOLOOP_TICK_DEDUP_DIR="${AUTOLOOP_TICK_DEDUP_DIR:-${TMPDIR:-/tmp}/autoloop-tick-dedup}"

# ===== Error handling: log and exit gracefully =====
_log_error() {
  local cwd
  cwd=$(pwd 2>/dev/null || echo 'unknown')
  local session="${CLAUDE_SESSION_ID:-absent}"
  local error_msg="$1"
  local exit_code="${2:-1}"

  # Ensure loops dir exists for logging
  mkdir -p "$LOOPS_DIR" 2>/dev/null || true

  # Append JSON error record to log (best-effort)
  {
    jq -n \
      --arg ts_us "$(gdate +%s%6N 2>/dev/null || python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo '0')" \
      --arg cwd "$cwd" \
      --arg session "$session" \
      --arg error "$error_msg" \
      --arg exit_code "$exit_code" \
      '{ts_us: $ts_us, cwd: $cwd, session: $session, error: $error, exit_code: $exit_code}' \
      >> "$HOOK_ERRORS_LOG" 2>/dev/null || true
  }
}

trap '_log_error "Unexpected error in heartbeat-tick hook" "$?"' ERR

# =============================================================================
# FAST PATH: tool-burst-tick-deduplication throttle gate (runs BEFORE lib sourcing)
# =============================================================================
# Why this block is ABOVE the library `source` statements:
#   Sourcing registry-lib.sh + state-lib.sh + provenance-lib.sh costs ~10-15ms
#   on macOS even when no functions are invoked (bash has to parse each file).
#   When the throttle skips a tick we don't need any of those libraries — the
#   skip decision only needs gdate + cat + bash builtins. Running the gate
#   above the sources keeps the fast-path latency under ~12ms instead of ~25ms.
#
# What can fail before this gate without losing forensic logs:
#   The ERR trap above already wraps everything up to _log_error, so if a
#   regex match itself errors (highly unlikely under set -e but possible
#   if PAYLOAD contains weird unicode that breaks the regex engine), the
#   error is logged before exit.

# Step 1: Read stdin JSON payload (modern Claude Code hook contract).
# Use a bounded read to avoid blocking when stdin is closed.
PAYLOAD=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat 2>/dev/null || echo "")
fi
[ -z "$PAYLOAD" ] && PAYLOAD='{}'

# Step 1a (iter-27 tool-burst-tick-deduplication fast-path session-id extract,
# iter-32 throttle-key-uuid-shape-required hardening):
#
# Pre-iter-27 the PAYLOAD jq spawn was the very first work this hook did,
# even when the entire tick would be deduplicated by the throttle below. By
# extracting session_id with a pure-bash regex first (BASH_REMATCH, zero
# subprocess spawns), the throttle gate can fire BEFORE jq starts.
#
# Iter-32 hardening: the iter-27 regex `"session_id":"([^"]+)"` matches the
# FIRST occurrence of `session_id` in the JSON — which can be a NESTED field
# like `tool_input.session_id` if the JSON serializer emits it before the
# top-level key. Claude Code's current PostToolUse payload puts session_id
# first so the bug was masked in production, but the latent failure mode is
# real: a future payload-order change would silently break the throttle
# (write would write the correct UUID's throttle file, read would search by
# the WRONG nested key, so throttle would NEVER hit → every tick goes slow
# path with no error).
#
# The iter-32 fix REQUIRES the captured value to look like a UUID
# (8-4-4-4-12 lowercase hex). Claude Code session_ids are UUIDs; nested
# session_id values inside tool_input would almost never be UUID-shaped
# (they're typically integer task IDs, file paths, or string handles).
# When the nested value is non-UUID, the regex engine skips past it and
# matches the next `"session_id":"..."` whose value IS UUID-shaped — which
# is the top-level field.
#
# Defense in depth: if the regex matches but the value isn't UUID-shaped,
# the regex won't match at all and we fall through to the jq decode below,
# so correctness is preserved (just at the cost of one jq spawn).
SESSION_ID_FAST=""
PAYLOAD_CWD_FAST=""
if [[ "$PAYLOAD" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\" ]]; then
  SESSION_ID_FAST="${BASH_REMATCH[1]}"
fi
if [[ "$PAYLOAD" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  PAYLOAD_CWD_FAST="${BASH_REMATCH[1]}"
fi
# env-var fallback for session_id (legacy contract; see top-of-file comment)
[ -z "$SESSION_ID_FAST" ] && SESSION_ID_FAST="${CLAUDE_SESSION_ID:-}"

# Step 1b (iter-27 throttle gate): if last successful tick fired less than
# $AUTOLOOP_TICK_DEDUP_INTERVAL_US microseconds ago, exit immediately. Zero
# jq spawns on this path — just one gdate + one `cat` of a tiny tmp file.
# Setting AUTOLOOP_TICK_DEDUP_INTERVAL_US=0 disables the throttle entirely
# (useful for tests that need deterministic per-tick semantics).
#
# Iter-32 throttle-key-read-write-symmetric-fix: define _hbt_throttle_key
# ONCE here and reuse it for both the gate-read below AND the end-of-script
# write at line ~525. Pre-iter-32 the read used $SESSION_ID_FAST while the
# write used $SESSION_ID — a hidden asymmetry that silently broke the
# throttle whenever the bash regex extracted a different value than jq.
# Now the key is computed exactly once; both sides use the same variable.
_hbt_throttle_key="$SESSION_ID_FAST"

if [ -n "$_hbt_throttle_key" ] \
   && [ "$AUTOLOOP_TICK_DEDUP_INTERVAL_US" -gt 0 ] 2>/dev/null \
   && command -v gdate >/dev/null 2>&1; then
  _hbt_throttle_file="$AUTOLOOP_TICK_DEDUP_DIR/$_hbt_throttle_key.us"
  if [ -f "$_hbt_throttle_file" ]; then
    _hbt_now_us=$(gdate +%s%6N 2>/dev/null || echo 0)
    _hbt_last_us=$(cat "$_hbt_throttle_file" 2>/dev/null || echo 0)
    if [ "$_hbt_now_us" -gt 0 ] 2>/dev/null && [ "$_hbt_last_us" -gt 0 ] 2>/dev/null; then
      _hbt_elapsed_us=$((_hbt_now_us - _hbt_last_us))
      if [ "$_hbt_elapsed_us" -ge 0 ] && [ "$_hbt_elapsed_us" -lt "$AUTOLOOP_TICK_DEDUP_INTERVAL_US" ]; then
        # Throttle hit — Claude Code tool burst is mid-flight. Skip the tick.
        # Exits BEFORE library sourcing → ~12ms instead of ~25ms.
        exit 0
      fi
    fi
  fi
fi

# =============================================================================
# SLOW PATH: throttle expired (or disabled). Now source the libraries.
# =============================================================================

# ===== Source library functions =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_LIB="$SCRIPT_DIR/../scripts/registry-lib.sh"
STATE_LIB="$SCRIPT_DIR/../scripts/state-lib.sh"
PROVENANCE_LIB="$SCRIPT_DIR/../scripts/provenance-lib.sh"

if [ ! -f "$REGISTRY_LIB" ]; then
  _log_error "registry-lib.sh not found at $REGISTRY_LIB" 1
  exit 0
fi

if [ ! -f "$STATE_LIB" ]; then
  _log_error "state-lib.sh not found at $STATE_LIB" 1
  exit 0
fi

# shellcheck source=/dev/null
source "$REGISTRY_LIB" 2>/dev/null || {
  _log_error "Failed to source registry-lib.sh" 1
  exit 0
}

# shellcheck source=/dev/null
source "$STATE_LIB" 2>/dev/null || {
  _log_error "Failed to source state-lib.sh" 1
  exit 0
}

# Provenance is best-effort; missing lib is non-fatal
if [ -f "$PROVENANCE_LIB" ]; then
  # shellcheck source=/dev/null
  source "$PROVENANCE_LIB" 2>/dev/null || true
fi

export _PROV_AGENT="heartbeat-tick.sh"

# ===== Main logic =====

# Perf (iter-25 hot-path-jq-batching): one jq invocation extracts BOTH fields
# instead of two sequential spawns. Saves ~50ms cold-start on macOS per call.
# TSV output decoded by bash `read` builtin (no second subprocess needed).
# The trailing-tab fallback `printf '\t'` guarantees `read` always sees two
# columns even when jq fails or PAYLOAD lacks the fields — so SESSION_ID/CWD
# default to empty strings rather than carrying stale values from the prior tick.
#
# Perf (iter-27 jq-skip-if-regex-already-extracted): if the iter-27 bash
# regex above already extracted both fields, don't spawn jq at all. Falls
# back to jq only when the regex missed (malformed JSON, unexpected shape).
if [ -n "$SESSION_ID_FAST" ] && [ -n "$PAYLOAD_CWD_FAST" ]; then
  SESSION_ID="$SESSION_ID_FAST"
  PAYLOAD_CWD="$PAYLOAD_CWD_FAST"
else
  IFS=$'\t' read -r SESSION_ID PAYLOAD_CWD <<< "$(
    echo "$PAYLOAD" | jq -r '"\(.session_id // "")\t\(.cwd // "")"' 2>/dev/null \
      || printf '\t'
  )"
fi

# Back-compat fallback: env var (DEPRECATED — see top-of-file comment)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-}"
fi

if [ -z "$SESSION_ID" ]; then
  # No session ID anywhere — no-op (likely running outside a Claude session)
  exit 0
fi

# Step 2: Determine cwd (prefer stdin payload, fall back to pwd)
CWD_RAW="${PAYLOAD_CWD:-$(pwd 2>/dev/null || echo '')}"
# Wave 6.1: realpath normalization (see session-bind.sh comment for rationale)
if [ -n "$CWD_RAW" ] && CWD_NORM=$(cd "$CWD_RAW" 2>/dev/null && pwd -P); then
  CWD="$CWD_NORM"
else
  CWD="$CWD_RAW"
fi
if [ -z "$CWD" ]; then
  _log_error "Failed to determine cwd" 1
  exit 0
fi

# Step 3: Read registry (fail-graceful — returns empty registry if missing)
REGISTRY=$(read_registry "$REGISTRY_PATH") || {
  _log_error "Failed to read registry at $REGISTRY_PATH" 1
  exit 0
}

# Step 4: Find matching loop. Two-pass match (BIND-03 cwd-drift defense):
#   (a) primary: owner_session_id == this session — survives cwd drift
#   (b) fallback: cwd starts_with dirname(contract_path)
# Without (a), a session that drifts out of its contract dir would silently lose
# its loop binding and stop ticking heartbeat — masking the drift.
MATCHING_LOOP=""
MATCHING_LOOP_ID=""

MATCHING_LOOP=$(echo "$REGISTRY" | jq -r --arg sid "$SESSION_ID" '
.loops[] |
select(.owner_session_id == $sid) |
@json
' 2>/dev/null | head -1) || MATCHING_LOOP=""

if [ -z "$MATCHING_LOOP" ] || [ "$MATCHING_LOOP" = "" ]; then
  # Wave 6 fix: project_root ⊆ cwd ⊆ contract_dir hierarchy check
  # (matches sessions opened at the project root as well as inside .autoloop/<slug>--<hash>/).
  # See session-bind.sh for the full rationale and the on-the-fly project_root
  # derivation that backfills legacy entries without a stored created_at_cwd.
  MATCHING_LOOP=$(echo "$REGISTRY" | jq -r --arg cwd "$CWD" '
.loops[] |
select(
  (.contract_path | split("/") | .[:-1] | join("/")) as $contract_dir |
  (.created_at_cwd // "") as $stored_root |
  ((.contract_path | capture("^(?<root>.+)/\\.autoloop/[^/]+--[0-9a-f]{6}/CONTRACT\\.md$") | .root) // "") as $derived_root |
  # Wave 6.1 corruption guard: prefer derived_root when stored_root is
  # not a strict ancestor of contract_dir. See session-bind.sh for the
  # full rationale; the predicate must stay byte-identical here.
  (if ($stored_root != "") and ($contract_dir | startswith($stored_root + "/"))
   then $stored_root
   else $derived_root
   end) as $project_root |
  if $project_root == "" then
    ($cwd == $contract_dir) or ($cwd | startswith($contract_dir + "/"))
  else
    (($cwd == $project_root) or ($cwd | startswith($project_root + "/")))
      and
    (($cwd == $contract_dir) or ($contract_dir | startswith($cwd + "/")))
  end
) |
@json
' 2>/dev/null | head -1) || {
    exit 0
  }
fi

# If no matching loop found, no-op
if [ -z "$MATCHING_LOOP" ] || [ "$MATCHING_LOOP" = "" ]; then
  exit 0
fi

# Step 5+6: Decode loop_id + ownership + generation in ONE jq invocation.
#
# Perf (iter-25 hot-path-jq-batching): the original code spawned 3 separate
# jq processes here (one per field), each paying a ~50ms cold-start tax on
# macOS. Batched extraction via TSV reduces to a single spawn. The five
# fields below are the entire MATCHING_LOOP surface this hook reads — also
# eagerly grabs state_dir + contract_path so the later Step 7.5 block can
# skip its two extra spawns.
#
# Failure mode: if jq dies (e.g., MATCHING_LOOP isn't valid JSON), the
# fallback printf yields four tabs → all five vars become empty strings →
# the OWNER_SESSION_ID check below exits 0 cleanly (no-op tick). Same
# graceful degradation as the original per-field _log_error path, just
# without the per-field error message granularity.
IFS=$'\t' read -r MATCHING_LOOP_ID OWNER_SESSION_ID REGISTRY_GENERATION STATE_DIR CONTRACT_PATH <<< "$(
  echo "$MATCHING_LOOP" | jq -r '"\(.loop_id // "")\t\(.owner_session_id // "")\t\(.generation // 0)\t\(.state_dir // "")\t\(.contract_path // "")"' 2>/dev/null \
    || printf '\t\t0\t\t'
)"

if [ -z "$MATCHING_LOOP_ID" ]; then
  _log_error "Failed to extract loop_id from matching loop" 1
  exit 0
fi

if [ "$OWNER_SESSION_ID" != "$SESSION_ID" ]; then
  # Different session owns this loop; no-op (don't tick another session's heartbeat)
  exit 0
fi

# Read current heartbeat.
#
# Perf (iter-26 read-heartbeat-state-dir-hint): pass STATE_DIR (already
# extracted from the batched MATCHING_LOOP decode above) so read_heartbeat
# skips its registry round-trip. Saves 3 jq spawns (read_registry's `jq .`
# + select + state_dir extract) on every Claude Code tool invocation.
HB=$(read_heartbeat "$MATCHING_LOOP_ID" "" "$STATE_DIR" 2>/dev/null || echo "{}") || {
  # Gracefully handle read_heartbeat failure
  HB="{}"
}

# Step 6+7+7.5 prep: batch-extract heartbeat fields (generation + iteration
# + bound_cwd) in ONE jq spawn.
#
# Perf (iter-25 hot-path-jq-batching): the original code did two separate
# `jq -r` calls on $HB, each ~50ms cold-start on macOS. The iteration field
# is consumed below in Step 7's increment.
#
# Perf (iter-26 fold-pre-bound-cwd-into-hb-batch): bound_cwd used to be
# extracted in a separate `jq -r '.bound_cwd // ""' "$HB_FILE"` invocation
# below in Step 7.5 — but $HB is loaded above via `read_heartbeat`, which is
# the same content as $HB_FILE at that point (we haven't written yet). One
# extra TSV column makes that 4th jq spawn vanish.
IFS=$'\t' read -r HB_GENERATION CURRENT_ITERATION PRE_BOUND_CWD <<< "$(
  echo "$HB" | jq -r '"\(.generation // 0)\t\(.iteration // 0)\t\(.bound_cwd // "")"' 2>/dev/null \
    || printf '0\t0\t'
)"

# If generation mismatch: this session has been reclaimed
if [ "$HB_GENERATION" != "$REGISTRY_GENERATION" ]; then
  # Perf (iter-25 hot-path-jq-batching): STATE_DIR already extracted above in
  # the batched MATCHING_LOOP decode; no extra jq spawn needed here.
  if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR/revision-log" ]; then
    SUPERSEDED_FILE="$STATE_DIR/revision-log/superseded-$(date +%s%N).json"
    {
      jq -n \
        --arg loop_id "$MATCHING_LOOP_ID" \
        --arg session_id "$SESSION_ID" \
        --arg reason "Generation mismatch: heartbeat=$HB_GENERATION, registry=$REGISTRY_GENERATION" \
        '{loop_id: $loop_id, session_id: $session_id, event: "superseded", reason: $reason, ts_us: '"$(python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null || echo '0')"'}' \
        > "$SUPERSEDED_FILE" 2>/dev/null || true
    }
  fi

  # Exit 0 without ticking heartbeat
  exit 0
fi

# Step 7: Increment iteration counter (already decoded by the batched HB jq above).
NEW_ITERATION=$((CURRENT_ITERATION + 1))

# Step 7.5 (BIND-03 prep): capture bound_cwd from existing heartbeat BEFORE
# write_heartbeat overwrites the file. write_heartbeat replaces the entire
# JSON object (no field-level merge), so any drift state we want to preserve
# across ticks must be re-applied below via jq merge after the rewrite.
#
# Perf (iter-25 hot-path-jq-batching): STATE_DIR + CONTRACT_PATH already
# extracted above in the batched MATCHING_LOOP decode; two jq spawns saved.
# Perf (iter-26 fold-pre-bound-cwd-into-hb-batch): PRE_BOUND_CWD already
# extracted in the Step 6+7 HB batch above; one more jq spawn saved.
HB_FILE="$STATE_DIR/heartbeat.json"

# Call write_heartbeat to atomically write new heartbeat.
#
# Perf (iter-26 write-heartbeat-zero-registry-read-fast-path): pass the
# already-extracted STATE_DIR + CONTRACT_PATH + REGISTRY_GENERATION as hints
# so write_heartbeat skips its registry round-trip entirely. heartbeat-tick
# already paid for the registry read via the MATCHING_LOOP batched decode
# (line ~207 above); duplicating that read inside write_heartbeat costs 3
# more jq spawns (~21ms on macOS) for no new information.
if ! write_heartbeat "$MATCHING_LOOP_ID" "$SESSION_ID" "$NEW_ITERATION" "" \
      "$STATE_DIR" "$CONTRACT_PATH" "$REGISTRY_GENERATION" 2>/dev/null; then
  _log_error "Failed to write heartbeat for loop $MATCHING_LOOP_ID" 1
  exit 0
fi

# v2: mirror heartbeat into contract frontmatter (best-effort; registry+heartbeat
# are SSoT). Failure here MUST NOT abort the loop tick — a stale frontmatter is
# fine; an aborted heartbeat is not.
#
# Perf (iter-28 batched-frontmatter-rewrite-single-awk-pass): pre-iter-28 this
# block invoked set_contract_field FOUR times, each parsing+rewriting the
# entire contract via its own awk+mktemp+mv cycle (~8-12ms each on macOS).
# The batched variant takes all four (field, value) pairs in one awk pass.
# Savings: ~25-35ms per slow-path tick. Same metachar-safe literal-prefix
# match, same atomic mv semantics.
if [ -n "$CONTRACT_PATH" ] && [ -f "$CONTRACT_PATH" ] && command -v set_contract_frontmatter_field_batch >/dev/null 2>&1; then
  _NOW_US=$(now_us 2>/dev/null || echo "")
  if [ -n "$_NOW_US" ]; then
    set_contract_frontmatter_field_batch "$CONTRACT_PATH" \
      "last_heartbeat_us" "$_NOW_US" \
      "last_heartbeat_session_id" "\"$SESSION_ID\"" \
      "iteration" "$NEW_ITERATION" \
      "generation" "$REGISTRY_GENERATION" \
      2>/dev/null || true
  else
    # no_us unavailable — omit last_heartbeat_us but still update the other 3
    set_contract_frontmatter_field_batch "$CONTRACT_PATH" \
      "last_heartbeat_session_id" "\"$SESSION_ID\"" \
      "iteration" "$NEW_ITERATION" \
      "generation" "$REGISTRY_GENERATION" \
      2>/dev/null || true
  fi
fi

# Step 8 (BIND-03): cwd-drift detection.
# Re-merge bound_cwd into the freshly-written heartbeat.json (write_heartbeat
# doesn't preserve our extension fields). Detect drift if PRE_BOUND_CWD was
# set and current CWD doesn't sit under it.
if [ -n "$STATE_DIR" ] && [ -f "$HB_FILE" ] && [ -n "$CONTRACT_PATH" ]; then
  # Wave 6.2: canonicalize CONTRACT_DIR via realpath. CWD on line 118 is
  # already realpath-resolved, so deriving CONTRACT_DIR with bare `dirname`
  # left a symlink-asymmetric BOUND_CWD on disk: a session under
  # `~/work/...` would see CWD=/Volumes/work/... but BOUND_CWD=/Users/.../work/...
  # The case glob at the bottom of this block then mismatched and falsely
  # flagged cwd_drift. `cd && pwd -P` matches the same normalization the
  # bind hook performs, so writer and reader speak the same encoding.
  CONTRACT_DIR=$(cd "$(dirname "$CONTRACT_PATH")" 2>/dev/null && pwd -P) || \
    CONTRACT_DIR=$(dirname "$CONTRACT_PATH")
  BOUND_CWD="$PRE_BOUND_CWD"

  if [ -z "$BOUND_CWD" ]; then
    # First heartbeat after binding — record bound_cwd
    TMP=$(mktemp "$HB_FILE.XXXXXX") || TMP=""
    if [ -n "$TMP" ]; then
      if jq --arg bc "$CONTRACT_DIR" '. + {bound_cwd: $bc, cwd_drift_detected: false}' "$HB_FILE" >"$TMP" 2>/dev/null; then
        mv "$TMP" "$HB_FILE" 2>/dev/null || rm -f "$TMP"
      else
        rm -f "$TMP"
      fi
    fi
    if command -v emit_provenance >/dev/null 2>&1; then
      emit_provenance "$MATCHING_LOOP_ID" "bound_cwd_recorded" \
        session_id="$SESSION_ID" \
        cwd_observed="$CWD" \
        cwd_bound="$CONTRACT_DIR" \
        registry_generation="$REGISTRY_GENERATION" \
        decision="proceeded" 2>/dev/null || true
    fi
  else
    # Subsequent heartbeat — check for drift
    case "$CWD" in
      "$BOUND_CWD"*)
        : # cwd matches; no action
        ;;
      *)
        # Drift detected — flag in heartbeat + emit provenance
        TMP=$(mktemp "$HB_FILE.XXXXXX") || TMP=""
        if [ -n "$TMP" ]; then
          if jq '. + {cwd_drift_detected: true}' "$HB_FILE" >"$TMP" 2>/dev/null; then
            mv "$TMP" "$HB_FILE" 2>/dev/null || rm -f "$TMP"
          else
            rm -f "$TMP"
          fi
        fi
        if command -v emit_provenance >/dev/null 2>&1; then
          emit_provenance "$MATCHING_LOOP_ID" "cwd_drift_detected" \
            session_id="$SESSION_ID" \
            cwd_observed="$CWD" \
            cwd_bound="$BOUND_CWD" \
            registry_generation="$REGISTRY_GENERATION" \
            reason="current cwd diverged from bound_cwd; resume disabled until reclaim" \
            decision="refused" 2>/dev/null || true
        fi
        ;;
    esac
  fi
fi

# Iter-27 tool-burst-tick-deduplication: record this successful tick's
# timestamp so the throttle gate above can skip near-future bursts. Written
# AFTER write_heartbeat succeeds (a failed tick shouldn't burn its throttle
# window — the next call should still attempt the work).
#
# Iter-32 throttle-key-read-write-symmetric-fix: $_hbt_throttle_key was
# computed once at the top of the script (next to the throttle gate). Reuse
# the SAME variable here so read and write are textually identical — no
# possibility of one side updating while the other doesn't. Fall back to
# $SESSION_ID if the iter-27 bash regex missed (e.g. malformed PAYLOAD or
# a non-UUID session_id that fails the iter-32 UUID-shape check).
[ -z "${_hbt_throttle_key:-}" ] && _hbt_throttle_key="$SESSION_ID"
if [ -n "$_hbt_throttle_key" ] && [ "$AUTOLOOP_TICK_DEDUP_INTERVAL_US" -gt 0 ] 2>/dev/null \
   && command -v gdate >/dev/null 2>&1; then
  mkdir -p "$AUTOLOOP_TICK_DEDUP_DIR" 2>/dev/null || true
  _hbt_now_us_end=$(gdate +%s%6N 2>/dev/null || echo "")
  if [ -n "$_hbt_now_us_end" ]; then
    echo "$_hbt_now_us_end" > "$AUTOLOOP_TICK_DEDUP_DIR/$_hbt_throttle_key.us" 2>/dev/null || true
  fi
fi

# Success: exit gracefully
exit 0
