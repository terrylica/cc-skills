#!/usr/bin/env bash
# PROCESS-STORM-OK
# FILE-SIZE-OK — cohesive hook install/uninstall surface; splitting would create
# artificial separation between PostToolUse and SessionStart installers that
# share lock primitive and atomic-rename plumbing.
#
# hook-install-lib.sh — Idempotent, concurrency-safe hook install/uninstall for settings.json
# Provides install_hook (now installs BOTH PostToolUse heartbeat-tick.sh AND
# SessionStart session-bind.sh as of v4.10.0 Phase 36), uninstall_hook, and
# is_hook_installed helpers. Uses flock/lockf on fd 7 (~/.claude/.settings.lock)
# for safe concurrent access.

set -euo pipefail

# is_hook_installed [settings_path]
# Checks if our heartbeat hook is already installed in settings.json.
#
# Arguments:
#   $1 (optional): Override path to settings.json (for testing); defaults to ~/.claude/settings.json
#
# Output:
#   "yes" or "no" to stdout
#
# Exit code:
#   0 always (fail-graceful)
#
# Example:
#   if [ "$(is_hook_installed)" = "yes" ]; then echo "Hook installed"; fi
is_hook_installed() {
  local settings_path="${1:-$HOME/.claude/settings.json}"

  # If settings file doesn't exist, hook is not installed
  if [ ! -f "$settings_path" ]; then
    echo "no"
    return 0
  fi

  # Parse settings.json and check if our hook path is present
  # Our hook is identified by command path ending with /plugins/autonomous-loop/hooks/heartbeat-tick.sh
  local installed
  installed=$(jq -r '
    .hooks.PostToolUse[]?.hooks[]? |
    select(.type == "command" and (.command | endswith("/plugins/autonomous-loop/hooks/heartbeat-tick.sh"))) |
    .command
  ' "$settings_path" 2>/dev/null || echo "") || true

  if [ -n "$installed" ]; then
    echo "yes"
  else
    echo "no"
  fi
}

# hook_path_default
# Resolves the default path to our hook from this script's location.
# Returns the absolute path to heartbeat-tick.sh.
#
# Output:
#   Absolute path to heartbeat-tick.sh
#
# Exit code:
#   0 on success
#   1 if script directory cannot be determined
hook_path_default() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "ERROR: hook_path_default: cannot determine script directory" >&2
    return 1
  }

  local plugin_dir
  plugin_dir="$(dirname "$script_dir")" || return 1

  local hook_path
  hook_path="$plugin_dir/hooks/heartbeat-tick.sh"

  if [ ! -f "$hook_path" ]; then
    echo "ERROR: hook_path_default: heartbeat hook not found at $hook_path" >&2
    return 1
  fi

  echo "$hook_path"
}

# hook_path_default_session_bind
# Returns the absolute path to session-bind.sh (SessionStart hook).
hook_path_default_session_bind() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "ERROR: hook_path_default_session_bind: cannot determine script directory" >&2
    return 1
  }

  local plugin_dir
  plugin_dir="$(dirname "$script_dir")" || return 1

  local hook_path
  hook_path="$plugin_dir/hooks/session-bind.sh"

  if [ ! -f "$hook_path" ]; then
    echo "ERROR: hook_path_default_session_bind: session-bind hook not found at $hook_path" >&2
    return 1
  fi

  echo "$hook_path"
}

# is_session_bind_installed [settings_path]
# Checks if our session-bind hook is registered in settings.json under SessionStart.
is_session_bind_installed() {
  local settings_path="${1:-$HOME/.claude/settings.json}"

  if [ ! -f "$settings_path" ]; then
    echo "no"
    return 0
  fi

  local installed
  installed=$(jq -r '
    .hooks.SessionStart[]?.hooks[]? |
    select(.type == "command" and (.command | endswith("/plugins/autonomous-loop/hooks/session-bind.sh"))) |
    .command
  ' "$settings_path" 2>/dev/null || echo "") || true

  if [ -n "$installed" ]; then
    echo "yes"
  else
    echo "no"
  fi
}

# _with_settings_lock <fn> [args...]
# Internal: wraps settings.json mutations in file-locking serialization.
# Acquires exclusive lock on ~/.claude/.settings.lock (using lockf on macOS, flock on Linux),
# calls fn with args, releases lock.
#
# Arguments:
#   $1: Function name to invoke
#   ${@:2}: Args to pass to fn
#
# Exit code:
#   0 on success
#   1 if lock contention, temp write error, or fn exit code != 0
#
# Example:
#   _with_settings_lock install_hook_impl "$settings_path" "$hook_path"
_with_settings_lock() {
  local fn="$1"
  shift

  # Ensure ~/.claude/ directory exists
  local claude_dir="$HOME/.claude"
  if [ ! -d "$claude_dir" ]; then
    mkdir -p "$claude_dir" || {
      echo "ERROR: _with_settings_lock: failed to create $claude_dir" >&2
      return 1
    }
  fi

  local lock_file="$claude_dir/.settings.lock"

  # Clean up lock file on exit
  trap 'exec 7>&- 2>/dev/null || true' EXIT

  # Create lock file if it doesn't exist
  touch "$lock_file" || {
    echo "ERROR: _with_settings_lock: failed to create lock file" >&2
    return 1
  }

  # Acquire exclusive lock using appropriate tool
  # macOS: lockf (POSIX); Linux: flock (GNU)
  if command -v flock >/dev/null 2>&1; then
    # Linux: flock with fd 7
    exec 7>"$lock_file" || {
      echo "ERROR: _with_settings_lock: failed to open fd 7" >&2
      return 1
    }
    if ! flock --wait 5 -x 7; then
      echo "ERROR: _with_settings_lock: lock contention; another writer is active" >&2
      exec 7>&-
      return 1
    fi
  elif command -v lockf >/dev/null 2>&1; then
    # macOS: lockf with retry loop (non-blocking mode with polling)
    exec 7>"$lock_file" || {
      echo "ERROR: _with_settings_lock: failed to open fd 7" >&2
      return 1
    }
    local retries=50  # ~5 seconds with 100ms sleeps
    while ! lockf -t 0 "$lock_file" true 2>/dev/null; do
      retries=$((retries - 1))
      if [ $retries -le 0 ]; then
        echo "ERROR: _with_settings_lock: lock contention; another writer is active" >&2
        exec 7>&-
        return 1
      fi
      sleep 0.1
    done
  else
    echo "ERROR: _with_settings_lock: neither flock nor lockf found; cannot acquire lock" >&2
    return 1
  fi

  # Call fn with args
  if ! "$fn" "$@" 2>&1; then
    return 1
  fi

  # Lock is released by trap on EXIT
  return 0
}

# install_hook_impl <settings_path> <hook_path>
# Implementation function: installs hook into settings.json.
# Creates or updates settings.json; backs up original on first install.
#
# Arguments:
#   $1: Path to settings.json
#   $2: Absolute path to heartbeat-tick.sh
#
# Exit code:
#   0 on success (installed or already present)
#   1 on error
install_hook_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1

  # Check if already installed (idempotent)
  if [ -f "$settings_path" ]; then
    # Check if our hook is already there
    local installed
    installed=$(jq -r '
      .hooks.PostToolUse[]?.hooks[]? |
      select(.type == "command" and (.command == "'"$hook_path"'")) |
      .command
    ' "$settings_path" 2>/dev/null || echo "") || true

    if [ -n "$installed" ]; then
      echo "Hook already installed at $hook_path; no-op" >&2
      return 0
    fi

    # Validate JSON before modifying
    if ! jq . "$settings_path" >/dev/null 2>&1; then
      echo "ERROR: install_hook_impl: settings.json at $settings_path is malformed JSON" >&2
      return 1
    fi

    # Backup original (first install detection)
    local backup_file
    backup_file="$claude_dir/.settings.backup.$(date +%s).json"
    cp "$settings_path" "$backup_file" || {
      echo "ERROR: install_hook_impl: failed to create backup at $backup_file" >&2
      return 1
    }
  fi

  # Create or update settings.json
  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || {
    echo "ERROR: install_hook_impl: mktemp failed" >&2
    return 1
  }

  # Read existing or create new
  local new_settings
  if [ -f "$settings_path" ]; then
    # Add hook to existing PostToolUse array
    new_settings=$(jq '
      .hooks.PostToolUse //= [
        { "matcher": "*", "hooks": [] }
      ] |
      (
        if (.hooks.PostToolUse | length) == 0 then
          .hooks.PostToolUse += [{ "matcher": "*", "hooks": [] }]
        else
          .
        end
      ) |
      .hooks.PostToolUse[0].hooks += [
        {
          "type": "command",
          "command": "'"$hook_path"'"
        }
      ]
    ' "$settings_path" 2>/dev/null) || {
      echo "ERROR: install_hook_impl: jq update failed" >&2
      rm -f "$temp_file"
      return 1
    }
  else
    # Create new settings.json with just our hook
    new_settings=$(jq -n '
      {
        "hooks": {
          "PostToolUse": [
            {
              "matcher": "*",
              "hooks": [
                {
                  "type": "command",
                  "command": "'"$hook_path"'"
                }
              ]
            }
          ]
        }
      }
    ') || {
      echo "ERROR: install_hook_impl: jq creation failed" >&2
      rm -f "$temp_file"
      return 1
    }
  fi

  # Validate JSON before write
  if ! echo "$new_settings" | jq . >/dev/null 2>&1; then
    echo "ERROR: install_hook_impl: generated invalid JSON" >&2
    rm -f "$temp_file"
    return 1
  fi

  # Write to temp file
  if ! echo "$new_settings" > "$temp_file"; then
    echo "ERROR: install_hook_impl: failed to write temp file" >&2
    rm -f "$temp_file"
    return 1
  fi

  # Sync to disk
  if command -v fsync >/dev/null 2>&1; then
    fsync "$temp_file" || true
  else
    sync || true
  fi

  # Atomic rename
  if ! mv "$temp_file" "$settings_path"; then
    echo "ERROR: install_hook_impl: atomic rename failed" >&2
    rm -f "$temp_file"
    return 1
  fi

  echo "Hook installed successfully at $settings_path" >&2
  return 0
}

# install_hook [settings_path] [hook_path]
# Public: idempotent install of heartbeat hook into settings.json.
# On first install, backs up original to .settings.backup.<ts>.json.
# Subsequent installs are no-ops.
#
# Arguments:
#   $1 (optional): Override path to settings.json (for testing); defaults to ~/.claude/settings.json
#   $2 (optional): Override path to heartbeat-tick.sh (for testing); defaults to plugin's hook dir
#
# Exit code:
#   0 on success (installed or already present)
#   1 on error
#
# Example:
#   install_hook  # Uses defaults
#   install_hook "/tmp/settings.json" "/path/to/heartbeat-tick.sh"
install_hook() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"

  # Resolve default hook path if not provided
  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default) || return 1
  fi

  # Validate hook_path exists
  if [ ! -f "$hook_path" ]; then
    echo "ERROR: install_hook: heartbeat hook not found at $hook_path" >&2
    return 1
  fi

  # Convert paths to absolute
  settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")

  # Call with lock
  _with_settings_lock install_hook_impl "$settings_path" "$hook_path" || return 1
}

# uninstall_hook_impl <settings_path> <hook_path>
# Implementation function: removes hook from settings.json.
# Idempotent: no error if hook not present.
#
# Arguments:
#   $1: Path to settings.json
#   $2: Absolute path to heartbeat-tick.sh
#
# Exit code:
#   0 always (idempotent)
uninstall_hook_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1

  # If settings file doesn't exist, nothing to uninstall
  if [ ! -f "$settings_path" ]; then
    echo "Settings.json not found; nothing to uninstall" >&2
    return 0
  fi

  # Validate JSON before modifying
  if ! jq . "$settings_path" >/dev/null 2>&1; then
    echo "ERROR: uninstall_hook_impl: settings.json at $settings_path is malformed JSON" >&2
    return 1
  fi

  # Remove our hook from PostToolUse (idempotent: no error if not found)
  local new_settings
  new_settings=$(jq '
    .hooks.PostToolUse[]?.hooks |= map(
      select(
        (.type != "command" or .command != "'"$hook_path"'")
      )
    )
  ' "$settings_path" 2>/dev/null) || {
    echo "ERROR: uninstall_hook_impl: jq update failed" >&2
    return 1
  }

  # Validate JSON before write
  if ! echo "$new_settings" | jq . >/dev/null 2>&1; then
    echo "ERROR: uninstall_hook_impl: generated invalid JSON" >&2
    return 1
  fi

  # Create temp file
  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || {
    echo "ERROR: uninstall_hook_impl: mktemp failed" >&2
    return 1
  }

  # Write to temp file
  if ! echo "$new_settings" > "$temp_file"; then
    echo "ERROR: uninstall_hook_impl: failed to write temp file" >&2
    rm -f "$temp_file"
    return 1
  fi

  # Sync to disk
  if command -v fsync >/dev/null 2>&1; then
    fsync "$temp_file" || true
  else
    sync || true
  fi

  # Atomic rename
  if ! mv "$temp_file" "$settings_path"; then
    echo "ERROR: uninstall_hook_impl: atomic rename failed" >&2
    rm -f "$temp_file"
    return 1
  fi

  echo "Hook uninstalled successfully from $settings_path" >&2
  return 0
}

# uninstall_hook [settings_path] [hook_path]
# Public: idempotent removal of heartbeat hook from settings.json.
# Leaves other PostToolUse entries intact.
#
# Arguments:
#   $1 (optional): Override path to settings.json (for testing); defaults to ~/.claude/settings.json
#   $2 (optional): Override path to heartbeat-tick.sh (for testing); defaults to plugin's hook dir
#
# Exit code:
#   0 always (idempotent; no error if hook not present)
#   1 on error
#
# Example:
#   uninstall_hook  # Uses defaults
#   uninstall_hook "/tmp/settings.json" "/path/to/heartbeat-tick.sh"
uninstall_hook() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"

  # Resolve default hook path if not provided
  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default) || return 1
  fi

  # Convert paths to absolute
  if [ -f "$settings_path" ]; then
    settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  else
    # Path doesn't exist yet; still convert to absolute for consistency
    settings_path=$(cd "$(dirname "$(pwd)/$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  fi

  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")

  # Call with lock
  _with_settings_lock uninstall_hook_impl "$settings_path" "$hook_path" || return 1
}

# PROCESS-STORM-OK
# ===== SessionStart hook (session-bind.sh) install/uninstall =====
# v4.10.0 Phase 36 (BIND-01): mirrors PostToolUse installer but writes to
# .hooks.SessionStart and points at session-bind.sh. Each function is a plain
# bash function definition; no subshell or background expansion involved.

install_session_bind_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1

  if [ -f "$settings_path" ]; then
    local installed
    installed=$(jq -r '
      .hooks.SessionStart[]?.hooks[]? |
      select(.type == "command" and (.command == "'"$hook_path"'")) |
      .command
    ' "$settings_path" 2>/dev/null || echo "") || true

    if [ -n "$installed" ]; then
      echo "SessionStart hook already installed at $hook_path; no-op" >&2
      return 0
    fi

    if ! jq . "$settings_path" >/dev/null 2>&1; then
      echo "ERROR: install_session_bind_impl: settings.json malformed" >&2
      return 1
    fi
  fi

  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || {
    echo "ERROR: install_session_bind_impl: mktemp failed" >&2
    return 1
  }

  local new_settings
  if [ -f "$settings_path" ]; then
    new_settings=$(jq '
      .hooks.SessionStart //= [
        { "matcher": "*", "hooks": [] }
      ] |
      (
        if (.hooks.SessionStart | length) == 0 then
          .hooks.SessionStart += [{ "matcher": "*", "hooks": [] }]
        else
          .
        end
      ) |
      .hooks.SessionStart[0].hooks += [
        {
          "type": "command",
          "command": "'"$hook_path"'"
        }
      ]
    ' "$settings_path" 2>/dev/null) || {
      echo "ERROR: install_session_bind_impl: jq update failed" >&2
      rm -f "$temp_file"
      return 1
    }
  else
    new_settings=$(jq -n '
      {
        "hooks": {
          "SessionStart": [
            {
              "matcher": "*",
              "hooks": [
                {
                  "type": "command",
                  "command": "'"$hook_path"'"
                }
              ]
            }
          ]
        }
      }
    ') || {
      echo "ERROR: install_session_bind_impl: jq creation failed" >&2
      rm -f "$temp_file"
      return 1
    }
  fi

  if ! echo "$new_settings" | jq . >/dev/null 2>&1; then
    echo "ERROR: install_session_bind_impl: generated invalid JSON" >&2
    rm -f "$temp_file"
    return 1
  fi

  if ! echo "$new_settings" >"$temp_file"; then
    echo "ERROR: install_session_bind_impl: write failed" >&2
    rm -f "$temp_file"
    return 1
  fi

  sync || true

  if ! mv "$temp_file" "$settings_path"; then
    echo "ERROR: install_session_bind_impl: atomic rename failed" >&2
    rm -f "$temp_file"
    return 1
  fi

  echo "SessionStart hook installed successfully at $settings_path" >&2
  return 0
}

uninstall_session_bind_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1

  if [ ! -f "$settings_path" ]; then
    return 0
  fi

  if ! jq . "$settings_path" >/dev/null 2>&1; then
    echo "ERROR: uninstall_session_bind_impl: settings.json malformed" >&2
    return 1
  fi

  local new_settings
  new_settings=$(jq '
    .hooks.SessionStart[]?.hooks |= map(
      select(
        (.type != "command" or .command != "'"$hook_path"'")
      )
    )
  ' "$settings_path" 2>/dev/null) || {
    echo "ERROR: uninstall_session_bind_impl: jq update failed" >&2
    return 1
  }

  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || return 1

  if ! echo "$new_settings" >"$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  sync || true
  mv "$temp_file" "$settings_path" || {
    rm -f "$temp_file"
    return 1
  }
  return 0
}

install_session_bind() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"

  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default_session_bind) || return 1
  fi

  if [ ! -f "$hook_path" ]; then
    echo "ERROR: install_session_bind: session-bind hook not found at $hook_path" >&2
    return 1
  fi

  settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")

  _with_settings_lock install_session_bind_impl "$settings_path" "$hook_path" || return 1
}

uninstall_session_bind() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"

  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default_session_bind) || return 1
  fi

  if [ -f "$settings_path" ]; then
    settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  fi
  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")

  _with_settings_lock uninstall_session_bind_impl "$settings_path" "$hook_path" || return 1
}

# PROCESS-STORM-OK
# ===== PreToolUse pacing-veto hook (v16.6.1: anti-pacing enforcement) =====

hook_path_default_pacing_veto() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  local plugin_dir
  plugin_dir="$(dirname "$script_dir")" || return 1
  local hook_path="$plugin_dir/hooks/pacing-veto.sh"
  if [ ! -f "$hook_path" ]; then
    echo "ERROR: hook_path_default_pacing_veto: pacing-veto hook not found at $hook_path" >&2
    return 1
  fi
  echo "$hook_path"
}

is_pacing_veto_installed() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  if [ ! -f "$settings_path" ]; then
    echo "no"
    return 0
  fi
  local installed
  installed=$(jq -r '
    .hooks.PreToolUse[]?.hooks[]? |
    select(.type == "command" and (.command | endswith("/plugins/autonomous-loop/hooks/pacing-veto.sh"))) |
    .command
  ' "$settings_path" 2>/dev/null || echo "") || true
  if [ -n "$installed" ]; then echo "yes"; else echo "no"; fi
}

install_pacing_veto_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1

  if [ -f "$settings_path" ]; then
    local installed
    installed=$(jq -r '
      .hooks.PreToolUse[]?.hooks[]? |
      select(.type == "command" and (.command == "'"$hook_path"'")) |
      .command
    ' "$settings_path" 2>/dev/null || echo "") || true
    if [ -n "$installed" ]; then
      echo "PreToolUse pacing-veto already installed at $hook_path; no-op" >&2
      return 0
    fi
    if ! jq . "$settings_path" >/dev/null 2>&1; then
      echo "ERROR: install_pacing_veto_impl: settings.json malformed" >&2
      return 1
    fi
  fi

  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || return 1

  # Matcher restricted to ScheduleWakeup tool — cheaper than running on every tool call.
  local new_settings
  if [ -f "$settings_path" ]; then
    new_settings=$(jq '
      .hooks.PreToolUse //= [] |
      .hooks.PreToolUse += [{
        "matcher": "ScheduleWakeup",
        "hooks": [
          { "type": "command", "command": "'"$hook_path"'" }
        ]
      }]
    ' "$settings_path" 2>/dev/null) || {
      rm -f "$temp_file"
      return 1
    }
  else
    new_settings=$(jq -n '
      {
        "hooks": {
          "PreToolUse": [
            {
              "matcher": "ScheduleWakeup",
              "hooks": [
                { "type": "command", "command": "'"$hook_path"'" }
              ]
            }
          ]
        }
      }
    ') || { rm -f "$temp_file"; return 1; }
  fi

  if ! echo "$new_settings" | jq . >/dev/null 2>&1; then
    rm -f "$temp_file"
    return 1
  fi
  if ! echo "$new_settings" >"$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  sync || true
  if ! mv "$temp_file" "$settings_path"; then
    rm -f "$temp_file"
    return 1
  fi
  echo "PreToolUse pacing-veto hook installed successfully at $settings_path" >&2
  return 0
}

uninstall_pacing_veto_impl() {
  local settings_path="$1"
  local hook_path="$2"
  local claude_dir
  claude_dir=$(dirname "$settings_path") || return 1
  [ ! -f "$settings_path" ] && return 0
  if ! jq . "$settings_path" >/dev/null 2>&1; then
    return 1
  fi
  local new_settings
  new_settings=$(jq '
    .hooks.PreToolUse[]?.hooks |= map(
      select((.type != "command" or .command != "'"$hook_path"'"))
    ) |
    .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(select((.hooks // []) | length > 0)))
  ' "$settings_path" 2>/dev/null) || return 1
  local temp_file
  temp_file=$(mktemp -p "$claude_dir" settings.XXXXXX.json) || return 1
  if ! echo "$new_settings" >"$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  sync || true
  mv "$temp_file" "$settings_path" || { rm -f "$temp_file"; return 1; }
  return 0
}

install_pacing_veto() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"
  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default_pacing_veto) || return 1
  fi
  if [ ! -f "$hook_path" ]; then
    return 1
  fi
  settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")
  _with_settings_lock install_pacing_veto_impl "$settings_path" "$hook_path" || return 1
}

uninstall_pacing_veto() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  local hook_path="${2:-}"
  if [ -z "$hook_path" ]; then
    hook_path=$(hook_path_default_pacing_veto) || return 1
  fi
  if [ -f "$settings_path" ]; then
    settings_path=$(cd "$(dirname "$settings_path")" && echo "$PWD/$(basename "$settings_path")")
  fi
  hook_path=$(cd "$(dirname "$hook_path")" && echo "$PWD/$(basename "$hook_path")")
  _with_settings_lock uninstall_pacing_veto_impl "$settings_path" "$hook_path" || return 1
}

# install_all_hooks: composite — installs heartbeat-tick (PostToolUse),
# session-bind (SessionStart), and pacing-veto (PreToolUse). Idempotent.
install_all_hooks() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  install_hook "$settings_path" || return 1
  install_session_bind "$settings_path" || return 1
  install_pacing_veto "$settings_path" || return 1
  return 0
}

# uninstall_all_hooks: composite — removes all three autonomous-loop hooks.
uninstall_all_hooks() {
  local settings_path="${1:-$HOME/.claude/settings.json}"
  uninstall_hook "$settings_path" || true
  uninstall_session_bind "$settings_path" || true
  uninstall_pacing_veto "$settings_path" || true
  return 0
}

export -f hook_path_default_pacing_veto
export -f is_pacing_veto_installed
export -f install_pacing_veto_impl
export -f install_pacing_veto
export -f uninstall_pacing_veto_impl
export -f uninstall_pacing_veto

# Export functions for sourcing by other scripts
export -f is_hook_installed
export -f is_session_bind_installed
export -f hook_path_default
export -f hook_path_default_session_bind
export -f _with_settings_lock
export -f install_hook_impl
export -f install_hook
export -f uninstall_hook_impl
export -f uninstall_hook
export -f install_session_bind_impl
export -f install_session_bind
export -f uninstall_session_bind_impl
export -f uninstall_session_bind
export -f install_all_hooks
export -f uninstall_all_hooks
