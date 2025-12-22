---
name: asciinema-streaming-backup
description: Real-time asciinema recording backup to GitHub orphan branch with idle-based chunking and brotli archival. TRIGGERS - streaming backup, recording backup, asciinema backup, continuous recording, session backup, orphan branch recording, zstd streaming, chunked recording, real-time backup, github recording storage.
allowed-tools: Read, Bash, Glob, Write, Edit
---

# asciinema-streaming-backup

Complete system for streaming asciinema recordings to GitHub with automatic brotli archival. Uses idle-detection for intelligent chunking, zstd for concatenatable streaming compression, and GitHub Actions for final brotli recompression.

> **Platform**: macOS, Linux
> **Isolation**: Uses Git orphan branch (separate history, cannot pollute main)

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
    ~/recordings/                                 ▼
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

### Phase 0: Preflight Validation

**Purpose**: Verify all tools installed, offer self-correction if missing.

```bash
#!/usr/bin/env bash
# preflight-check.sh - Validates all requirements

MISSING=()

# Check each tool
for tool in asciinema zstd brotli git gh; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING+=("$tool")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing tools: ${MISSING[*]}"
  echo ""
  echo "Install with:"
  echo "  brew install ${MISSING[*]}"
  exit 1
fi

# Check asciinema version (need 3.0+ for Rust version)
ASCIINEMA_VERSION=$(asciinema --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ "${ASCIINEMA_VERSION%%.*}" -lt 3 ]]; then
  echo "Warning: asciinema $ASCIINEMA_VERSION detected. Version 3.0+ recommended."
  echo "Upgrade: brew upgrade asciinema"
fi

echo "All requirements satisfied"
```

**Self-Correction**: If tools are missing, generate installation command and offer to run it.

---

### Phase 1: Repository Setup

**Purpose**: Create orphan branch with GitHub Actions workflow.

#### Step 1.1: Detect or Create Orphan Branch

```bash
#!/usr/bin/env bash
# setup-orphan-branch.sh

REPO_URL="$1"  # e.g., git@github.com:user/repo.git
BRANCH="gh-recordings"
LOCAL_DIR="$HOME/recordings/$(basename "$REPO_URL" .git)"

# Check if orphan branch exists remotely
if git ls-remote --heads "$REPO_URL" "$BRANCH" | grep -q "$BRANCH"; then
  echo "Orphan branch '$BRANCH' already exists"

  # Clone if not present locally
  if [[ ! -d "$LOCAL_DIR" ]]; then
    git clone --single-branch --branch "$BRANCH" --depth 1 "$REPO_URL" "$LOCAL_DIR"
    echo "Cloned to: $LOCAL_DIR"
  fi
else
  echo "Creating orphan branch '$BRANCH'..."

  # Create temporary clone for setup
  TEMP_DIR=$(mktemp -d)
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
  cd "$TEMP_DIR"

  # Create orphan branch
  git checkout --orphan "$BRANCH"
  git rm -rf .

  # Setup directory structure
  mkdir -p .github/workflows chunks archives

  # Create workflow (content from references/github-workflow.md)
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

      - name: Install compression tools
        run: sudo apt-get update && sudo apt-get install -y zstd brotli

      - name: Recompress chunks to brotli
        run: |
          if compgen -G "chunks/*.zst" > /dev/null; then
            # Concatenate all zstd chunks, decompress, recompress to brotli
            ARCHIVE_NAME="archive_$(date +%Y%m%d_%H%M%S).cast.br"
            cat chunks/*.zst | zstd -d | brotli -9 -o "archives/$ARCHIVE_NAME"
            rm -f chunks/*.zst
            echo "Created: archives/$ARCHIVE_NAME"
            echo "ARCHIVE_NAME=$ARCHIVE_NAME" >> $GITHUB_ENV
          else
            echo "No chunks to process"
          fi

      - name: Commit archive
        if: env.ARCHIVE_NAME != ''
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore: archive recording to brotli (${{ env.ARCHIVE_NAME }})"
          file_pattern: 'archives/*.br chunks/'
WORKFLOW_EOF

  # Create placeholder files
  echo '# Recording chunks (zstd compressed)' > chunks/README.md
  echo '# Brotli archives (final compressed)' > archives/README.md

  # Create README
  cat > README.md << 'README_EOF'
# Recording Storage (Orphan Branch)

This branch stores asciinema recording backups. It is completely isolated from the main codebase.

## Structure

- `chunks/` - Streaming zstd-compressed chunks (auto-deleted after archival)
- `archives/` - Final brotli-compressed recordings (~300x compression)

## How It Works

1. Local idle-chunker monitors asciinema recording
2. When idle ≥30s, creates zstd chunk and pushes here
3. GitHub Action concatenates chunks and recompresses to brotli
4. Chunks are deleted, archive is retained

## Isolation Guarantee

This is an orphan branch with no shared history with main.
Git refuses to merge: "refusing to merge unrelated histories"
README_EOF

  # Commit and push
  git add .
  git commit -m "init: recording storage (orphan branch)"
  git push -u origin "$BRANCH"

  # Cleanup temp and clone properly
  cd -
  rm -rf "$TEMP_DIR"

  # Clone to local recordings directory
  mkdir -p "$(dirname "$LOCAL_DIR")"
  git clone --single-branch --branch "$BRANCH" --depth 1 "$REPO_URL" "$LOCAL_DIR"
  echo "Setup complete: $LOCAL_DIR"
fi
```

#### Step 1.2: Validate Setup

```bash
#!/usr/bin/env bash
# validate-setup.sh

LOCAL_DIR="$1"

ERRORS=()

# Check directory exists
[[ -d "$LOCAL_DIR" ]] || ERRORS+=("Directory not found: $LOCAL_DIR")

# Check it's a git repo
[[ -d "$LOCAL_DIR/.git" ]] || ERRORS+=("Not a git repository")

# Check correct branch
BRANCH=$(git -C "$LOCAL_DIR" branch --show-current 2>/dev/null)
[[ "$BRANCH" == "gh-recordings" ]] || ERRORS+=("Wrong branch: $BRANCH (expected gh-recordings)")

# Check workflow exists
[[ -f "$LOCAL_DIR/.github/workflows/recompress.yml" ]] || ERRORS+=("Workflow missing")

# Check directories exist
[[ -d "$LOCAL_DIR/chunks" ]] || ERRORS+=("chunks/ directory missing")
[[ -d "$LOCAL_DIR/archives" ]] || ERRORS+=("archives/ directory missing")

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Validation failed:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi

echo "Validation passed: $LOCAL_DIR"
```

---

### Phase 2: Idle-Detection Chunking

**Purpose**: Monitor recording and create chunks during idle periods.

#### Step 2.1: Start Recording with Chunker

```bash
#!/usr/bin/env bash
# start-recording.sh

WORKSPACE=$(basename "$PWD")
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
CAST_FILE="$PWD/tmp/${WORKSPACE}_${DATETIME}.cast"
RECORDINGS_DIR="$HOME/recordings/REPO-NAME"  # Customize per repo

# Ensure directories exist
mkdir -p "$PWD/tmp"
mkdir -p "$RECORDINGS_DIR/chunks"

echo "Recording to: $CAST_FILE"
echo "Chunks to: $RECORDINGS_DIR/chunks/"
echo ""
echo "Run this command to start recording:"
echo ""
echo "  asciinema rec $CAST_FILE"
echo ""
echo "Then in another terminal, run the idle-chunker:"
echo ""
echo "  $RECORDINGS_DIR/idle-chunker.sh $CAST_FILE"
```

#### Step 2.2: Idle Chunker Script

This script monitors the .cast file and creates chunks when idle ≥30 seconds.

See [references/idle-chunker.md](./references/idle-chunker.md) for the complete script.

**Quick version**:

```bash
#!/usr/bin/env bash
# idle-chunker.sh - Creates chunks during recording idle periods

CAST_FILE="$1"
RECORDINGS_DIR="$2"  # e.g., ~/recordings/repo-name
IDLE_THRESHOLD="${3:-30}"  # seconds

cd "$RECORDINGS_DIR"
last_chunk_pos=0

while true; do
  [[ -f "$CAST_FILE" ]] || { sleep 5; continue; }

  # Check file modification time
  file_mtime=$(stat -f%m "$CAST_FILE" 2>/dev/null || stat -c%Y "$CAST_FILE")
  now=$(date +%s)
  idle_seconds=$((now - file_mtime))

  if (( idle_seconds >= IDLE_THRESHOLD )); then
    current_size=$(stat -f%z "$CAST_FILE" 2>/dev/null || stat -c%s "$CAST_FILE")

    if (( current_size > last_chunk_pos )); then
      chunk_name="chunk_$(date +%Y%m%d_%H%M%S).cast"

      # Extract new bytes since last chunk
      tail -c +$((last_chunk_pos + 1)) "$CAST_FILE" > "chunks/$chunk_name"
      zstd -3 --rm "chunks/$chunk_name"

      echo "[$(date +%H:%M:%S)] Created: chunks/${chunk_name}.zst (idle ${idle_seconds}s)"

      # Push to GitHub
      git add chunks/ && git commit -m "chunk: $(date +%H:%M)" && git push

      last_chunk_pos=$current_size
    fi
  fi

  sleep 5
done
```

---

### Phase 3: Validation & Self-Correction

**Purpose**: Validate entire system and auto-fix issues.

#### Step 3.1: Full System Validation

```bash
#!/usr/bin/env bash
# validate-system.sh - Complete validation with self-correction

REPO_URL="$1"
LOCAL_DIR="$HOME/recordings/$(basename "$REPO_URL" .git)"

echo "=== System Validation ==="

# 1. Check tools
echo -n "Tools... "
MISSING=()
for tool in asciinema zstd brotli git gh; do
  command -v "$tool" &>/dev/null || MISSING+=("$tool")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "MISSING: ${MISSING[*]}"
  echo "Self-correction: brew install ${MISSING[*]}"
  read -p "Install now? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] && brew install "${MISSING[@]}"
else
  echo "OK"
fi

# 2. Check orphan branch exists
echo -n "Orphan branch... "
if git ls-remote --heads "$REPO_URL" gh-recordings | grep -q gh-recordings; then
  echo "OK"
else
  echo "MISSING"
  echo "Self-correction: Run Phase 1 setup"
  read -p "Create orphan branch now? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] && ./setup-orphan-branch.sh "$REPO_URL"
fi

# 3. Check local clone
echo -n "Local clone... "
if [[ -d "$LOCAL_DIR" ]]; then
  echo "OK ($LOCAL_DIR)"
else
  echo "MISSING"
  echo "Self-correction: Clone orphan branch"
  git clone --single-branch --branch gh-recordings --depth 1 "$REPO_URL" "$LOCAL_DIR"
fi

# 4. Check workflow
echo -n "GitHub Actions workflow... "
if [[ -f "$LOCAL_DIR/.github/workflows/recompress.yml" ]]; then
  echo "OK"
else
  echo "MISSING"
  echo "Self-correction: Regenerate workflow"
  # Copy workflow template
fi

# 5. Test compression round-trip
echo -n "Compression test... "
TEST_DATA="test data $(date)"
echo "$TEST_DATA" | zstd -3 | zstd -d | grep -q "$TEST_DATA" && echo "OK" || echo "FAILED"

# 6. Test brotli
echo -n "Brotli test... "
echo "$TEST_DATA" | brotli | brotli -d | grep -q "$TEST_DATA" && echo "OK" || echo "FAILED"

echo ""
echo "=== Validation Complete ==="
```

#### Step 3.2: Compression Round-Trip Test

```bash
#!/usr/bin/env bash
# test-compression.sh - Validate zstd concatenation works

# Create test chunks
echo '{"version": 2}' > /tmp/test_header.cast
echo '[0.1, "o", "Hello "]' > /tmp/test_chunk1.cast
echo '[0.2, "o", "World"]' > /tmp/test_chunk2.cast

# Compress individually
zstd -3 /tmp/test_header.cast -o /tmp/test_header.cast.zst
zstd -3 /tmp/test_chunk1.cast -o /tmp/test_chunk1.cast.zst
zstd -3 /tmp/test_chunk2.cast -o /tmp/test_chunk2.cast.zst

# Concatenate
cat /tmp/test_header.cast.zst /tmp/test_chunk1.cast.zst /tmp/test_chunk2.cast.zst > /tmp/test_combined.zst

# Decompress and verify
zstd -d /tmp/test_combined.zst -o /tmp/test_combined.cast

# Check content
if grep -q '"version": 2' /tmp/test_combined.cast && \
   grep -q 'Hello' /tmp/test_combined.cast && \
   grep -q 'World' /tmp/test_combined.cast; then
  echo "Concatenation test: PASSED"
else
  echo "Concatenation test: FAILED"
  exit 1
fi

# Cleanup
rm -f /tmp/test_*.cast /tmp/test_*.zst
```

---

## Quick Start

### First-Time Setup

```bash
# 1. Check requirements
for tool in asciinema zstd brotli git gh; do
  command -v "$tool" &>/dev/null && echo "$tool: OK" || echo "$tool: MISSING"
done

# 2. Create orphan branch (replace with your repo)
REPO="git@github.com:YOUR/REPO.git"
./setup-orphan-branch.sh "$REPO"

# 3. Validate setup
./validate-setup.sh "$HOME/recordings/REPO"
```

### Recording Session

```bash
# Terminal 1: Start recording
WORKSPACE=$(basename "$PWD")
asciinema rec $PWD/tmp/${WORKSPACE}_$(date +%Y-%m-%d_%H-%M).cast

# Terminal 2: Start idle-chunker
~/recordings/REPO/idle-chunker.sh $PWD/tmp/${WORKSPACE}_*.cast ~/recordings/REPO
```

---

## TodoWrite Task Templates

### Template: Full Setup

```
1. [Preflight] Validate all tools installed (asciinema, zstd, brotli, git, gh)
2. [Preflight] Self-correct: offer installation for missing tools
3. [Setup] Check if orphan branch exists on remote
4. [Setup] Create orphan branch if missing
5. [Setup] Create GitHub Actions recompress workflow
6. [Setup] Clone orphan branch to ~/recordings/
7. [Validate] Verify local directory structure
8. [Validate] Test compression round-trip (zstd concatenation)
9. [Validate] Test brotli compression
10. [Deploy] Copy idle-chunker.sh to recordings directory
11. [Guide] Display recording start instructions
```

### Template: Recording Session

```
1. [Context] Detect workspace from $PWD
2. [Context] Generate datetime for filename
3. [Context] Ensure tmp/ directory exists
4. [Command] Generate asciinema rec command
5. [Command] Generate idle-chunker command
6. [Guide] Display two-terminal workflow instructions
```

---

## Troubleshooting

### "Cannot push to orphan branch"

**Cause**: Authentication or permissions issue.

**Fix**:

```bash
# Check gh auth status
gh auth status

# Re-authenticate if needed
gh auth login
```

### "Chunks not being created"

**Cause**: Idle threshold not reached, or file not growing.

**Fix**:

- Verify recording is active: `tail -f $CAST_FILE`
- Lower threshold: `IDLE_THRESHOLD=15`
- Check file permissions

### "GitHub Action not triggering"

**Cause**: Workflow file missing or wrong branch filter.

**Fix**:

```bash
# Verify workflow exists
cat ~/recordings/REPO/.github/workflows/recompress.yml

# Check branch filter includes gh-recordings
grep -A2 "branches:" ~/recordings/REPO/.github/workflows/recompress.yml
```

### "Brotli archive empty or corrupted"

**Cause**: zstd chunks not concatenating properly (overlapping data).

**Fix**: Ensure idle-chunker uses `last_chunk_pos` to avoid overlap:

```bash
# Check for overlaps - each chunk should be sequential
for f in chunks/*.zst; do
  zstd -d "$f" -c | head -1
done
```

---

## Key Design Decisions

| Decision                | Rationale                                          |
| ----------------------- | -------------------------------------------------- |
| **zstd for streaming**  | Supports frame concatenation (brotli doesn't)      |
| **brotli for archival** | Best compression ratio (~300x for .cast files)     |
| **Orphan branch**       | Complete isolation, can't pollute main history     |
| **Idle-based chunking** | Semantic breakpoints, not mid-output splits        |
| **Shallow clone**       | Minimal disk usage, can't accidentally access main |
| **30s idle threshold**  | Balances chunk frequency vs semantic completeness  |

---

## Reference Documentation

- [Idle Chunker Script](./references/idle-chunker.md) - Complete chunker implementation
- [GitHub Workflow](./references/github-workflow.md) - Full Actions workflow
- [Setup Scripts](./references/setup-scripts.md) - All setup and validation scripts
- [asciinema 3.0 Docs](https://docs.asciinema.org/)
- [zstd Frame Format](https://github.com/facebook/zstd)
- [Git Orphan Branches](https://graphite.dev/guides/git-orphan-branches)
