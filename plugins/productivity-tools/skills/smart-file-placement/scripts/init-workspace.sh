#!/usr/bin/env bash
# Smart File Placement - Workspace Initialization
# Called automatically when skill detects missing directory structure
# Can also be used as Claude Code launch wrapper

set -euo pipefail

# Detect workplace and scratch directory
if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
  workplace=$(basename "$toplevel")
  scratch="$toplevel/scratch"
  in_git_repo=true
else
  workplace=$(basename "$PWD")
  scratch="$HOME/$workplace/scratch"
  in_git_repo=false
fi

skills="$HOME/.claude/skills"

# Create directory structure
echo "Initializing workspace: $workplace"
mkdir -p "/var/tmp/$workplace" "$scratch" "$skills"

# Update .gitignore if in git repo - atomic write
# ADR: /docs/adr/2025-12-07-idempotency-backup-traceability.md
if [ "$in_git_repo" = true ]; then
  gitignore="$toplevel/.gitignore"

  # Atomic .gitignore update using mktemp + mv
  tmp=$(mktemp)
  {
    # Preserve existing content
    cat "$gitignore" 2>/dev/null || true
    # Add entries if not already present
    grep -qx "/scratch/" "$gitignore" 2>/dev/null || echo "/scratch/"
    grep -qx "/var/tmp/" "$gitignore" 2>/dev/null || echo "/var/tmp/"
  } > "$tmp"
  mv "$tmp" "$gitignore"

  echo "Updated .gitignore"
fi

echo "✅ Workspace initialized:"
echo "   /var/tmp/$workplace (ephemeral)"
echo "   $scratch (working files)"
echo "   $skills (global skills)"

# Export environment variables for Claude Code
export WORKSPACE_VAR_TMP="/var/tmp/$workplace"
export WORKSPACE_SCRATCH="$scratch"
export WORKSPACE_NAME="$workplace"
export WORKSPACE_IN_GIT_REPO="$in_git_repo"
