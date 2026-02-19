#!/usr/bin/env bash
# ADR: /docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md
# pretooluse-guard.sh - Block manual ASCII art without graph-easy source
#
# Exit codes:
#   0 - Allow (no issues found)
#   2 - Block (hard block that cannot be bypassed)
#
# Uses exit code 2 for hard enforcement (not permissionDecision: deny)
# because there's no legitimate reason to add manual diagrams without source.

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null) || exit 0

# Only check Write/Edit on markdown files
if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
    exit 0
fi

if [[ ! "$FILE_PATH" =~ \.md$ ]]; then
    exit 0
fi

# Box-drawing characters pattern (Unicode box-drawing block U+2500-U+257F)
# Common characters: ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬ ┏ ┓ ┗ ┛
BOX_CHARS='[─│┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬┏┓┗┛┣┫┳┻╋━┃]'

# Check if content contains box-drawing characters
if ! echo "$CONTENT" | grep -qE "$BOX_CHARS"; then
    # No box-drawing chars, allow
    exit 0
fi

# Has box-drawing chars - check for graph-easy source block
if echo "$CONTENT" | grep -q '<summary>graph-easy source</summary>'; then
    # Has source block, allow
    exit 0
fi

# Alternative: check for <details> with graph-easy
if echo "$CONTENT" | grep -q '<details>' && echo "$CONTENT" | grep -q 'graph-easy'; then
    # Has source block, allow
    exit 0
fi

# Block: has ASCII art without source block
cat >&2 << 'EOF'
[PRETOOLUSE-GUARD] Manual ASCII art detected without graph-easy source

Box-drawing characters found in markdown without a source block.

To fix:
1. Use the graph-easy skill to generate diagrams
2. Include <details><summary>graph-easy source</summary>...</details> block

Reference: /docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md
EOF

exit 2
