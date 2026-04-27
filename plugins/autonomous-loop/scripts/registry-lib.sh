#!/usr/bin/env bash
# registry-lib.sh — Loop ID derivation and registry read helpers for autonomous-loop
# Provides deterministic loop ID generation and read-only registry access

set -euo pipefail

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

  # Use jq to find the entry
  local entry
  entry=$(echo "$registry" | jq ".loops[] | select(.loop_id == \"$loop_id\") // empty" 2>/dev/null) || {
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

# Export functions for sourcing by other scripts
export -f derive_loop_id
export -f read_registry
export -f read_registry_entry
