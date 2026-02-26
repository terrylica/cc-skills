**Skill**: [Session Chronicle](../SKILL.md)

# Preflight Scripts

Bash scripts for verifying the environment before session archaeology.

---

## Step 1: Verify Session Storage Location

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
set -euo pipefail

# Check Claude session storage
PROJECT_DIR="$HOME/.claude/projects"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Session storage not found at $PROJECT_DIR" >&2
  echo "  Expected: ~/.claude/projects/" >&2
  echo "  This directory is created by Claude Code on first use." >&2
  exit 1
fi

# Count project folders (0 is valid - just means no sessions yet)
PROJECT_COUNT=$(ls -1d "$PROJECT_DIR"/*/ 2>/dev/null | wc -l || echo "0")
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  echo "WARNING: No project sessions found in $PROJECT_DIR"
  echo "  This may be expected if Claude Code hasn't been used in any projects yet."
else
  echo "✓ Found $PROJECT_COUNT project folders in $PROJECT_DIR"
fi
echo "Ready for session archaeology"
PREFLIGHT_EOF
```

## Step 2: Find Current Project Sessions

```bash
/usr/bin/env bash << 'FIND_SESSIONS_EOF'
set -euo pipefail

# Encode current working directory path (Claude Code path encoding)
CWD=$(pwd)
ENCODED_PATH=$(echo "$CWD" | tr '/' '-')
PROJECT_SESSIONS="$HOME/.claude/projects/$ENCODED_PATH"

if [[ -d "$PROJECT_SESSIONS" ]]; then
  # Count main sessions vs agent sessions (handle empty glob safely)
  MAIN_COUNT=$(ls -1 "$PROJECT_SESSIONS"/*.jsonl 2>/dev/null | grep -v "agent-" | wc -l | tr -d ' ' || echo "0")
  AGENT_COUNT=$(ls -1 "$PROJECT_SESSIONS"/agent-*.jsonl 2>/dev/null | wc -l | tr -d ' ' || echo "0")

  if [[ "$MAIN_COUNT" -eq 0 && "$AGENT_COUNT" -eq 0 ]]; then
    echo "ERROR: Session directory exists but contains no .jsonl files" >&2
    echo "  Location: $PROJECT_SESSIONS" >&2
    exit 1
  fi

  echo "✓ Found $MAIN_COUNT main sessions + $AGENT_COUNT subagent sessions"
  echo "  Location: $PROJECT_SESSIONS"

  # Show main sessions with line counts
  echo -e "\n=== Main Sessions ==="
  for f in "$PROJECT_SESSIONS"/*.jsonl; do
    [[ ! -f "$f" ]] && continue
    name=$(basename "$f" .jsonl)
    [[ "$name" =~ ^agent- ]] && continue
    lines=$(wc -l < "$f" | tr -d ' ')
    echo "  $name ($lines entries)"
  done

  # Show agent sessions summary
  echo -e "\n=== Subagent Sessions ==="
  for f in "$PROJECT_SESSIONS"/agent-*.jsonl; do
    [[ ! -f "$f" ]] && continue
    name=$(basename "$f" .jsonl)
    lines=$(wc -l < "$f" | tr -d ' ')
    echo "  $name ($lines entries)"
  done
else
  echo "ERROR: No sessions found for current project" >&2
  echo "  Expected: $PROJECT_SESSIONS" >&2
  echo "" >&2
  echo "Available project folders:" >&2
  ls -1 "$HOME/.claude/projects/" 2>/dev/null | head -10 || echo "  (none)"
  exit 1
fi
FIND_SESSIONS_EOF
```

## Step 3: Verify Required Tools

```bash
/usr/bin/env bash << 'TOOLS_EOF'
set -euo pipefail

# All tools are REQUIRED - fail loudly if missing
MISSING=0

# Check for jq (required for JSONL parsing)
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not installed (brew install jq)" >&2
  MISSING=1
fi

# Check for brotli (required for compression)
if ! command -v brotli &>/dev/null; then
  echo "ERROR: brotli not installed (brew install brotli)" >&2
  MISSING=1
fi

# Check for aws (required for S3 upload)
if ! command -v aws &>/dev/null; then
  echo "ERROR: aws CLI not installed (brew install awscli)" >&2
  MISSING=1
fi

# Check for op (required for 1Password credential injection)
if ! command -v op &>/dev/null; then
  echo "ERROR: 1Password CLI not installed (brew install 1password-cli)" >&2
  MISSING=1
fi

if [[ $MISSING -eq 1 ]]; then
  echo "" >&2
  echo "PREFLIGHT FAILED: Missing required tools. Install them and retry." >&2
  exit 1
fi

echo "✓ All required tools available: jq, brotli, aws, op"
TOOLS_EOF
```
