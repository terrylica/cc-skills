#!/usr/bin/env bash
#
# Unified PostToolUse reminder for cc-skills plugin.
# Pure bash + jq implementation for minimal startup overhead.
#
# Provides non-blocking reminders for decision traceability:
# 1. ADR modified → remind to update Design Spec
# 2. Design Spec modified → remind to update ADR
# 3. Implementation code modified → remind about ADR traceability
#

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract fields using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only process Write/Edit
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
    REMINDER="[CODE-ADR TRACEABILITY] You modified implementation file: ${BASENAME}. Consider: Does this change relate to an existing ADR? If implementing a decision from docs/adr/, add ADR reference comment."
fi

# Output reminder if set
if [[ -n "$REMINDER" ]]; then
    # Escape for JSON
    REMINDER_ESCAPED=$(echo "$REMINDER" | sed 's/"/\\"/g' | tr '\n' ' ')
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"${REMINDER_ESCAPED}\"}}"
fi

exit 0
