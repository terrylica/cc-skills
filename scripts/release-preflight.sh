#!/bin/bash
# Release preflight checks for semantic-release
# ADR: 2025-12-23-semantic-release-preflight-guard
set -euo pipefail

# Disable history expansion to avoid issues with ! character
set +H 2>/dev/null || true

# Load mise environment for GH_TOKEN and GH_ACCOUNT
eval "$(mise hook-env -s bash 2>/dev/null)" || true

# Step 1: Clear git cache to ensure accurate file status
git update-index --refresh -q || true

# Step 2: Check for uncommitted changes (modified, untracked, staged, deleted)
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ PREFLIGHT FAILED: Working directory not clean"
  echo "Uncommitted changes:"
  git status --short
  echo ""
  echo "Please commit or stash changes before release."
  exit 1
fi
echo "✓ Working directory clean"

# Step 3: Validate GitHub CLI authentication scopes
SCOPES=$(gh api -i user 2>&1 | grep -i "x-oauth-scopes" | sed 's/.*: //' || true)
if [ -z "$SCOPES" ]; then
  echo "❌ PREFLIGHT FAILED: GitHub CLI not authenticated"
  echo ""
  echo "Resolution: gh auth login"
  exit 1
fi
# Use || pattern to avoid history expansion issues with !
echo "$SCOPES" | grep -q "workflow" || {
  echo "❌ PREFLIGHT FAILED: GitHub token missing workflow scope"
  echo "Current scopes: $SCOPES"
  echo ""
  echo "Resolution: gh auth refresh -s workflow"
  exit 1
}
echo "✓ GitHub CLI scopes valid (workflow present)"

# Step 4: Verify GitHub account matches expected (if GH_ACCOUNT configured)
ACTUAL_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
EXPECTED_USER="${GH_ACCOUNT:-}"
if [ -n "$EXPECTED_USER" ] && [ "$ACTUAL_USER" != "$EXPECTED_USER" ]; then
  echo "❌ PREFLIGHT FAILED: GitHub account mismatch"
  echo "Expected: $EXPECTED_USER (from GH_ACCOUNT env)"
  echo "Actual:   $ACTUAL_USER (from gh api user)"
  echo ""
  echo "Resolution: gh auth switch --user $EXPECTED_USER"
  exit 1
fi
if [ -n "$EXPECTED_USER" ]; then
  echo "✓ GitHub account verified: $ACTUAL_USER"
else
  echo "⚠ GH_ACCOUNT not set, releasing as: $ACTUAL_USER"
fi

echo "✓ All preflight checks passed"
