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

# Step 3: Validate GitHub token (no API calls - avoids process storms)
# Token is set by mise via .mise.toml reading from ~/.claude/.secrets/gh-token-*
if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "❌ PREFLIGHT FAILED: No GitHub token found"
  echo ""
  echo "Resolution: Run 'eval \"\$(mise env)\"' or check .mise.toml"
  exit 1
fi
TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
# Validate token format
if [[ "$TOKEN" =~ ^(ghp_|github_pat_) ]]; then
  echo "✓ GitHub token present (${#TOKEN} chars, valid format)"
else
  echo "⚠ GitHub token present but unusual format (not ghp_* or github_pat_*)"
fi

# Step 4: Verify target account (from GH_ACCOUNT env, no API call)
EXPECTED_USER="${GH_ACCOUNT:-}"
if [ -n "$EXPECTED_USER" ]; then
  echo "✓ Target account: $EXPECTED_USER (from GH_ACCOUNT env)"
else
  echo "⚠ GH_ACCOUNT not set - releasing with token from mise.toml"
fi

echo "✓ All preflight checks passed"
