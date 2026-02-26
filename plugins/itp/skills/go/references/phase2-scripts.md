**Skill**: [ITP Go Workflow](../SKILL.md)

# Phase 2 Scripts

## 2.1 Format Markdown

Run Prettier against ADR and spec:

```bash
prettier --write --no-config --parser markdown --prose-wrap preserve \
  docs/adr/$ADR_ID.md \
  docs/design/$ADR_ID/spec.md
```

## 2.2 Push to GitHub

```bash
/usr/bin/env bash << 'GIT_EOF_2'
git add docs/adr/$ADR_ID.md docs/design/$ADR_ID/
git commit -m "docs: add ADR and design spec for <slug>"

# If --branch was used:
git push -u origin <type>/$ADR_ID

# If working on current branch (default):
git push origin $(git branch --show-current)
GIT_EOF_2
```

## 2.3 Open in Browser

```bash
/usr/bin/env bash << 'GIT_EOF_3'
# Get repo URL from origin remote (works correctly with forks)
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

if [[ -z "$REMOTE_URL" ]]; then
  echo "Error: No origin remote configured"
  exit 1
fi

# Convert SSH format to HTTPS for browser URLs
# Handles: git@github.com:owner/repo.git
# Handles: git@github.com-username:owner/repo.git (multi-account SSH aliases)
# Handles: https://github.com/owner/repo.git
REPO_URL=$(echo "$REMOTE_URL" | sed -E 's|git@github\.com[^:]*:|https://github.com/|' | sed 's|\.git$||')

BRANCH=$(git branch --show-current)

open "$REPO_URL/blob/$BRANCH/docs/adr/$ADR_ID.md"
open "$REPO_URL/blob/$BRANCH/docs/design/$ADR_ID/spec.md"
GIT_EOF_3
```
