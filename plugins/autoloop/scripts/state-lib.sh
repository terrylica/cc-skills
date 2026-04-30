#!/usr/bin/env bash
# state-lib.sh — State directory and atomic heartbeat primitives for autoloop
# Provides: now_us, state_dir_path, init_state_dir, write_heartbeat, read_heartbeat

set -euo pipefail

# now_us
# Returns current time in microseconds since epoch.
# Uses gdate (GNU date) if available, with fallback to python3 for macOS.
# Microsecond precision is important for heartbeat timestamps and stale detection.
#
# Output:
#   Integer: microseconds since Unix epoch
#
# Exit code:
#   0 on success
#   1 if neither gdate nor python3 available (fatal)
#
# Example:
#   ts=$(now_us)
#   echo "$ts"  # Output: 1725000000123456
now_us() {
  # Try gdate first (GNU date, available on Linux and macOS via coreutils)
  if command -v gdate >/dev/null 2>&1; then
    local ns
    ns=$(gdate +%s%N 2>/dev/null) || {
      # Fallback if gdate fails
      python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null && return 0
      return 1
    }
    # Convert nanoseconds to microseconds (last 6 digits)
    echo $((ns / 1000))
    return 0
  fi

  # Fallback to python3 (available on all platforms)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; print(int(time.time()*1_000_000))" 2>/dev/null && return 0
  fi

  echo "ERROR: now_us: neither gdate nor python3 available" >&2
  return 1
}

# state_dir_path <loop_id> <contract_path>
# Returns the absolute path to a loop's state directory.
# State dir is <git_toplevel>/.loop-state/<loop_id>
# Falls back to contract's parent directory if not in a git repo.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: contract_path (absolute or relative path to contract file)
#
# Output:
#   Absolute path to state directory
#
# Exit code:
#   0 on success
#   1 if contract_path doesn't resolve
#
# Example:
#   state_dir=$(state_dir_path "a1b2c3d4e5f6" "/path/to/LOOP_CONTRACT.md")
#   echo "$state_dir"  # Output: /path/to/repo/.loop-state/a1b2c3d4e5f6
state_dir_path() {
  local loop_id="$1"
  local contract_path="$2"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: state_dir_path: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Resolve contract path to absolute
  local contract_abs
  local contract_dir
  contract_dir=$(cd "$(dirname "$contract_path")" && pwd -P) || {
    echo "ERROR: state_dir_path: cannot resolve contract_path '$contract_path'" >&2
    return 1
  }
  contract_abs="$contract_dir/$(basename "$contract_path")"

  # Try to find git toplevel
  local repo_root
  if repo_root=$(git -C "$(dirname "$contract_abs")" rev-parse --show-toplevel 2>/dev/null); then
    echo "$repo_root/.loop-state/$loop_id"
    return 0
  fi

  # Fallback: use contract's parent directory
  echo "$(dirname "$contract_abs")/.loop-state/$loop_id"
  return 0
}

# init_state_dir <loop_id> <contract_path>
# Initializes the state directory for a loop. Creates directories, adds .gitignore entry,
# auto-derives loop_id in contract frontmatter if missing, and registers in loop registry.
# Idempotent: safe to call multiple times.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: contract_path (absolute or relative path to contract file)
#
# Exit code:
#   0 on success (or already initialized)
#   1 if state_dir cannot be determined or critical operations fail
#
# Side effects:
#   - Creates <state_dir>/revision-log/ directory
#   - Adds .loop-state/ to repo's .gitignore (idempotent)
#   - Auto-adds loop_id to contract frontmatter if missing (MIG-01 partial)
#   - Registers loop in registry if not already registered (MIG-02)
#
# Example:
#   init_state_dir "a1b2c3d4e5f6" "/path/to/LOOP_CONTRACT.md"
init_state_dir() {
  local loop_id="$1"
  local contract_path="$2"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: init_state_dir: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Resolve state directory path
  local state_dir
  if ! state_dir=$(state_dir_path "$loop_id" "$contract_path"); then
    echo "ERROR: init_state_dir: failed to determine state_dir" >&2
    return 1
  fi

  # Create state directory and revision-log subdirectory
  mkdir -p "$state_dir/revision-log" || {
    echo "ERROR: init_state_dir: failed to create state directory '$state_dir'" >&2
    return 1
  }

  # Resolve git toplevel for .gitignore
  local repo_root
  if repo_root=$(git -C "$(dirname "$contract_path")" rev-parse --show-toplevel 2>/dev/null); then
    # Add .loop-state/ to repo's .gitignore (idempotent)
    local gitignore_path="$repo_root/.gitignore"

    # Create .gitignore if it doesn't exist
    if [ ! -f "$gitignore_path" ]; then
      touch "$gitignore_path" || {
        echo "ERROR: init_state_dir: failed to create .gitignore" >&2
        return 1
      }
    fi

    # Add .loop-state/ entry if not already present (idempotent via grep)
    if ! grep -q "^\.loop-state/$" "$gitignore_path"; then
      echo ".loop-state/" >> "$gitignore_path" || {
        echo "ERROR: init_state_dir: failed to update .gitignore" >&2
        return 1
      }
    fi
  fi

  # Auto-derive loop_id in contract frontmatter if missing (MIG-01 partial)
  if [ -f "$contract_path" ]; then
    if ! grep -q "^loop_id:" "$contract_path"; then
      # Insert loop_id after name: line
      if grep -q "^name:" "$contract_path"; then
        sed -i.bak '/^name:/a\
loop_id: '"$loop_id" "$contract_path" || true
        rm -f "${contract_path}.bak"
      else
        # If no name: line, just prepend after opening --- if present
        if head -1 "$contract_path" | grep -q "^---"; then
          sed -i.bak '2i\
loop_id: '"$loop_id" "$contract_path" || true
          rm -f "${contract_path}.bak"
        fi
      fi
    fi

    # v2 birth record: stamp immutable fields once (idempotent — only writes
    # missing fields). Mutable owner mirror fields are written by hooks/reclaim.
    init_contract_frontmatter_v2 "$contract_path" "$loop_id" "$state_dir" 2>/dev/null || true
  fi

  # Source registry-lib to check if entry exists and register if needed (MIG-02)
  local registry_lib_dir
  registry_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ -f "$registry_lib_dir/registry-lib.sh" ]; then
    # shellcheck source=/dev/null
    source "$registry_lib_dir/registry-lib.sh" 2>/dev/null || true

    # Check if entry already exists
    local existing_entry
    existing_entry=$(read_registry_entry "$loop_id" 2>/dev/null) || existing_entry="{}"

    if [ "$existing_entry" = "{}" ] || [ -z "$existing_entry" ]; then
      # Auto-register entry if missing (MIG-02)
      local entry_json
      entry_json=$(jq -n \
        --arg loop_id "$loop_id" \
        --arg contract_path "$contract_path" \
        --arg state_dir "$state_dir" \
        --arg generation "0" \
        '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, generation: $generation}')

      register_loop "$entry_json" 2>/dev/null || true
    fi
  fi

  return 0
}

# write_heartbeat <loop_id> <session_id> <iteration> [contract_path]
# Atomically writes heartbeat.json to the loop's state directory.
# Uses mktemp + mv for atomic write (defends pitfall #3: cross-filesystem rename).
# Captures current registry generation and stamps it in the heartbeat.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: session_id (loop session identifier)
#   $3: iteration (iteration number, integer)
#   $4 (optional): contract_path (if not in standard location; defaults to derived from registry)
#
# Output:
#   None on success; error messages to stderr on failure
#
# Exit code:
#   0 on success
#   1 if state_dir doesn't exist, mktemp fails, or registry read fails
#
# Side effects:
#   - Writes heartbeat.json atomically in state_dir
#   - On mv failure, tempfile is cleaned up; previous heartbeat survives
#
# Example:
#   write_heartbeat "a1b2c3d4e5f6" "session_123456_abc def" 1
write_heartbeat() {
  local loop_id="$1"
  local session_id="$2"
  local iteration="$3"
  local contract_path="${4:-}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: write_heartbeat: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Determine state_dir: if contract_path provided, use it; otherwise read from registry
  local state_dir
  if [ -n "$contract_path" ]; then
    if ! state_dir=$(state_dir_path "$loop_id" "$contract_path"); then
      echo "ERROR: write_heartbeat: failed to determine state_dir from contract_path" >&2
      return 1
    fi
  else
    # Try to read state_dir from registry
    local registry_lib_dir
    registry_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ -f "$registry_lib_dir/registry-lib.sh" ]; then
      # shellcheck source=/dev/null
      source "$registry_lib_dir/registry-lib.sh" 2>/dev/null || {
        echo "ERROR: write_heartbeat: cannot source registry-lib.sh" >&2
        return 1
      }

      local entry
      entry=$(read_registry_entry "$loop_id" 2>/dev/null) || {
        echo "ERROR: write_heartbeat: failed to read registry entry" >&2
        return 1
      }

      if [ "$entry" = "{}" ] || [ -z "$entry" ]; then
        echo "ERROR: write_heartbeat: loop_id not found in registry" >&2
        return 1
      fi

      state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || {
        echo "ERROR: write_heartbeat: failed to extract state_dir from registry entry" >&2
        return 1
      }
    else
      echo "ERROR: write_heartbeat: cannot locate registry-lib.sh" >&2
      return 1
    fi
  fi

  # Ensure state_dir exists
  if [ ! -d "$state_dir" ]; then
    echo "ERROR: write_heartbeat: state directory '$state_dir' does not exist" >&2
    return 1
  fi

  # Get current timestamp in microseconds
  local last_wake_us
  if ! last_wake_us=$(now_us); then
    echo "ERROR: write_heartbeat: failed to get current timestamp" >&2
    return 1
  fi

  # Read current generation from registry
  local generation="0"
  local registry_lib_dir
  registry_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ -f "$registry_lib_dir/registry-lib.sh" ]; then
    local entry
    entry=$(read_registry_entry "$loop_id" 2>/dev/null) || entry="{}"
    generation=$(echo "$entry" | jq -r '.generation // 0' 2>/dev/null) || generation="0"
  fi

  # Create temporary file in state_dir (same filesystem — pitfall #3 defense)
  local temp_file
  temp_file=$(mktemp -p "$state_dir" heartbeat.XXXXXX.json) || {
    echo "ERROR: write_heartbeat: mktemp failed in '$state_dir'" >&2
    return 1
  }

  # Setup trap to clean up temp file on error.
  # Use ${temp_file:-} so the trap is safe even when it fires after the function
  # returns (the local var goes out of scope at script exit).
  trap 'rm -f "${temp_file:-}"' EXIT

  # Build heartbeat JSON
  local heartbeat_json
  heartbeat_json=$(jq -n \
    --arg loop_id "$loop_id" \
    --arg session_id "$session_id" \
    --arg iteration "$iteration" \
    --arg last_wake_us "$last_wake_us" \
    --arg generation "$generation" \
    '{loop_id: $loop_id, session_id: $session_id, iteration: $iteration, last_wake_us: $last_wake_us, generation: $generation}')

  # Write to tempfile
  if ! echo "$heartbeat_json" > "$temp_file"; then
    echo "ERROR: write_heartbeat: failed to write temp file" >&2
    return 1
  fi

  # Attempt fsync (best-effort)
  if command -v fsync >/dev/null 2>&1; then
    fsync "$temp_file" || true
  else
    sync || true
  fi

  # Atomic rename to commit
  local heartbeat_path="$state_dir/heartbeat.json"
  if ! mv "$temp_file" "$heartbeat_path"; then
    echo "ERROR: write_heartbeat: atomic rename failed" >&2
    return 1
  fi

  # Disable trap now that we've succeeded
  trap - EXIT

  return 0
}

# read_heartbeat <loop_id> [contract_path]
# Reads the heartbeat.json from a loop's state directory.
# Returns JSON content on success, or {} if file doesn't exist (fail-graceful).
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2 (optional): contract_path (for state_dir derivation if needed)
#
# Output:
#   Heartbeat JSON object, or {} if not found
#
# Exit code:
#   0 always (fail-graceful)
#
# Example:
#   hb=$(read_heartbeat "a1b2c3d4e5f6")
#   iteration=$(echo "$hb" | jq -r '.iteration // 0')
read_heartbeat() {
  local loop_id="$1"
  local contract_path="${2:-}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "{}"
    return 0
  fi

  # Determine state_dir
  local state_dir
  if [ -n "$contract_path" ]; then
    if ! state_dir=$(state_dir_path "$loop_id" "$contract_path"); then
      echo "{}"
      return 0
    fi
  else
    # Try to read from registry
    local registry_lib_dir
    registry_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ -f "$registry_lib_dir/registry-lib.sh" ]; then
      # shellcheck source=/dev/null
      source "$registry_lib_dir/registry-lib.sh" 2>/dev/null || {
        echo "{}"
        return 0
      }

      local entry
      entry=$(read_registry_entry "$loop_id" 2>/dev/null) || {
        echo "{}"
        return 0
      }

      state_dir=$(echo "$entry" | jq -r '.state_dir // empty' 2>/dev/null) || {
        echo "{}"
        return 0
      }
    else
      echo "{}"
      return 0
    fi
  fi

  # Read heartbeat.json
  local heartbeat_path="$state_dir/heartbeat.json"
  if [ ! -f "$heartbeat_path" ]; then
    echo "{}"
    return 0
  fi

  # Parse and return (graceful on JSON error)
  if ! jq . "$heartbeat_path" 2>/dev/null; then
    echo "{}"
    return 0
  fi
}

# set_contract_field <contract_path> <field_name> <field_value>
# Atomically set a single YAML field in a contract's frontmatter.
# If the field exists, replaces its value. If missing, inserts it before the
# closing `---` of the frontmatter. Idempotent and safe to call repeatedly.
#
# The frontmatter MUST start at line 1 with `---` and have a closing `---`.
# field_value is written verbatim; quote it yourself if needed (e.g. ISO timestamp).
#
# Atomicity: writes to mktemp in same dir then mv (defends pitfall #3).
# Best-effort: returns 0 on any I/O failure; never blocks the calling hook.
#
# Arguments:
#   $1: contract_path (must exist and be a regular file)
#   $2: field_name (e.g. "owner_session_id")
#   $3: field_value (verbatim, including quotes if string-typed)
#
# Example:
#   set_contract_field "./LOOP_CONTRACT.md" "owner_session_id" "\"abc-def-123\""
#   set_contract_field "./LOOP_CONTRACT.md" "generation" "3"
set_contract_field() {
  local contract_path="$1"
  local field="$2"
  local value="$3"

  if [ ! -f "$contract_path" ]; then
    return 0
  fi
  if [ -z "$field" ]; then
    return 0
  fi

  local contract_dir
  contract_dir=$(dirname "$contract_path") || return 0

  local tmp
  tmp=$(mktemp "${contract_path}.XXXXXX") 2>/dev/null || return 0

  # awk: walk through frontmatter (between line-1 `---` and the next `---`).
  # If field already present, replace its line. If absent, insert before closing.
  awk -v field="$field" -v value="$value" '
    BEGIN { in_fm = 0; fm_done = 0; replaced = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; print; next }
    in_fm && /^---[[:space:]]*$/ {
      if (!replaced) {
        print field ": " value
      }
      in_fm = 0; fm_done = 1; print; next
    }
    in_fm {
      if ($0 ~ "^" field ":") {
        print field ": " value
        replaced = 1
        next
      }
    }
    { print }
  ' "$contract_path" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 0
  fi

  mv "$tmp" "$contract_path" 2>/dev/null || { rm -f "$tmp"; return 0; }
  return 0
}

# init_contract_frontmatter_v2 <contract_path> <loop_id> <state_dir>
# Populate the immutable birth-record fields of a v2 contract.
# Idempotent: only writes fields that are missing — never overwrites existing
# values (so contracts are not "rebirthed" by a re-run of /autoloop:start).
#
# Fields written if missing:
#   schema_version, loop_id, campaign_slug, created_at_utc, created_at_cwd,
#   created_at_git_branch, created_at_git_commit, state_dir, revision_log_path,
#   expected_cadence (default), status (default "active")
#
# created_in_session is left empty for the session-bind hook to fill on first
# SessionStart (skill subprocess does not see $CLAUDE_SESSION_ID — see
# session-bind.sh header for context).
#
# Arguments:
#   $1: contract_path
#   $2: loop_id
#   $3: state_dir
init_contract_frontmatter_v2() {
  local contract_path="$1"
  local loop_id="$2"
  local state_dir="$3"

  if [ ! -f "$contract_path" ]; then
    return 0
  fi

  # Helper: only set if not already in frontmatter (read up to closing ---)
  _set_if_missing() {
    local field="$1" value="$2"
    if ! awk '
      NR == 1 && /^---/ { in_fm = 1; next }
      in_fm && /^---/ { exit }
      in_fm && $0 ~ "^" field ":" { found = 1; exit }
      END { exit (found ? 0 : 1) }
    ' field="$field" "$contract_path" 2>/dev/null; then
      set_contract_field "$contract_path" "$field" "$value"
    fi
  }

  # schema_version: bump to 2 if missing or 1 (signals v2 fields are populated)
  local existing_schema
  existing_schema=$(awk '
    NR == 1 && /^---/ { in_fm = 1; next }
    in_fm && /^---/ { exit }
    in_fm && /^schema_version:/ { gsub(/^schema_version:[[:space:]]*/, ""); print; exit }
  ' "$contract_path" 2>/dev/null)
  if [ -z "$existing_schema" ] || [ "$existing_schema" = "1" ]; then
    set_contract_field "$contract_path" "schema_version" "2"
  fi

  _set_if_missing "loop_id" "$loop_id"

  # campaign_slug: derive from existing `name:` field if missing
  local name_value
  name_value=$(awk '
    NR == 1 && /^---/ { in_fm = 1; next }
    in_fm && /^---/ { exit }
    in_fm && /^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/^["<]|[">]$/, ""); print; exit }
  ' "$contract_path" 2>/dev/null)
  if [ -n "$name_value" ]; then
    # slugify: lowercase, replace non-alnum with -, trim leading/trailing -
    local slug
    slug=$(echo "$name_value" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
    [ -n "$slug" ] && _set_if_missing "campaign_slug" "\"$slug\""
  fi

  # created_at_utc: stamp with `date -u` if missing
  local created_at
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  [ -n "$created_at" ] && _set_if_missing "created_at_utc" "\"$created_at\""

  # created_at_cwd: realpath of contract's parent directory
  local cwd_abs
  cwd_abs=$(cd "$(dirname "$contract_path")" && pwd -P 2>/dev/null || echo "")
  [ -n "$cwd_abs" ] && _set_if_missing "created_at_cwd" "\"$cwd_abs\""

  # git branch + commit (best-effort)
  local branch commit
  branch=$(git -C "$cwd_abs" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  commit=$(git -C "$cwd_abs" rev-parse HEAD 2>/dev/null || echo "")
  [ -n "$branch" ] && _set_if_missing "created_at_git_branch" "\"$branch\""
  [ -n "$commit" ] && _set_if_missing "created_at_git_commit" "\"$commit\""

  _set_if_missing "state_dir" "\"$state_dir\""
  _set_if_missing "revision_log_path" "\"$state_dir/revision-log\""

  _set_if_missing "expected_cadence" "\"hourly\""
  _set_if_missing "status" "\"active\""

  return 0
}

# Export functions for sourcing by other scripts
export -f now_us
export -f state_dir_path
export -f init_state_dir
export -f write_heartbeat
export -f read_heartbeat
export -f set_contract_field
export -f init_contract_frontmatter_v2
