---
name: asciinema-streaming-backup
description: Real-time asciinema recording backup to GitHub orphan branch with idle-based chunking and brotli archival. TRIGGERS - streaming backup, recording backup, asciinema backup, continuous recording, session backup, orphan branch recording, zstd streaming, chunked recording, real-time backup, github recording storage.
allowed-tools: Read, Bash, Glob, Write, Edit, AskUserQuestion
---

# asciinema-streaming-backup

Complete system for streaming asciinema recordings to GitHub with automatic brotli archival. Uses idle-detection for intelligent chunking, zstd for concatenatable streaming compression, and GitHub Actions for final brotli recompression.

> **Platform**: macOS, Linux
> **Isolation**: Uses Git orphan branch (separate history, cannot pollute main)
> **Setup**: GitHub CLI (`gh`) for all GitHub operations

---

## Architecture Overview

```
┌─────────────────┐     zstd chunks      ┌─────────────────┐     Actions      ┌─────────────────┐
│  asciinema rec  │ ──────────────────▶  │  GitHub Orphan  │ ───────────────▶ │  brotli archive │
│  + idle-chunker │   (concatenatable)   │  gh-recordings  │                  │  (300x compress)│
└─────────────────┘                      └─────────────────┘                  └─────────────────┘
         │                                        │
         │ Idle ≥30s triggers chunk               │ Separate history
         ▼                                        │ Cannot PR to main
    ~/asciinema_recordings/                       ▼
    └── repo-name/                          .github/workflows/
        └── chunks/*.zst                    └── recompress.yml
```

---

## Requirements

| Component         | Required | Installation             | Version       |
| ----------------- | -------- | ------------------------ | ------------- |
| **asciinema CLI** | Yes      | `brew install asciinema` | 3.0+ (Rust)   |
| **zstd**          | Yes      | `brew install zstd`      | Any           |
| **brotli**        | Yes      | `brew install brotli`    | Any           |
| **git**           | Yes      | Pre-installed            | 2.20+         |
| **gh CLI**        | Yes      | `brew install gh`        | Any           |
| **fswatch**       | Optional | `brew install fswatch`   | For real-time |

---

## Workflow Phases

### Phase 0: Preflight - Tool Validation

**Purpose**: Verify all tools installed, offer self-correction if missing.

```bash
#!/usr/bin/env bash
# preflight-tools.sh - Validates all tool requirements

MISSING=()

for tool in asciinema zstd brotli git gh; do
  if command -v "$tool" &>/dev/null; then
    echo "✓ $tool: $(command -v "$tool")"
  else
    MISSING+=("$tool")
    echo "✗ $tool: MISSING"
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "Install missing tools:"
  echo "  brew install ${MISSING[*]}"
  exit 1
fi

# Check asciinema version (need 3.0+ for Rust version)
ASCIINEMA_VERSION=$(asciinema --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ "${ASCIINEMA_VERSION%%.*}" -lt 3 ]]; then
  echo ""
  echo "⚠ asciinema $ASCIINEMA_VERSION detected. Version 3.0+ recommended."
  echo "  Upgrade: brew upgrade asciinema"
fi

echo ""
echo "✓ All required tools installed"
```

---

### Phase 1: Preflight - GitHub Account Detection

**Purpose**: Detect available GitHub accounts/users from multiple sources.

**Detection Sources** (in priority order):

1. **SSH Config** (`~/.ssh/config`) - Host aliases like `github.com-personal`
2. **gh CLI** (`gh auth status`) - Authenticated GitHub accounts
3. **mise env** (`.mise.toml`) - `GH_TOKEN`, `GITHUB_USER` variables
4. **git config** - `user.name`, `user.email` per directory
5. **gitconfig includes** - Conditional includes based on directory

```bash
#!/usr/bin/env bash
# detect-github-accounts.sh - Discovers available GitHub accounts

echo "=== Detecting GitHub Accounts ==="
echo ""

ACCOUNTS=()

# 1. SSH Config - Look for github.com-* host aliases
echo "--- SSH Config ---"
if [[ -f ~/.ssh/config ]]; then
  SSH_HOSTS=$(grep -E "^Host github\.com-" ~/.ssh/config | awk '{print $2}' | sort -u)
  if [[ -n "$SSH_HOSTS" ]]; then
    while IFS= read -r host; do
      # Extract username from IdentityFile path or host suffix
      USERNAME=$(echo "$host" | sed 's/github.com-//')
      echo "  SSH: $host → $USERNAME"
      ACCOUNTS+=("ssh:$USERNAME:$host")
    done <<< "$SSH_HOSTS"
  else
    echo "  No github.com-* aliases found"
  fi
else
  echo "  ~/.ssh/config not found"
fi

# 2. gh CLI authenticated accounts
echo ""
echo "--- GitHub CLI (gh) ---"
if command -v gh &>/dev/null; then
  GH_ACCOUNTS=$(gh auth status 2>&1 | grep -E "Logged in to github" | sed 's/.*as \([^ ]*\).*/\1/')
  if [[ -n "$GH_ACCOUNTS" ]]; then
    while IFS= read -r user; do
      echo "  gh: $user"
      ACCOUNTS+=("gh:$user:github.com")
    done <<< "$GH_ACCOUNTS"
  else
    echo "  No authenticated accounts"
  fi
else
  echo "  gh CLI not installed"
fi

# 3. mise env (current directory)
echo ""
echo "--- mise env ---"
if [[ -f .mise.toml ]]; then
  MISE_USER=$(grep -E "GITHUB_USER|GH_USER" .mise.toml | head -1 | sed 's/.*= *"\([^"]*\)".*/\1/')
  if [[ -n "$MISE_USER" ]]; then
    echo "  mise: $MISE_USER (from .mise.toml)"
    ACCOUNTS+=("mise:$MISE_USER:mise")
  else
    echo "  No GITHUB_USER in .mise.toml"
  fi
elif command -v mise &>/dev/null; then
  MISE_USER=$(mise env 2>/dev/null | grep -E "GITHUB_USER|GH_USER" | head -1 | cut -d= -f2 | tr -d '"')
  if [[ -n "$MISE_USER" ]]; then
    echo "  mise: $MISE_USER (from environment)"
    ACCOUNTS+=("mise:$MISE_USER:mise")
  else
    echo "  No GITHUB_USER in mise env"
  fi
else
  echo "  mise not available"
fi

# 4. Git config (global and local)
echo ""
echo "--- Git Config ---"
GIT_USER=$(git config user.name 2>/dev/null)
GIT_EMAIL=$(git config user.email 2>/dev/null)
if [[ -n "$GIT_USER" ]]; then
  echo "  git: $GIT_USER <$GIT_EMAIL>"
  ACCOUNTS+=("git:$GIT_USER:$GIT_EMAIL")
fi

# 5. Check for gitconfig includeIf patterns
echo ""
echo "--- Gitconfig Includes ---"
if [[ -f ~/.gitconfig ]]; then
  INCLUDES=$(grep -A1 "includeIf" ~/.gitconfig 2>/dev/null | grep "path" | sed 's/.*path = //')
  if [[ -n "$INCLUDES" ]]; then
    echo "  Found conditional includes:"
    echo "$INCLUDES" | while read -r inc; do
      echo "    - $inc"
    done
  else
    echo "  No conditional includes"
  fi
fi

# Summary
echo ""
echo "=== Detected Accounts ==="
if [[ ${#ACCOUNTS[@]} -eq 0 ]]; then
  echo "  No GitHub accounts detected!"
  echo "  Run: gh auth login"
else
  for acc in "${ACCOUNTS[@]}"; do
    echo "  - $acc"
  done
fi
```

---

### Phase 2: Interactive Configuration (AskUserQuestion)

**Purpose**: Confirm parameters with user before setup.

#### Question Flow 1: GitHub Account Selection

After detecting accounts, present options to user:

```markdown
## AskUserQuestion: GitHub Account

**Question**: "Which GitHub account should be used for this recording storage?"

**Header**: "GitHub"

**Options** (from detection):

- Option 1: "{detected_username_1}" - "Detected from SSH config (github.com-personal)"
- Option 2: "{detected_username_2}" - "Detected from gh CLI authentication"
- Option 3: "{detected_username_3}" - "Detected from mise env"
  (User can always select "Other" for custom input)

**multiSelect**: false
```

#### Question Flow 2: Repository Selection

```markdown
## AskUserQuestion: Repository

**Question**: "Which repository should store the recordings?"

**Header**: "Repository"

**Options**:

- Option 1: "{current_repo}" - "Current workspace repository (Recommended)"
- Option 2: "dedicated-recordings" - "Create a dedicated recordings repository"
- Option 3: "existing-private" - "Use an existing private repository"
  (User can always select "Other" for custom input)

**multiSelect**: false
```

#### Question Flow 3: Local Folder Path

```markdown
## AskUserQuestion: Local Path

**Question**: "Where should the local recording storage be located?"

**Header**: "Local Path"

**Options**:

- Option 1: "~/asciinema_recordings/{repo}" - "Default recommended location (Recommended)"
- Option 2: "~/recordings/{repo}" - "Alternative short path"
- Option 3: "./.recordings" - "Inside current workspace (gitignored)"
  (User can always select "Other" for custom input)

**multiSelect**: false
```

#### Question Flow 4: Idle Threshold

```markdown
## AskUserQuestion: Chunk Timing

**Question**: "How many seconds of idle time before creating a chunk?"

**Header**: "Idle Time"

**Options**:

- Option 1: "30 seconds" - "Balanced: good chunk size, reasonable frequency (Recommended)"
- Option 2: "15 seconds" - "Frequent: smaller chunks, more commits"
- Option 3: "60 seconds" - "Infrequent: larger chunks, fewer commits"
- Option 4: "120 seconds" - "Minimal: only during extended pauses"

**multiSelect**: false
```

---

### Phase 3: Repository Setup

**Purpose**: Create orphan branch with GitHub Actions workflow using GitHub CLI.

**Important**: All GitHub operations use `gh` CLI (not raw git push).

```bash
#!/usr/bin/env bash
# setup-orphan-branch.sh

GITHUB_USER="$1"      # From AskUserQuestion
REPO_NAME="$2"        # From AskUserQuestion
LOCAL_BASE="$3"       # From AskUserQuestion (default: ~/asciinema_recordings)
IDLE_THRESHOLD="$4"   # From AskUserQuestion (default: 30)

BRANCH="gh-recordings"
LOCAL_DIR="${LOCAL_BASE}/${REPO_NAME}"

# Construct repo URL using detected SSH host or default
if [[ -n "$SSH_HOST" ]]; then
  REPO_URL="git@${SSH_HOST}:${GITHUB_USER}/${REPO_NAME}.git"
else
  REPO_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
fi

echo "=== Setup Configuration ==="
echo "  GitHub User: $GITHUB_USER"
echo "  Repository: $REPO_NAME"
echo "  Repo URL: $REPO_URL"
echo "  Local Path: $LOCAL_DIR"
echo "  Idle Threshold: ${IDLE_THRESHOLD}s"
echo ""

# Check if orphan branch exists remotely
if git ls-remote --heads "$REPO_URL" "$BRANCH" 2>/dev/null | grep -q "$BRANCH"; then
  echo "✓ Orphan branch '$BRANCH' already exists"

  if [[ -d "$LOCAL_DIR" ]]; then
    echo "✓ Local clone exists, pulling latest..."
    git -C "$LOCAL_DIR" pull
  else
    echo "→ Cloning to: $LOCAL_DIR"
    mkdir -p "$(dirname "$LOCAL_DIR")"
    git clone --single-branch --branch "$BRANCH" --depth 1 "$REPO_URL" "$LOCAL_DIR"
  fi
else
  echo "→ Creating orphan branch '$BRANCH'..."

  # Use gh CLI to ensure proper authentication
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT

  # Clone using gh CLI (handles auth automatically)
  gh repo clone "${GITHUB_USER}/${REPO_NAME}" "$TEMP_DIR" -- --depth 1
  cd "$TEMP_DIR"

  # Create orphan branch
  git checkout --orphan "$BRANCH"
  git rm -rf .

  # Setup directory structure
  mkdir -p .github/workflows chunks archives

  # Create workflow (see references/github-workflow.md for full version)
  cat > .github/workflows/recompress.yml << 'WORKFLOW_EOF'
name: Recompress to Brotli

on:
  push:
    branches: [gh-recordings]
    paths: ['chunks/**/*.zst']
  workflow_dispatch:

jobs:
  recompress:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: sudo apt-get update && sudo apt-get install -y zstd brotli

      - name: Recompress chunks
        run: |
          if compgen -G "chunks/*.zst" > /dev/null; then
            mkdir -p archives
            ARCHIVE="session_$(date +%Y%m%d_%H%M%S).cast.br"
            ls -1 chunks/*.zst | sort | xargs cat | zstd -d | brotli -9 -o "archives/$ARCHIVE"
            rm -f chunks/*.zst
            echo "ARCHIVE=$ARCHIVE" >> $GITHUB_ENV
          fi

      - name: Commit
        if: env.ARCHIVE != ''
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore: archive to brotli (${{ env.ARCHIVE }})"
          file_pattern: 'archives/*.br chunks/'
WORKFLOW_EOF

  # Create READMEs
  cat > chunks/README.md << 'EOF'
# Chunks
Streaming zstd-compressed recording chunks.
Auto-deleted after archival to brotli.
EOF

  cat > archives/README.md << 'EOF'
# Archives
Final brotli-compressed recordings.
~300x compression ratio.
EOF

  cat > README.md << 'EOF'
# Recording Storage (Orphan Branch)

This branch stores asciinema recording backups.
Completely isolated from main codebase history.

## Structure
- `chunks/` - Streaming zstd chunks (temporary)
- `archives/` - Brotli archives (permanent)

## Isolation Guarantee
This is an orphan branch with no shared history.
Git refuses to merge: "refusing to merge unrelated histories"
EOF

  # Commit and push
  git add .
  git commit -m "init: recording storage (orphan branch)"
  git push -u origin "$BRANCH"

  # Clone to local recordings directory
  cd -
  mkdir -p "$(dirname "$LOCAL_DIR")"
  git clone --single-branch --branch "$BRANCH" --depth 1 "$REPO_URL" "$LOCAL_DIR"
fi

# Install idle-chunker with configured threshold
cat > "$LOCAL_DIR/idle-chunker.sh" << CHUNKER_EOF
#!/usr/bin/env bash
# idle-chunker.sh - Auto-generated with threshold: ${IDLE_THRESHOLD}s
CAST_FILE="\${1:?Usage: idle-chunker.sh <cast_file>}"
IDLE_THRESHOLD="${IDLE_THRESHOLD}"
cd "\$(dirname "\$0")"
last_pos=0
echo "Monitoring: \$CAST_FILE (idle threshold: \${IDLE_THRESHOLD}s)"
while [[ -f "\$CAST_FILE" ]] || sleep 2; do
  [[ -f "\$CAST_FILE" ]] || continue
  mtime=\$(stat -f%m "\$CAST_FILE" 2>/dev/null || stat -c%Y "\$CAST_FILE")
  idle=\$(($(date +%s) - mtime))
  size=\$(stat -f%z "\$CAST_FILE" 2>/dev/null || stat -c%s "\$CAST_FILE")
  if (( idle >= IDLE_THRESHOLD && size > last_pos )); then
    chunk="chunks/chunk_\$(date +%Y%m%d_%H%M%S).cast"
    tail -c +\$((last_pos + 1)) "\$CAST_FILE" > "\$chunk"
    zstd -3 --rm "\$chunk"
    git add chunks/ && git commit -m "chunk \$(date +%H:%M)" && git push
    last_pos=\$size
    echo "[\$(date +%H:%M:%S)] Created: \${chunk}.zst"
  fi
  sleep 5
done
CHUNKER_EOF
chmod +x "$LOCAL_DIR/idle-chunker.sh"

echo ""
echo "=== Setup Complete ==="
echo "  Local: $LOCAL_DIR"
echo "  Chunker: $LOCAL_DIR/idle-chunker.sh"
```

---

### Phase 4: Validation & Self-Correction

**Purpose**: Validate entire system and auto-fix issues.

See [references/setup-scripts.md](./references/setup-scripts.md) for complete validation scripts.

---

## AskUserQuestion Integration Summary

When this skill is invoked, use AskUserQuestion tool in this sequence:

### Step 1: Run Detection Scripts

```bash
# Detect tools
for tool in asciinema zstd brotli git gh; do
  command -v "$tool" &>/dev/null && echo "✓ $tool" || echo "✗ $tool"
done

# Detect GitHub accounts (see Phase 1 script)
```

### Step 2: Present Questions

Based on detection results, ask:

1. **GitHub Account** - From detected accounts
2. **Repository** - Current workspace or dedicated repo
3. **Local Path** - Default: `~/asciinema_recordings/{repo}`
4. **Idle Threshold** - Default: 30 seconds

### Step 3: Execute Setup

With confirmed parameters, run Phase 3 setup script.

### Step 4: Validate and Display Instructions

````markdown
## Setup Complete!

**Local Storage**: ~/asciinema_recordings/{repo}
**Orphan Branch**: gh-recordings (isolated from main)
**GitHub Actions**: Auto-recompresses chunks to brotli

### To Start Recording:

**Terminal 1** (recording):

```bash
asciinema rec $PWD/tmp/{workspace}_{datetime}.cast
```
````

**Terminal 2** (chunker):

```bash
~/asciinema_recordings/{repo}/idle-chunker.sh $PWD/tmp/*.cast
```

```

---

## TodoWrite Task Templates

### Template: Full Interactive Setup

```

1. [Preflight] Check required tools (asciinema, zstd, brotli, git, gh)
2. [Preflight] Offer installation for missing tools via Homebrew
3. [Detection] Scan SSH config for github.com-\* host aliases
4. [Detection] Check gh CLI authenticated accounts
5. [Detection] Check mise env for GITHUB_USER/GH_TOKEN
6. [Detection] Check git config for user.name/email
7. [AskUser] Present GitHub account options from detection
8. [AskUser] Confirm repository selection
9. [AskUser] Confirm local storage path (default: ~/asciinema_recordings/)
10. [AskUser] Confirm idle threshold (default: 30s)
11. [Setup] Check if orphan branch exists on remote
12. [Setup] Create orphan branch via gh CLI if missing
13. [Setup] Install GitHub Actions workflow
14. [Setup] Clone orphan branch to local path
15. [Setup] Install idle-chunker.sh with configured threshold
16. [Validate] Verify local directory structure
17. [Validate] Test compression round-trip
18. [Guide] Display recording start instructions

````

---

## Key Design Decisions

| Decision                       | Rationale                                          |
| ------------------------------ | -------------------------------------------------- |
| **Default: ~/asciinema_recordings/** | Clear purpose, not confused with other recordings |
| **zstd for streaming**         | Supports frame concatenation (brotli doesn't)      |
| **brotli for archival**        | Best compression ratio (~300x for .cast files)     |
| **Orphan branch**              | Complete isolation, can't pollute main history     |
| **gh CLI for setup**           | Handles auth automatically, consistent experience  |
| **Multi-account detection**    | Different repos may need different GitHub users    |
| **30s default idle**           | Balances chunk size vs frequency                   |

---

## Troubleshooting

### "Multiple GitHub accounts detected"

This is expected! Different repositories may belong to different accounts.

**Fix**: The skill detects all available accounts and asks you to choose the correct one per repository.

### "Cannot push to orphan branch"

**Cause**: Wrong GitHub account or authentication issue.

**Fix**:

```bash
# Check which account gh is using
gh auth status

# Switch account if needed
gh auth switch

# Re-authenticate if needed
gh auth login
````

### "SSH permission denied"

**Cause**: SSH key not associated with the selected GitHub account.

**Fix**:

```bash
# Test SSH connection with specific host alias
ssh -T git@github.com-personal

# Add key to ssh-agent
ssh-add ~/.ssh/id_ed25519_personal
```

---

## Reference Documentation

- [Idle Chunker Script](./references/idle-chunker.md) - Complete chunker implementation
- [GitHub Workflow](./references/github-workflow.md) - Full Actions workflow
- [Setup Scripts](./references/setup-scripts.md) - All setup and validation scripts
- [asciinema 3.0 Docs](https://docs.asciinema.org/)
- [zstd Frame Format](https://github.com/facebook/zstd)
- [Git Orphan Branches](https://graphite.dev/guides/git-orphan-branches)
