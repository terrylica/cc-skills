#!/usr/bin/env bash
# FILE-SIZE-OK
# registry-lib.sh — Loop ID derivation and registry read helpers for autoloop
# Provides deterministic loop ID generation and read-only registry access

set -euo pipefail

# Source portable.sh for is_valid_jq_simple_path / log_validation_event.
# Tolerate missing file (callers without portable.sh fall back to no validation
# beyond the legacy regex checks already in this file).
_REGISTRY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -f "$_REGISTRY_LIB_DIR/portable.sh" ]; then
  # shellcheck source=/dev/null
  source "$_REGISTRY_LIB_DIR/portable.sh" 2>/dev/null || true
fi

# derive_loop_id <path>
# Derives a stable 12-character hexadecimal loop ID from an absolute contract path.
# Uses sha256(realpath) to ensure deterministic output and collision-free identity.
#
# Arguments:
#   $1: Contract file path (absolute or relative; will be resolved via realpath)
#
# Output:
#   12-character hexadecimal string to stdout
#
# Exit code:
#   0 on success
#   1 if realpath fails (contract path doesn't exist or is inaccessible)
#
# Example:
#   loop_id=$(derive_loop_id "/Users/user/project/LOOP_CONTRACT.md")
#   echo "$loop_id"  # Output: a1b2c3d4e5f6
derive_loop_id() {
  local contract_path="$1"

  # Resolve to absolute path, handling symlinks
  local resolved_path
  if ! resolved_path=$(realpath "$contract_path" 2>/dev/null); then
    echo "ERROR: derive_loop_id: cannot resolve path '$contract_path'" >&2
    return 1
  fi

  # Compute SHA256 hash and take first 12 hex characters
  echo -n "$resolved_path" | shasum -a 256 | cut -c 1-12
}

# read_registry [registry_path_override]
# Reads the machine-level registry file and returns parsed JSON.
# Handles missing files (returns empty registry) and malformed JSON (warns, returns empty).
#
# Arguments:
#   $1 (optional): Override path to registry file (for testing); defaults to ~/.claude/loops/registry.json
#
# Output:
#   Valid JSON on stdout: either parsed registry or empty registry
#   Warnings may go to stderr if file is malformed
#
# Exit code:
#   0 always (fail-graceful) unless a fatal error occurs (e.g., jq not installed)
#
# Example:
#   registry=$(read_registry)
#   count=$(echo "$registry" | jq '.loops | length')
read_registry() {
  local registry_path="${1:-$HOME/.claude/loops/registry.json}"
  local empty_registry='{"loops": [], "schema_version": 1}'

  # Check if file exists
  if [ ! -f "$registry_path" ]; then
    echo "$empty_registry"
    return 0
  fi

  # Try to parse as JSON
  if ! jq . "$registry_path" 2>/dev/null; then
    echo "WARNING: registry.json at '$registry_path' is malformed; treating as empty" >&2
    echo "$empty_registry"
    return 0
  fi
}

# read_registry_entry <loop_id> [registry_path_override]
# Fetches a single loop entry from the registry by loop_id.
#
# Arguments:
#   $1: Loop ID (12 hexadecimal characters)
#   $2 (optional): Override path to registry file (for testing)
#
# Output:
#   Entry object as JSON if found; empty object {} if not found
#   Errors go to stderr
#
# Exit code:
#   0 on success (entry found or gracefully not found)
#   1 if loop_id format is invalid or jq fails
#
# Example:
#   entry=$(read_registry_entry "a1b2c3d4e5f6")
#   if [[ "$entry" != "{}" ]]; then
#     owner=$(echo "$entry" | jq -r '.owner_session_id')
#   fi
read_registry_entry() {
  local loop_id="$1"
  local registry_path="${2:-$HOME/.claude/loops/registry.json}"

  # Validate loop_id format (exactly 12 hex characters)
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: read_registry_entry: invalid loop_id format '$loop_id' (must be 12 hex chars)" >&2
    return 1
  fi

  # Get full registry and search for entry
  local registry
  registry=$(read_registry "$registry_path") || return 1

  # Use jq to find the entry. --arg keeps loop_id outside the jq AST so a
  # malformed value can't escape the JSON string boundary even if validation
  # above is bypassed by a future code change.
  local entry
  entry=$(echo "$registry" | jq --arg id "$loop_id" '.loops[] | select(.loop_id == $id) // empty' 2>/dev/null) || {
    echo "ERROR: read_registry_entry: jq query failed" >&2
    return 1
  }

  # Return entry if found, otherwise empty object
  if [ -n "$entry" ]; then
    echo "$entry"
  else
    echo "{}"
  fi
}

# _with_registry_lock <fn> [args...]
# Internal: wraps read-modify-write in file-locking serialization.
# Acquires exclusive lock on ~/.claude/loops/.registry.lock (using lockf on macOS, flock on Linux),
# reads current registry, calls fn with args, captures stdout as new registry,
# atomic-renames to registry.json, releases lock.
#
# Arguments:
#   $1: Function name to invoke (fn)
#   ${@:2}: Args to pass to fn
#
# Stdin to fn: current registry JSON
# Expected stdout from fn: new registry JSON
#
# Exit code:
#   0 on success
#   1 if lock contention (timeout), temp write error, or fn exit code != 0
#   Partial writes cleaned up via trap before exit
#
# Example:
#   _with_registry_lock register_loop_impl "$entry_json"
_with_registry_lock() {
  local fn="$1"
  shift

  # Ensure ~/.claude/loops/ directory exists
  local loops_dir="$HOME/.claude/loops"
  if [ ! -d "$loops_dir" ]; then
    mkdir -p "$loops_dir" || {
      echo "ERROR: _with_registry_lock: failed to create $loops_dir" >&2
      return 1
    }
  fi

  local lock_file="$loops_dir/.registry.lock"
  local registry_file="$loops_dir/registry.json"
  local temp_file=""

  # Clean up temp files on exit (trap early to cover all paths).
  # Use ${temp_file:-} so the trap is safe even when it fires after the function
  # returns (the local var goes out of scope at script exit).
  trap 'rm -f "${temp_file:-}"; exec 9>&- 2>/dev/null || true' EXIT

  # Create lock file if it doesn't exist
  touch "$lock_file" || {
    echo "ERROR: _with_registry_lock: failed to create lock file" >&2
    return 1
  }

  # Acquire exclusive lock using appropriate tool
  # macOS: lockf (POSIX); Linux: flock (GNU)
  if command -v flock >/dev/null 2>&1; then
    # Linux: flock with fd 9
    exec 9>"$lock_file" || {
      echo "ERROR: _with_registry_lock: failed to open fd 9" >&2
      return 1
    }
    if ! flock --wait 5 -x 9; then
      echo "ERROR: _with_registry_lock: lock contention; another writer is active" >&2
      exec 9>&-
      return 1
    fi
  elif command -v lockf >/dev/null 2>&1; then
    # macOS: lockf (blocks indefinitely by default, so we use timeout via sleep-retry)
    local retries=50  # ~5 seconds with 100ms sleeps
    while ! lockf -t 0 "$lock_file" true 2>/dev/null; do
      retries=$((retries - 1))
      if [ $retries -le 0 ]; then
        echo "ERROR: _with_registry_lock: lock contention; another writer is active" >&2
        return 1
      fi
      sleep 0.1
    done
  else
    echo "ERROR: _with_registry_lock: neither flock nor lockf found; cannot acquire lock" >&2
    return 1
  fi

  # Read current registry (fail-graceful)
  local current_registry
  current_registry=$(read_registry "$registry_file") || {
    echo "ERROR: _with_registry_lock: failed to read registry" >&2
    return 1
  }

  # Call fn with current registry on stdin, capture output
  local new_registry
  if ! new_registry=$(echo "$current_registry" | "$fn" "$@" 2>&1); then
    echo "ERROR: _with_registry_lock: fn '$fn' failed" >&2
    return 1
  fi

  # Validate new registry is valid JSON before writing
  if ! echo "$new_registry" | jq . >/dev/null 2>&1; then
    echo "ERROR: _with_registry_lock: fn produced invalid JSON" >&2
    return 1
  fi

  # Create temp file in same directory (defends pitfall #3: cross-filesystem rename)
  temp_file=$(mktemp -p "$loops_dir" registry.XXXXXX.json) || {
    echo "ERROR: _with_registry_lock: mktemp failed" >&2
    return 1
  }

  # Write full new content to tempfile, then fsync
  if ! echo "$new_registry" > "$temp_file"; then
    echo "ERROR: _with_registry_lock: failed to write temp file" >&2
    return 1
  fi

  # Sync to disk (fsync via sync if available, otherwise skip)
  if command -v fsync >/dev/null 2>&1; then
    fsync "$temp_file" || true
  else
    sync || true
  fi

  # Pre-rename JSON validation (W2.3). The in-memory check at line 226 catches
  # fn-produced garbage; this catches DISK-side truncation between `echo >`
  # and `mv` — disk-full, filesystem error, OOM-killed echo. Without this gate
  # a partial `}{`-style write could silently replace registry.json. If the
  # temp file is invalid, abort and let the trap clean it up; the original
  # registry.json is untouched.
  if ! jq empty "$temp_file" >/dev/null 2>&1; then
    echo "ERROR: _with_registry_lock: temp file is not valid JSON post-write — aborting transaction" >&2
    if command -v log_validation_event >/dev/null 2>&1; then
      log_validation_event registry_corrupt_pre_rename temp_file "$temp_file" caller=_with_registry_lock fn="$fn"
    fi
    return 1
  fi

  # Atomic rename to commit
  if ! mv "$temp_file" "$registry_file"; then
    echo "ERROR: _with_registry_lock: atomic rename failed" >&2
    return 1
  fi

  # Explicitly unset temp file so trap doesn't try to rm it (it's now registry.json)
  temp_file=""

  # Lock is released by trap on EXIT
  return 0
}

# register_loop_impl [entry_json]
# Implementation function: reads stdin (current registry), adds new entry, outputs new registry.
# This is the "mutator function" passed to _with_registry_lock.
#
# Arguments:
#   $1: New entry JSON object (passed as argument)
#
# Stdin:
#   Current registry JSON
#
# Output:
#   Updated registry JSON to stdout
#
# Exit code:
#   0 on success
#   1 if entry.loop_id already exists or validation fails
register_loop_impl() {
  local entry_json="$1"

  # Parse stdin as registry
  local registry
  registry=$(cat)

  # Extract loop_id from new entry
  local new_loop_id
  new_loop_id=$(echo "$entry_json" | jq -r '.loop_id' 2>/dev/null) || {
    echo "ERROR: register_loop_impl: failed to extract loop_id from entry" >&2
    return 1
  }

  # Validate loop_id format
  if ! [[ "$new_loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: register_loop_impl: invalid loop_id format '$new_loop_id'" >&2
    return 1
  fi

  # Check if loop_id already exists (--arg avoids string-interpolation injection)
  local existing
  existing=$(echo "$registry" | jq --arg id "$new_loop_id" '.loops[] | select(.loop_id == $id)' 2>/dev/null)
  if [ -n "$existing" ]; then
    echo "ERROR: register_loop_impl: loop_id '$new_loop_id' already exists" >&2
    return 1
  fi

  # Append entry to loops array. --argjson parses entry_json as JSON; the call
  # site (register_loop) already validated it.
  echo "$registry" | jq --argjson entry "$entry_json" '.loops += [$entry]' 2>/dev/null || {
    echo "ERROR: register_loop_impl: jq update failed" >&2
    return 1
  }
}

# register_loop <json_entry>
# Public: registers a new loop entry in the registry.
# Entry must have all required fields (loop_id, contract_path, etc.) per schema.
# Errors if loop_id already exists.
#
# Arguments:
#   $1: Complete entry JSON object (with all required fields)
#
# Exit code:
#   0 on success
#   1 if entry is invalid, loop_id exists, or write fails
#
# Example:
#   entry=$(jq -n --arg id "a1b2c3d4e5f6" --arg path "/tmp/contract.md" '{loop_id: $id, contract_path: $path, ...}')
#   register_loop "$entry"
register_loop() {
  local entry_json="$1"

  # Validate entry is valid JSON
  if ! echo "$entry_json" | jq . >/dev/null 2>&1; then
    echo "ERROR: register_loop: entry is not valid JSON" >&2
    return 1
  fi

  # Call write-locked helper
  _with_registry_lock register_loop_impl "$entry_json" || return 1
}

# unregister_loop_impl <loop_id>
# Implementation function: reads stdin (current registry), removes entry by loop_id, outputs new registry.
#
# Arguments:
#   $1: loop_id to remove
#
# Stdin:
#   Current registry JSON
#
# Output:
#   Updated registry JSON to stdout
#
# Exit code:
#   0 always (idempotent; no error if loop_id absent)
unregister_loop_impl() {
  local loop_id="$1"

  # Parse stdin as registry
  local registry
  registry=$(cat)

  # Remove entry by loop_id (if present). --arg avoids string-interpolation injection.
  echo "$registry" | jq --arg id "$loop_id" '.loops |= map(select(.loop_id != $id))' 2>/dev/null || {
    echo "ERROR: unregister_loop_impl: jq update failed" >&2
    return 1
  }
}

# unregister_loop <loop_id>
# Public: removes a loop entry from the registry by loop_id.
# Idempotent: no error if loop_id not found (desirable for clean stop).
#
# Arguments:
#   $1: loop_id to remove
#
# Exit code:
#   0 always (idempotent success)
#   1 only if loop_id format invalid or write lock fails
#
# Example:
#   unregister_loop "a1b2c3d4e5f6"
unregister_loop() {
  local loop_id="$1"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: unregister_loop: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Call write-locked helper (returns 0 even if not found)
  _with_registry_lock unregister_loop_impl "$loop_id" || return 1
}

# update_loop_field_impl <loop_id> <jq_path> <new_value_json>
# PROCESS-STORM-OK (bash function definition, not a fork bomb)
# Implementation function: reads stdin (current registry), updates field on entry, outputs new registry.
#
# Arguments:
#   $1: loop_id to update
#   $2: jq path expression (e.g., ".generation" or ".metadata.last_heartbeat_us")
#   $3: new value as JSON
#
# Stdin:
#   Current registry JSON
#
# Output:
#   Updated registry JSON to stdout
#
# Exit code:
#   0 on success
#   1 if loop_id not found or jq update fails
update_loop_field_impl() {
  local loop_id="$1"
  local jq_path="$2"
  local new_value="$3"

  # Defense-in-depth: whitelist jq_path here as well. The public entry point
  # update_loop_field already validates, but impl is exported and could be
  # called directly by tests or future callers.
  if ! [[ "$jq_path" =~ ^\.[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "ERROR: update_loop_field_impl: jq_path '$jq_path' rejected (must match ^\\.[a-zA-Z_][a-zA-Z0-9_]*$)" >&2
    return 1
  fi

  # Parse stdin as registry
  local registry
  registry=$(cat)

  # Find and update entry. Loop_id goes through --arg; jq_path is interpolated
  # into the filter (whitelist already restricted it to a simple dotted path).
  # new_value is interpolated as JSON literal — caller is responsible for
  # passing valid JSON (numbers, "strings", true/false, null).
  local updated
  updated=$(echo "$registry" | jq --arg id "$loop_id" "(.loops[] | select(.loop_id == \$id) | $jq_path) |= $new_value" 2>/dev/null) || {
    echo "ERROR: update_loop_field_impl: jq update failed" >&2
    return 1
  }

  # Verify entry exists by checking if the loop_id is still in the result
  local exists
  exists=$(echo "$updated" | jq --arg id "$loop_id" '.loops[] | select(.loop_id == $id)' 2>/dev/null)
  if [ -z "$exists" ]; then
    echo "ERROR: update_loop_field_impl: loop_id '$loop_id' not found" >&2
    return 1
  fi

  echo "$updated"
}

# update_loop_field <loop_id> <jq_path> <new_value_json>
# Public: updates a field on an existing loop entry.
# Used by Phase 5+ for heartbeat metadata, Phase 4 for generation bump.
#
# Arguments:
#   $1: loop_id of entry to update
#   $2: jq path expression (e.g., ".generation" or ".metadata.heartbeat_us")
#   $3: new value as JSON (e.g., "1" or "1725000000000000")
#
# Exit code:
#   0 on success
#   1 if loop_id not found, jq_path invalid, or write fails
#
# Example:
#   update_loop_field "a1b2c3d4e5f6" ".generation" "2"
update_loop_field() {
  local loop_id="$1"
  local jq_path="$2"
  local new_value="$3"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: update_loop_field: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Validate jq_path is a single-key dotted path (^\.[a-zA-Z_][a-zA-Z0-9_]*$).
  # This blocks env-injection (".env"), debug-injection (".debug"), and any
  # pipe-chained jq filters that could read or mutate fields beyond the named
  # one. All current callers use simple paths like .generation, .owner_pid.
  if ! [[ "$jq_path" =~ ^\.[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "ERROR: update_loop_field: jq_path '$jq_path' rejected (must match ^\\.[a-zA-Z_][a-zA-Z0-9_]*$)" >&2
    if command -v log_validation_event >/dev/null 2>&1; then
      log_validation_event validation_reject jq_path "$jq_path" caller=update_loop_field
    fi
    return 1
  fi

  # Call write-locked helper
  _with_registry_lock update_loop_field_impl "$loop_id" "$jq_path" "$new_value" || return 1
}

# Export functions for sourcing by other scripts
export -f derive_loop_id
export -f read_registry
export -f read_registry_entry
export -f _with_registry_lock
export -f register_loop_impl
export -f register_loop
export -f unregister_loop_impl
export -f unregister_loop
export -f update_loop_field_impl
export -f update_loop_field
