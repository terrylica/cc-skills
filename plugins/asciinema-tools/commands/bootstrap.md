---
description: Pre-session bootstrap - sets up orphan branch, recording and streaming BEFORE entering Claude Code. TRIGGERS - bootstrap, pre-session, start streaming, before claude.
allowed-tools: Bash, AskUserQuestion, Glob, Write, Read
argument-hint: "[-r repo] [-b branch] [--setup-orphan] [--idle N] [--zstd N] [-y|--yes]"
---

# /asciinema-tools:bootstrap

Generate a bootstrap script that runs OUTSIDE Claude Code CLI to set up automatic session recording and streaming to GitHub.

## Critical Workflow

This command generates a script that runs BEFORE entering Claude Code:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PRE-CLAUDE BOOTSTRAP WORKFLOW                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. RUN BOOTSTRAP (in Claude Code):                                         │
│     /asciinema-tools:bootstrap                                              │
│     → Generates bootstrap-claude-session.sh                                 │
│                                                                             │
│  2. EXIT CLAUDE and RUN BOOTSTRAP:                                          │
│     $ source bootstrap-claude-session.sh                                    │
│     → Starts asciinema recording                                            │
│     → Starts idle-chunker (streams to GitHub)                               │
│                                                                             │
│  3. START CLAUDE:                                                           │
│     $ claude                                                                │
│     → Work normally - everything streams to GitHub                          │
│                                                                             │
│  4. EXIT (Ctrl+D):                                                          │
│     → Cleanup trap pushes final chunk                                       │
│     → GitHub Actions recompresses to brotli                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Arguments

| Argument         | Description                                          |
| ---------------- | ---------------------------------------------------- |
| `-r, --repo`     | GitHub repository (e.g., `owner/repo`)               |
| `-b, --branch`   | Orphan branch name (default: `asciinema-recordings`) |
| `--setup-orphan` | Force create orphan branch                           |
| `--idle N`       | Idle threshold in seconds (default: 30)              |
| `--zstd N`       | zstd compression level (default: 3)                  |
| `-y, --yes`      | Skip confirmation prompts                            |

## Execution

### Phase 0: Preflight Check

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
MISSING=()
for tool in asciinema zstd git gh; do
  command -v "$tool" &>/dev/null || MISSING+=("$tool")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "MISSING: ${MISSING[*]}"
  exit 1
fi

echo "PREFLIGHT: OK"
asciinema --version | head -1
gh auth status 2>&1 | grep -oE 'Logged in to github.com' | head -1
PREFLIGHT_EOF
```

### Phase 1: Detect Repository Context

**MANDATORY**: Run before AskUserQuestion to auto-populate options.

```bash
/usr/bin/env bash << 'DETECT_CONTEXT_EOF'
IN_GIT_REPO="false"
CURRENT_REPO_URL=""
CURRENT_REPO_OWNER=""
CURRENT_REPO_NAME=""
ORPHAN_BRANCH_EXISTS="false"
LOCAL_CLONE_EXISTS="false"
ORPHAN_BRANCH="asciinema-recordings"

if git rev-parse --git-dir &>/dev/null 2>&1; then
  IN_GIT_REPO="true"

  if git remote get-url origin &>/dev/null 2>&1; then
    CURRENT_REPO_URL=$(git remote get-url origin)
  elif [[ -n "$(git remote)" ]]; then
    REMOTE=$(git remote | head -1)
    CURRENT_REPO_URL=$(git remote get-url "$REMOTE")
  fi

  if [[ -n "$CURRENT_REPO_URL" ]]; then
    if [[ "$CURRENT_REPO_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
      CURRENT_REPO_OWNER="${BASH_REMATCH[1]}"
      CURRENT_REPO_NAME="${BASH_REMATCH[2]%.git}"
    fi

    if git ls-remote --heads "$CURRENT_REPO_URL" "$ORPHAN_BRANCH" 2>/dev/null | grep -q "$ORPHAN_BRANCH"; then
      ORPHAN_BRANCH_EXISTS="true"
    fi

    LOCAL_CLONE_PATH="$HOME/asciinema_recordings/$CURRENT_REPO_NAME"
    if [[ -d "$LOCAL_CLONE_PATH/.git" ]]; then
      LOCAL_CLONE_EXISTS="true"
    fi
  fi
fi

echo "IN_GIT_REPO=$IN_GIT_REPO"
echo "CURRENT_REPO_URL=$CURRENT_REPO_URL"
echo "CURRENT_REPO_OWNER=$CURRENT_REPO_OWNER"
echo "CURRENT_REPO_NAME=$CURRENT_REPO_NAME"
echo "ORPHAN_BRANCH_EXISTS=$ORPHAN_BRANCH_EXISTS"
echo "LOCAL_CLONE_EXISTS=$LOCAL_CLONE_EXISTS"
DETECT_CONTEXT_EOF
```

### Phase 2: Repository Selection (MANDATORY AskUserQuestion)

Based on detection results:

**If IN_GIT_REPO=true, ORPHAN_BRANCH_EXISTS=true:**

```
Question: "Orphan branch found in {repo}. Use it?"
Header: "Destination"
Options:
  - Label: "Use existing (Recommended)"
    Description: "Branch 'asciinema-recordings' already configured in {repo}"
  - Label: "Use different repository"
    Description: "Store recordings in a different repo"
```

**If IN_GIT_REPO=true, ORPHAN_BRANCH_EXISTS=false:**

```
Question: "No orphan branch in {repo}. Create one?"
Header: "Setup"
Options:
  - Label: "Create orphan branch (Recommended)"
    Description: "Initialize with GitHub Actions workflow for brotli"
  - Label: "Use different repository"
    Description: "Store recordings elsewhere"
```

**If IN_GIT_REPO=false:**

```
Question: "Not in a git repo. Where to store recordings?"
Header: "Destination"
Options:
  - Label: "Dedicated recordings repo"
    Description: "Use {owner}/asciinema-recordings"
  - Label: "Enter repository"
    Description: "Specify owner/repo manually"
```

### Phase 3: Create Orphan Branch (if needed)

```bash
/usr/bin/env bash << 'CREATE_ORPHAN_EOF'
REPO_URL="${1:?}"
BRANCH="${2:-asciinema-recordings}"
LOCAL_PATH="$HOME/asciinema_recordings/$(basename "$REPO_URL" .git)"

# Clone bare and create orphan
git clone --bare "$REPO_URL" /tmp/orphan-setup
cd /tmp/orphan-setup

# Create orphan branch
git checkout --orphan "$BRANCH"
git reset --hard
git commit --allow-empty -m "Initialize asciinema recordings"
git push origin "$BRANCH"

# Cleanup
rm -rf /tmp/orphan-setup

# Clone orphan branch locally
mkdir -p "$LOCAL_PATH"
git clone --single-branch --branch "$BRANCH" --depth 1 "$REPO_URL" "$LOCAL_PATH"
mkdir -p "$LOCAL_PATH/chunks"

echo "ORPHAN_CREATED: $LOCAL_PATH"
CREATE_ORPHAN_EOF
```

### Phase 4: Compression Settings (MANDATORY AskUserQuestion)

```
Question: "Configure streaming compression:"
Header: "Compression"
Options:
  - Label: "Default (30s idle, zstd-3) (Recommended)"
    Description: "Balanced chunking frequency and compression"
  - Label: "Fast (15s idle, zstd-1)"
    Description: "More frequent chunks, lower compression"
  - Label: "Compact (60s idle, zstd-6)"
    Description: "Less frequent chunks, higher compression"
```

### Phase 5: Generate Bootstrap Script

The generated script includes:

- Orphan branch clone/update
- asciinema recording start
- idle-chunker background process
- EXIT trap for cleanup

Output location: `$PWD/tmp/bootstrap-claude-session.sh`

### Phase 6: Display Instructions

```markdown
## Bootstrap Complete

Script generated at: `$PWD/tmp/bootstrap-claude-session.sh`

### Quick Start

1. Exit Claude Code: `exit` or Ctrl+D
2. Run bootstrap: `source $PWD/tmp/bootstrap-claude-session.sh`
3. Start Claude: `claude`
4. Work normally - all output streams to GitHub
5. Exit when done - cleanup runs automatically

### What Happens

- asciinema records to `{workspace}_{datetime}.cast`
- idle-chunker monitors for {idle}s pauses
- On idle, chunk is zstd compressed and pushed
- GitHub Actions recompresses to brotli (~300:1)
- On exit, final chunk pushed automatically
```

## Skip Logic

- If `-r` and `-b` provided -> skip repository selection
- If `--idle` and `--zstd` provided -> skip compression config
- If `-y` provided -> skip all confirmations
- If `--setup-orphan` provided -> force create orphan branch
