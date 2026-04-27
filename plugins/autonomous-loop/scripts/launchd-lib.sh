#!/usr/bin/env bash
# launchd-lib.sh — Per-loop launchd plist generation, validation, and load/unload
# Provides: plist_label, generate_plist, load_plist, unload_plist, is_plist_loaded

set -euo pipefail

# plist_label <loop_id>
# Returns the standard launchd label for a given loop_id.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#
# Output:
#   Label string: com.user.claude.loop.<loop_id>
#
# Exit code:
#   0 on success
#   1 if loop_id format invalid
plist_label() {
  local loop_id="$1"

  # Validate loop_id format (exactly 12 hex characters)
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: plist_label: invalid loop_id format '$loop_id' (must be 12 hex chars)" >&2
    return 1
  fi

  echo "com.user.claude.loop.$loop_id"
}

# xmlescape <string>
# Escapes a string for use in XML/plist by replacing special characters.
# Handles &, <, >, ", and single quotes.
#
# Arguments:
#   $1: string to escape
#
# Output:
#   Escaped string to stdout
#
# Exit code:
#   0 always
xmlescape() {
  local str="$1"
  # Replace & first (it's used in other replacements)
  str="${str//&/&amp;}"
  str="${str//</&lt;}"
  str="${str//>/&gt;}"
  str="${str//\"/&quot;}"
  str="${str//\'/&apos;}"
  echo "$str"
}

# generate_plist <loop_id> <state_dir> <waker_script> <interval_seconds>
# Generates a valid launchd plist and writes it to <state_dir>/waker.plist.
# The plist is configured to run the waker_script every <interval_seconds>.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: state_dir (absolute path; must exist or be created)
#   $3: waker_script (absolute path to the script to run)
#   $4: interval_seconds (integer; default 300)
#
# Output:
#   None on success; error messages to stderr on failure
#
# Exit code:
#   0 on success
#   1 if arguments invalid, state_dir inaccessible, or write fails
#
# Side effects:
#   - Creates <state_dir>/waker.plist with valid macOS PLIST XML
#   - Creates <state_dir>/ if it doesn't exist
#
# Example:
#   generate_plist "a1b2c3d4e5f6" "/path/to/state" "/path/to/waker.sh" "300"
generate_plist() {
  local loop_id="$1"
  local state_dir="$2"
  local waker_script="$3"
  local interval_seconds="${4:-300}"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: generate_plist: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # Validate interval_seconds is a number
  if ! [[ "$interval_seconds" =~ ^[0-9]+$ ]]; then
    echo "ERROR: generate_plist: interval_seconds must be a number, got '$interval_seconds'" >&2
    return 1
  fi

  # Ensure state_dir exists
  if ! mkdir -p "$state_dir"; then
    echo "ERROR: generate_plist: failed to create state directory '$state_dir'" >&2
    return 1
  fi

  # Validate waker_script exists
  if [ ! -f "$waker_script" ]; then
    echo "WARNING: generate_plist: waker_script '$waker_script' does not exist yet (Phase 9 will ship it)" >&2
  fi

  local label
  label=$(plist_label "$loop_id") || return 1

  # Escape paths for XML
  local escaped_state_dir
  escaped_state_dir=$(xmlescape "$state_dir")
  local escaped_waker_script
  escaped_waker_script=$(xmlescape "$waker_script")
  local escaped_loop_id
  escaped_loop_id=$(xmlescape "$loop_id")
  local escaped_label
  escaped_label=$(xmlescape "$label")

  # Build plist content
  local plist_content
  plist_content=$(cat <<'PLIST_END'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>LABEL_PLACEHOLDER</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>WAKER_SCRIPT_PLACEHOLDER</string>
		<string>LOOP_ID_PLACEHOLDER</string>
	</array>
	<key>StartInterval</key>
	<integer>INTERVAL_PLACEHOLDER</integer>
	<key>StandardOutPath</key>
	<string>STATE_DIR_PLACEHOLDER/waker.log</string>
	<key>StandardErrorPath</key>
	<string>STATE_DIR_PLACEHOLDER/waker.log</string>
	<key>RunAtLoad</key>
	<false/>
	<key>KeepAlive</key>
	<false/>
</dict>
</plist>
PLIST_END
)

  # Substitute placeholders
  plist_content="${plist_content//LABEL_PLACEHOLDER/$escaped_label}"
  plist_content="${plist_content//WAKER_SCRIPT_PLACEHOLDER/$escaped_waker_script}"
  plist_content="${plist_content//LOOP_ID_PLACEHOLDER/$escaped_loop_id}"
  plist_content="${plist_content//INTERVAL_PLACEHOLDER/$interval_seconds}"
  plist_content="${plist_content//STATE_DIR_PLACEHOLDER/$escaped_state_dir}"

  # Write plist to state_dir
  local plist_file="$state_dir/waker.plist"
  if ! echo "$plist_content" > "$plist_file"; then
    echo "ERROR: generate_plist: failed to write plist to '$plist_file'" >&2
    return 1
  fi

  return 0
}

# load_plist <loop_id> <state_dir>
# Validates and loads a plist via launchctl.
# On macOS: validates with plutil -lint, creates symlink in ~/Library/LaunchAgents/,
#           and bootstraps with launchctl bootstrap (with launchctl load fallback).
# On non-macOS: returns success with a skip message.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: state_dir (path where waker.plist resides)
#
# Output:
#   Status messages to stderr
#
# Exit code:
#   0 on success (or skipped on non-macOS)
#   1 if validation fails, symlink/load fails
#
# Idempotency:
#   Safe to call multiple times; checks if already loaded and skips if so
#
# Example:
#   load_plist "a1b2c3d4e5f6" "/path/to/state"
load_plist() {
  local loop_id="$1"
  local state_dir="$2"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: load_plist: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # On non-macOS, skip with a message
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[SKIP] launchctl unavailable on $(uname -s); plist load skipped (macOS only)" >&2
    return 0
  fi

  local plist_file="$state_dir/waker.plist"
  local label
  label=$(plist_label "$loop_id") || return 1

  # Validate plist with plutil -lint
  if ! plutil -lint "$plist_file" >/dev/null 2>&1; then
    echo "ERROR: load_plist: plist validation failed at '$plist_file'" >&2
    echo "Plist content:" >&2
    cat -n "$plist_file" >&2
    return 1
  fi

  # Check if already loaded (idempotent)
  if launchctl list "$label" >/dev/null 2>&1; then
    echo "INFO: plist already loaded for label '$label'; idempotent no-op" >&2
    return 0
  fi

  # Ensure ~/Library/LaunchAgents/ exists
  local agents_dir="$HOME/Library/LaunchAgents"
  if ! mkdir -p "$agents_dir"; then
    echo "ERROR: load_plist: failed to create directory '$agents_dir'" >&2
    return 1
  fi

  # Create absolute symlink from ~/Library/LaunchAgents/ to plist in state_dir
  local symlink_path="$agents_dir/${label}.plist"
  local abs_plist_file
  abs_plist_file="$(cd "$(dirname "$plist_file")" && pwd)/$(basename "$plist_file")"

  # Remove old symlink if it exists (for idempotency)
  rm -f "$symlink_path" 2>/dev/null || true

  if ! ln -s "$abs_plist_file" "$symlink_path"; then
    echo "ERROR: load_plist: failed to create symlink at '$symlink_path' -> '$abs_plist_file'" >&2
    return 1
  fi

  # Attempt to bootstrap (modern macOS 10.10+)
  if launchctl bootstrap gui/$UID "$symlink_path" 2>/dev/null; then
    echo "INFO: plist loaded via launchctl bootstrap for label '$label'" >&2
    return 0
  fi

  # Fallback to launchctl load (deprecated but still works on older macOS)
  if launchctl load "$symlink_path" 2>/dev/null; then
    echo "INFO: plist loaded via launchctl load (deprecated) for label '$label'" >&2
    return 0
  fi

  echo "ERROR: load_plist: both launchctl bootstrap and launchctl load failed" >&2
  return 1
}

# unload_plist <loop_id> <state_dir>
# Unloads a plist via launchctl and removes associated files.
# On macOS: removes symlink and calls launchctl bootout (with launchctl unload fallback).
# On non-macOS: returns success with a skip message.
#
# Arguments:
#   $1: loop_id (12 hex characters)
#   $2: state_dir (path where waker.plist resides)
#
# Output:
#   Status messages to stderr
#
# Exit code:
#   0 always (idempotent success; no error if plist not loaded)
#   1 only if loop_id format invalid
#
# Idempotency:
#   Safe to call multiple times; no-op if not loaded
#
# Example:
#   unload_plist "a1b2c3d4e5f6" "/path/to/state"
unload_plist() {
  local loop_id="$1"
  local state_dir="$2"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "ERROR: unload_plist: invalid loop_id format '$loop_id'" >&2
    return 1
  fi

  # On non-macOS, skip with a message
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "[SKIP] launchctl unavailable on $(uname -s); plist unload skipped (macOS only)" >&2
    return 0
  fi

  local plist_file="$state_dir/waker.plist"
  local label
  label=$(plist_label "$loop_id") || return 1

  local symlink_path="$HOME/Library/LaunchAgents/${label}.plist"

  # Attempt to bootout (modern macOS 10.10+)
  launchctl bootout "gui/$UID/$label" 2>/dev/null || true

  # Fallback to launchctl unload (deprecated but still works on older macOS)
  if [ -f "$symlink_path" ]; then
    launchctl unload "$symlink_path" 2>/dev/null || true
  fi

  # Remove symlink
  rm -f "$symlink_path" 2>/dev/null || true

  # Remove plist file from state_dir
  rm -f "$plist_file" 2>/dev/null || true

  echo "INFO: plist unloaded for label '$label'" >&2
  return 0
}

# is_plist_loaded <loop_id>
# Checks if a plist is currently loaded in launchctl.
# On macOS: returns "yes" or "no" based on launchctl list query.
# On non-macOS: returns "no" (unavailable).
#
# Arguments:
#   $1: loop_id (12 hex characters)
#
# Output:
#   "yes" or "no" to stdout
#
# Exit code:
#   0 always (fail-graceful)
#
# Example:
#   if [ "$(is_plist_loaded "a1b2c3d4e5f6")" = "yes" ]; then echo "Loaded"; fi
is_plist_loaded() {
  local loop_id="$1"

  # Validate loop_id format
  if ! [[ "$loop_id" =~ ^[0-9a-f]{12}$ ]]; then
    echo "no"
    return 0
  fi

  # On non-macOS, always return "no"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "no"
    return 0
  fi

  local label
  label=$(plist_label "$loop_id") || {
    echo "no"
    return 0
  }

  # Check if label is in launchctl list
  if launchctl list "$label" >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}

# Export functions for sourcing by other scripts
export -f plist_label
export -f xmlescape
export -f generate_plist
export -f load_plist
export -f unload_plist
export -f is_plist_loaded
