#!/usr/bin/env bash
#
# PostToolUseError handler for itp-hooks plugin.
# Handles failed Bash commands - UV reminder + silent failure guidance.
#
# IMPORTANT: PostToolUse hooks DON'T run for failed commands (Claude Code behavior).
# This PostToolUseError hook catches those cases.
#
# Input format (different from PostToolUse):
# {
#   "hook_event_name": "PostToolUseError",
#   "tool_name": "Bash",
#   "tool_input": { "command": "pip3 install ..." },
#   "error": {
#     "type": "ProcessError",
#     "exit_code": 1,
#     "stdout": "...",
#     "stderr": "..."
#   }
# }
#

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract fields - note different structure for PostToolUseError
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
EXIT_CODE=$(echo "$INPUT" | jq -r '.error.exit_code // 0')
STDERR=$(echo "$INPUT" | jq -r '.error.stderr // ""')

# Only process Bash errors
if [[ "$TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

REMINDER=""

# === UV REMINDER: Detect pip usage in failed commands ===
COMMAND_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

# Exceptions (same as posttooluse-reminder.sh)
UV_CONTEXT=false
if echo "$COMMAND_LOWER" | grep -qE '^\s*uv\s+(run|exec|pip)'; then
    UV_CONTEXT=true
fi

DOC_CONTEXT=false
if echo "$COMMAND_LOWER" | grep -qE '^\s*#|^\s*echo.*pip|grep.*pip'; then
    DOC_CONTEXT=true
fi

LOCK_OPS=false
if echo "$COMMAND_LOWER" | grep -qE 'pip-compile|pip\s+freeze'; then
    LOCK_OPS=true
fi

# Detect pip usage
if [[ "$UV_CONTEXT" == "false" && "$DOC_CONTEXT" == "false" && "$LOCK_OPS" == "false" ]]; then
    # Pattern allows: start, whitespace, quotes, or && before pip
    if echo "$COMMAND_LOWER" | grep -qE '(^|\s|"|'"'"'|&&\s*)(pip|pip3|python[0-9.]*\s+(-m\s+)?pip)\s+(install|uninstall)'; then
        # Generate suggested replacement
        SUGGESTED=$(echo "$COMMAND" | sed \
            -e 's/pip install/uv add/g' \
            -e 's/pip3 install/uv add/g' \
            -e 's/python -m pip install/uv add/g' \
            -e 's/pip uninstall/uv remove/g' \
            -e 's/pip3 uninstall/uv remove/g')

        # Special case: editable install
        if echo "$COMMAND_LOWER" | grep -qE 'pip\s+install\s+(-e|--editable)'; then
            SUGGESTED="uv pip install -e ."
        fi

        # Special case: requirements file install
        if echo "$COMMAND_LOWER" | grep -qE 'pip\s+install\s+-r'; then
            SUGGESTED="uv sync  # or: uv pip install -r requirements.txt"
        fi

        # Check for externally-managed-environment error (PEP 668)
        PEP668_NOTE=""
        if echo "$STDERR" | grep -qiE 'externally-managed|PEP.668'; then
            PEP668_NOTE="

PEP 668 ERROR DETECTED: System Python is externally managed.
SOLUTION: Use 'uv' which handles virtual environments automatically:
  uv add pyarrow        # Creates/uses .venv automatically
  uv pip install pkg    # Works in any venv context"
        fi

        REMINDER="[UV-REMINDER] pip failed (exit $EXIT_CODE) - use uv instead

FAILED: $COMMAND
PREFERRED: $SUGGESTED

WHY UV: 10-100x faster, automatic venv management, no PEP 668 issues$PEP668_NOTE

QUICK REF: pip install → uv add | pip uninstall → uv remove | pip -e . → uv pip install -e ."
    fi
fi

# === SILENT FAILURE GUIDANCE: Provide context for the error ===
if [[ -z "$REMINDER" && -n "$STDERR" ]]; then
    # Truncate long stderr
    STDERR_TRUNCATED="${STDERR:0:500}"
    if [[ ${#STDERR} -gt 500 ]]; then
        STDERR_TRUNCATED="${STDERR_TRUNCATED}..."
    fi

    REMINDER="[BASH-ERROR] Command failed with exit code $EXIT_CODE

COMMAND: $COMMAND

ERROR OUTPUT:
$STDERR_TRUNCATED

ACTION REQUIRED:
1. ACKNOWLEDGE the failure - do not proceed as if it succeeded
2. DIAGNOSE the root cause from the error message above
3. FIX the underlying issue before retrying
4. If failure is expected, use '|| true' or explicit error handling"
fi

# Output reminder if set
if [[ -n "$REMINDER" ]]; then
    jq -n --arg reason "$REMINDER" '{decision: "block", reason: $reason}'
fi

exit 0
