#!/usr/bin/env bash
#
# PostToolUse reminder for itp-hooks plugin.
# Pure bash + jq implementation for minimal startup overhead.
#
# Provides non-blocking reminders for decision traceability:
# 1. graph-easy CLI used → remind about using the skill for reproducibility
# 2. ADR modified → remind to update Design Spec
# 3. Design Spec modified → remind to update ADR
# 4. Implementation code modified → remind about ADR traceability
#

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract fields using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

REMINDER=""

#--- Bash tool: Check for graph-easy CLI usage ---
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    if [[ "$COMMAND" =~ graph-easy ]]; then
        # Track graph-easy usage for PreToolUse exemption
        # ADR: 2025-12-09-itp-hooks-workflow-aware-graph-easy
        STATE_DIR="$HOME/.claude/hooks/state"
        if ! mkdir -p "$STATE_DIR" 2>&1; then
            echo "[itp-hooks] Failed to create state directory: $STATE_DIR" >&2
        fi
        SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

        if [[ -n "$SESSION_ID" ]]; then
            # Write timestamp to flag file for PreToolUse to check
            echo "$(date +%s)" > "$STATE_DIR/${SESSION_ID}.graph-easy-used"
        fi

        REMINDER="[GRAPH-EASY SKILL] You used graph-easy CLI directly. For reproducible diagrams, prefer the graph-easy skill (or adr-graph-easy-architect for ADRs). Skills ensure: proper --as=boxart mode, correct \\\\n escaping, and <details> source block for future edits."
    fi

    # Output reminder if set and exit
    # ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
    # MUST use decision:block format - only "reason" field is visible to Claude
    if [[ -n "$REMINDER" ]]; then
        jq -n --arg reason "$REMINDER" '{decision: "block", reason: $reason}'
    fi
    exit 0
fi

# Only process Write/Edit for file-based reminders
if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Normalize path (remove leading ./ or /)
FILE_PATH="${FILE_PATH#./}"
FILE_PATH="${FILE_PATH#/}"

# Empty path check
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

REMINDER=""

#--- Check if ADR was modified ---
if [[ "$FILE_PATH" =~ ^docs/adr/([0-9]{4}-[0-9]{2}-[0-9]{2}-[a-zA-Z0-9_-]+)\.md$ ]]; then
    SLUG="${BASH_REMATCH[1]}"
    SPEC_PATH="docs/design/${SLUG}/spec.md"
    REMINDER="[ADR-SPEC SYNC] You modified ADR '${SLUG}'. Check if Design Spec needs updating: ${SPEC_PATH}. Rule: ADR and Design Spec must stay synchronized."

#--- Check if Design Spec was modified ---
elif [[ "$FILE_PATH" =~ ^docs/design/([0-9]{4}-[0-9]{2}-[0-9]{2}-[a-zA-Z0-9_-]+)/spec\.md$ ]]; then
    SLUG="${BASH_REMATCH[1]}"
    ADR_PATH="docs/adr/${SLUG}.md"
    REMINDER="[SPEC-ADR SYNC] You modified Design Spec '${SLUG}'. Check if ADR needs updating: ${ADR_PATH}. Rule: ADR and Design Spec must stay synchronized."

#--- Check if implementation code was modified ---
elif [[ "$FILE_PATH" =~ ^(src/|lib/|scripts/|plugins/[^/]+/skills/[^/]+/scripts/) ]] || \
     [[ "$FILE_PATH" =~ \.(py|ts|js|mjs|rs|go)$ ]]; then
    BASENAME=$(basename "$FILE_PATH")

    #--- Ruff linting for Python files ---
    # ADR: 2025-12-11-ruff-posttooluse-linting
    if [[ "$FILE_PATH" =~ \.py$ ]] && command -v ruff &>/dev/null; then
        # Comprehensive rule set: error handling + idiomatic Python
        # BLE: blind except, S110: try-except-pass, E722: bare except
        # F: pyflakes, UP: pyupgrade, SIM: simplify, B: bugbear, I: isort, RUF: ruff-specific
        # Ruff outputs "All checks passed!" on success - filter it out
        RUFF_OUTPUT=$(ruff check "$FILE_PATH" \
            --select BLE,S110,E722,F,UP,SIM,B,I,RUF \
            --ignore D,ANN \
            --no-fix \
            --output-format=concise \
            2>/dev/null | grep -v "All checks passed" | head -20) || true

        # Only report issues if ruff found actual problems (non-empty after filtering)
        if [[ -n "$RUFF_OUTPUT" ]]; then
            REMINDER="[RUFF] Issues detected in ${BASENAME}:\\n${RUFF_OUTPUT}\\nRun 'ruff check ${FILE_PATH} --fix' to auto-fix safe issues."
        fi
        # Skip ADR reminder if ruff passed - check for existing ADR reference below
    fi

    # Only show ADR traceability reminder if no ruff issues AND no existing ADR reference
    # Check if file already contains ADR reference to avoid false positives
    if [[ -z "$REMINDER" && -f "$FILE_PATH" ]]; then
        # Look for common ADR reference patterns in first 50 lines
        # Patterns: "ADR:", "docs/adr/", "adr/2", "/adr/"
        if ! head -50 "$FILE_PATH" 2>/dev/null | grep -qE '(ADR:|docs/adr/|/adr/[0-9])'; then
            REMINDER="[CODE-ADR TRACEABILITY] You modified implementation file: ${BASENAME}. Consider: Does this change relate to an existing ADR? If implementing a decision from docs/adr/, add ADR reference comment."
        fi
    fi
fi

# Output reminder if set
# ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
# MUST use decision:block format - only "reason" field is visible to Claude
if [[ -n "$REMINDER" ]]; then
    jq -n --arg reason "$REMINDER" '{decision: "block", reason: $reason}'
fi

exit 0
