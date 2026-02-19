#!/usr/bin/env bash
# ADR: /docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md
# webfetch-github-guard.sh - Soft block WebFetch for github.com URLs
#
# Exit codes:
#   0 - Allow (non-GitHub URL or user override)
#
# Uses permissionDecision: deny for soft block (user can override)
# because gh CLI provides superior GitHub data access.

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Parse tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
URL=$(echo "$INPUT" | jq -r '.tool_input.url // ""' 2>/dev/null) || exit 0

# Only intercept WebFetch tool
if [[ "$TOOL_NAME" != "WebFetch" ]]; then
    exit 0
fi

# Check if URL contains github.com
if [[ ! "$URL" =~ github\.com ]]; then
    exit 0
fi

# Detect specific GitHub resource types for targeted suggestions
GH_SUGGESTION=""
if [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    NUM="${BASH_REMATCH[3]}"
    GH_SUGGESTION="gh issue view $NUM --repo $OWNER/$REPO"
elif [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    NUM="${BASH_REMATCH[3]}"
    GH_SUGGESTION="gh pr view $NUM --repo $OWNER/$REPO"
elif [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/issues$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    GH_SUGGESTION="gh issue list --repo $OWNER/$REPO"
elif [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/pulls$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    GH_SUGGESTION="gh pr list --repo $OWNER/$REPO"
elif [[ "$URL" =~ github\.com/([^/]+)/([^/]+)/?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    GH_SUGGESTION="gh repo view $OWNER/$REPO"
else
    # Generic API suggestion for other GitHub URLs
    GH_SUGGESTION="gh api <endpoint> (see: gh api --help)"
fi

# Build reason message
REASON="[gh-tools] WebFetch to github.com detected

URL: $URL

Use gh CLI instead for better data access:
  $GH_SUGGESTION

Why gh CLI is preferred:
- Authenticated requests (no rate limits)
- Full JSON metadata (not HTML scraping)
- Pagination handled automatically
- Comments, labels, assignees included

Reference: /docs/adr/2026-01-03-gh-tools-webfetch-enforcement.md"

# Output soft block with deny permission
jq -n --arg reason "$REASON" '{
    permissionDecision: "deny",
    reason: $reason
}'

exit 0
