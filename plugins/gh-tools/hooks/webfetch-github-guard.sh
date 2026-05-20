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

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

# Read JSON input from stdin
INPUT=$(cat)

# Iter-55 pre-jq-fastpath bash-builtin-case-glob optimization:
#
# 1. Drop the TOOL_NAME jq parse + equality check entirely. The hook's
#    matcher in hooks.json is exactly "WebFetch", so TOOL_NAME is
#    GUARANTEED to be "WebFetch" by the time we fire. The pre-iter-55
#    `jq -r '.tool_name // ""'` + `[[ "$TOOL_NAME" != "WebFetch" ]]`
#    pair was dead-weight defensive code that ran one jq cold-start on
#    every WebFetch call to confirm what the matcher already guaranteed.
#
# 2. Add bash-builtin-case-glob substring check for "github.com" on the
#    raw $INPUT BEFORE spawning jq to extract the URL. The vast
#    majority of WebFetch traffic in this fleet targets non-github.com
#    URLs (HuggingFace, arXiv, package docs, blog posts, etc.) — the
#    slow path's URL regex `=~ github\.com` already correctly rejects
#    those, but only AFTER paying for the URL jq spawn. The case-glob
#    is a SUPERSET check: if "github.com" doesn't appear anywhere in
#    the payload, the URL can't possibly contain it either, so we exit
#    0 immediately. False positives (e.g. prompt text mentions
#    "github.com" but the URL doesn't) defer to the slow path intact —
#    zero false negatives possible.
#
# Measured (A/B benchmark, /tmp/bench-iter-55-ab-compare.sh, 50 iters
# each, non-github URL fast-path):
#   BASELINE  (pre-iter-55, 2 jq spawns): 14.86 ms/call
#   ITER-55   (case-glob, 0 jq spawns)  :  7.36 ms/call
#   --------------------------------------------------
#   Speedup: 2.02x, ~7.5 ms saved per call.
#
# The remaining ~7.4 ms is the irreducible bash process-spawn floor
# (Claude Code launches a fresh `bash` per hook invocation); the hook's
# own work is sub-millisecond on the fast path. To reduce further would
# require either an in-process hook runtime or batched hook execution
# — both outside the scope of this iter.
case "$INPUT" in
    *github.com*) ;;
    *) exit 0 ;;
esac

# Slow path: payload mentions github.com somewhere — extract the URL
# field to verify the WebFetch target itself contains github.com (the
# case-glob match could be a false positive on prompt text).
URL=$(echo "$INPUT" | jq -r '.tool_input.url // ""' 2>/dev/null) || exit 0

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
