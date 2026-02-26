**Skill**: [Session Chronicle](../SKILL.md)

# Session Archaeology Scripts

Bash scripts for scanning session files and tracing UUID chains.

---

## Step 1: Full Project Scan

Scan ALL session files (main + subagent) to build complete index:

```bash
/usr/bin/env bash << 'SCAN_EOF'
set -euo pipefail

CWD=$(pwd)
ENCODED_PATH=$(echo "$CWD" | tr '/' '-')
PROJECT_SESSIONS="$HOME/.claude/projects/$ENCODED_PATH"

if [[ ! -d "$PROJECT_SESSIONS" ]]; then
  echo "ERROR: Project sessions directory not found: $PROJECT_SESSIONS" >&2
  exit 1
fi

echo "=== Building Session Index ==="
MAIN_COUNT=0
AGENT_COUNT=0

# Main sessions
echo "Main sessions:"
for f in "$PROJECT_SESSIONS"/*.jsonl; do
  [[ ! -f "$f" ]] && continue
  name=$(basename "$f" .jsonl)
  [[ "$name" =~ ^agent- ]] && continue

  lines=$(wc -l < "$f" | tr -d ' ')
  first_ts=$(head -1 "$f" | jq -r '.timestamp // "unknown"') || first_ts="parse-error"
  last_ts=$(tail -1 "$f" | jq -r '.timestamp // "unknown"') || last_ts="parse-error"

  if [[ "$first_ts" == "parse-error" ]]; then
    echo "  WARNING: Failed to parse timestamps in $name" >&2
  fi

  echo "  $name|main|$lines|$first_ts|$last_ts"
  ((MAIN_COUNT++)) || true
done

# Subagent sessions
echo "Subagent sessions:"
for f in "$PROJECT_SESSIONS"/agent-*.jsonl; do
  [[ ! -f "$f" ]] && continue
  name=$(basename "$f" .jsonl)

  lines=$(wc -l < "$f" | tr -d ' ')
  first_ts=$(head -1 "$f" | jq -r '.timestamp // "unknown"') || first_ts="parse-error"

  echo "  $name|subagent|$lines|$first_ts"
  ((AGENT_COUNT++)) || true
done

echo ""
echo "✓ Indexed $MAIN_COUNT main + $AGENT_COUNT subagent sessions"

if [[ $MAIN_COUNT -eq 0 && $AGENT_COUNT -eq 0 ]]; then
  echo "ERROR: No sessions found to index" >&2
  exit 1
fi
SCAN_EOF
```

## Step 2: Build session_contexts Array

**CRITICAL**: This array must contain ALL sessions. Example output:

```json
{
  "session_contexts": [
    {
      "session_uuid": "8c821a19-e4f4-45d5-9338-be3a47ac81a3",
      "type": "main",
      "entries": 980,
      "timestamp_start": "2026-01-03T21:25:07.435Z",
      "description": "Primary session - research iterations, PR preparation"
    },
    {
      "session_uuid": "agent-a728ebe",
      "type": "subagent",
      "entries": 113,
      "timestamp_start": "2026-01-02T07:25:47.658Z",
      "description": "Explore agent - codebase analysis"
    }
  ]
}
```

## Step 3: Trace UUID Chain (Optional)

For detailed provenance of specific edits:

```bash
/usr/bin/env bash << 'TRACE_EOF'
set -euo pipefail

trace_uuid_chain() {
  local uuid="$1"
  local session_file="$2"
  local depth=0
  local max_depth=100

  if [[ -z "$uuid" ]]; then
    echo "ERROR: UUID argument required" >&2
    return 1
  fi

  if [[ ! -f "$session_file" ]]; then
    echo "ERROR: Session file not found: $session_file" >&2
    return 1
  fi

  echo "Tracing UUID chain from: $uuid"

  while [[ -n "$uuid" && $depth -lt $max_depth ]]; do
    # Use jq with explicit error handling
    entry=$(jq -c "select(.uuid == \"$uuid\")" "$session_file" 2>&1) || {
      echo "ERROR: jq failed parsing $session_file" >&2
      return 1
    }

    if [[ -n "$entry" ]]; then
      parent=$(echo "$entry" | jq -r '.parentUuid // empty') || parent=""
      timestamp=$(echo "$entry" | jq -r '.timestamp // "unknown"') || timestamp="unknown"
      type=$(echo "$entry" | jq -r '.type // "unknown"') || type="unknown"

      echo "  [$depth] $uuid ($type) @ $timestamp"
      echo "       -> parent: ${parent:-<root>}"

      uuid="$parent"
      ((depth++)) || true
    else
      echo "  UUID $uuid not in current session, searching others..."
      found=false
      for session in "$PROJECT_SESSIONS"/*.jsonl; do
        [[ ! -f "$session" ]] && continue
        if grep -q "\"uuid\":\"$uuid\"" "$session"; then
          session_file="$session"
          echo "  ✓ Found in $(basename "$session")"
          found=true
          break
        fi
      done
      if [[ "$found" == "false" ]]; then
        echo "  WARNING: UUID chain broken - $uuid not found in any session" >&2
        break
      fi
    fi
  done

  if [[ $depth -ge $max_depth ]]; then
    echo "WARNING: Reached max chain depth ($max_depth) - chain may be incomplete" >&2
  fi

  echo "✓ Chain depth: $depth"
}
TRACE_EOF
```
