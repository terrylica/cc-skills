#!/usr/bin/env bash
# Create alpha-forge worktree with ADR-style naming
# ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md
#
# Usage: create-worktree.sh <branch-name>
# Example: create-worktree.sh feat/2025-12-14-sharpe-statistical-validation

set -euo pipefail

BRANCH="${1:-}"
AF_ROOT="$HOME/eon/alpha-forge"
WORKTREE_BASE="$HOME/eon"

# Validate input
if [[ -z "$BRANCH" ]]; then
    echo "Usage: create-worktree.sh <branch-name>" >&2
    echo "Example: create-worktree.sh feat/2025-12-14-sharpe-statistical-validation" >&2
    exit 1
fi

# Validate alpha-forge repo exists
if [[ ! -d "$AF_ROOT/.git" ]]; then
    echo "Error: alpha-forge repo not found at $AF_ROOT" >&2
    exit 1
fi

cd "$AF_ROOT"

# Validate branch exists (local or remote)
if ! git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null && \
   ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null; then
    echo "Error: Branch '$BRANCH' not found locally or on origin" >&2
    echo "" >&2
    echo "Available local branches:" >&2
    git branch --format='  %(refname:short)' >&2
    exit 1
fi

# Extract date and slug from branch name
# Pattern: (feat|fix|refactor|chore)/YYYY-MM-DD-slug
# Or: (feat|fix|refactor|chore)/slug (use today's date)
if [[ "$BRANCH" =~ ^(feat|fix|refactor|chore)/([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
    DATE="${BASH_REMATCH[2]}"
    SLUG="${BASH_REMATCH[3]}"
elif [[ "$BRANCH" =~ ^(feat|fix|refactor|chore)/(.+)$ ]]; then
    DATE=$(date +%Y-%m-%d)
    SLUG="${BASH_REMATCH[2]}"
else
    # Fallback: use branch name as slug
    DATE=$(date +%Y-%m-%d)
    SLUG="${BRANCH##*/}"
fi

WORKTREE_NAME="alpha-forge.worktree-${DATE}-${SLUG}"
WORKTREE_PATH="${WORKTREE_BASE}/${WORKTREE_NAME}"

# Check if worktree already exists
if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree already exists at $WORKTREE_PATH" >&2
    exit 1
fi

# Check if branch already has a worktree
EXISTING_WT=$(git worktree list | grep "\[$BRANCH\]" | awk '{print $1}' || true)
if [[ -n "$EXISTING_WT" ]]; then
    echo "Error: Branch '$BRANCH' already has a worktree at $EXISTING_WT" >&2
    exit 1
fi

# Create worktree
echo "Creating worktree..."
echo "  Path: $WORKTREE_PATH"
echo "  Branch: $BRANCH"

git worktree add "$WORKTREE_PATH" "$BRANCH"

# Generate tab name
ACRONYM=$(echo "$SLUG" | tr '-' '\n' | cut -c1 | tr -d '\n' | tr '[:upper:]' '[:lower:]')
TAB_NAME="AF-${ACRONYM}"

echo ""
echo "✓ Worktree created successfully"
echo ""
echo "  Path:   $WORKTREE_PATH"
echo "  Branch: $BRANCH"
echo "  Tab:    $TAB_NAME"
echo ""
echo "  Note: Restart iTerm2 to see the new tab in your layout."
