---
name: session-chronicle
description: Excavate session logs for provenance tracking. TRIGGERS - who created, document finding, trace origin, session archaeology, provenance, ADR reference.
allowed-tools: Read, Grep, Glob, Bash
---

# Session Chronicle

Excavate Claude Code session logs to capture complete provenance for research findings, ADR decisions, and code contributions. Traces UUID chains across multiple auto-compacted sessions.

## When to Use This Skill

- User asks "who created this?" or "where did this come from?"
- User says "document this finding" with full session context
- ADR or research finding needs provenance tracking
- Git commit needs session UUID references
- Tracing edits across auto-compacted sessions

## Preflight Check

### Step 1: Verify Session Storage Location

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
# Check Claude session storage
PROJECT_DIR="$HOME/.claude/projects"
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Session storage not found at $PROJECT_DIR"
  exit 1
fi

# Count project folders
PROJECT_COUNT=$(ls -1d "$PROJECT_DIR"/*/ 2>/dev/null | wc -l)
echo "Found $PROJECT_COUNT project folders in $PROJECT_DIR"
echo "Ready for session archaeology"
PREFLIGHT_EOF
```

### Step 2: Find Current Project Sessions

```bash
/usr/bin/env bash << 'FIND_SESSIONS_EOF'
# Encode current working directory path
CWD=$(pwd)
ENCODED_PATH=$(echo "$CWD" | tr '/' '-')
PROJECT_SESSIONS="$HOME/.claude/projects/$ENCODED_PATH"

if [[ -d "$PROJECT_SESSIONS" ]]; then
  SESSION_COUNT=$(ls -1 "$PROJECT_SESSIONS"/*.jsonl 2>/dev/null | wc -l)
  echo "Found $SESSION_COUNT session files for current project"
  echo "Location: $PROJECT_SESSIONS"

  # Show largest sessions (likely most relevant)
  echo -e "\nLargest sessions (by line count):"
  wc -l "$PROJECT_SESSIONS"/*.jsonl 2>/dev/null | sort -rn | head -5
else
  echo "No sessions found for current project at: $PROJECT_SESSIONS"
  echo "Checking all project folders..."
  ls -la "$HOME/.claude/projects/" | head -10
fi
FIND_SESSIONS_EOF
```

### Step 3: Verify Required Tools

```bash
/usr/bin/env bash << 'TOOLS_EOF'
# Check for jq (required for JSONL parsing)
command -v jq &>/dev/null || { echo "WARNING: jq not installed (brew install jq)"; }

# Check for gzip (required for compression)
command -v gzip &>/dev/null || { echo "ERROR: gzip not found"; exit 1; }

echo "Required tools available"
TOOLS_EOF
```

---

## Part 1: AskUserQuestion Flows

### Flow A: Identify Target for Provenance

When the skill is triggered, first identify what the user wants to trace:

```
AskUserQuestion:
  question: "What do you want to trace provenance for?"
  header: "Target"
  multiSelect: false
  options:
    - label: "Specific code/feature"
      description: "Trace who created a specific function, feature, or code block"
    - label: "Research finding"
      description: "Document a finding with full session context for reproducibility"
    - label: "Configuration/decision"
      description: "Trace when and why a configuration or architectural decision was made"
    - label: "Custom search"
      description: "Search session logs for specific keywords or patterns"
```

### Flow B: Specify Search Parameters

Based on target type, gather search parameters:

```
AskUserQuestion:
  question: "What keywords or identifiers should we search for?"
  header: "Search"
  multiSelect: true
  options:
    - label: "File path pattern"
      description: "Search for edits to specific files (e.g., **/minimal_3*)"
    - label: "Function/variable name"
      description: "Search for creation of specific identifiers"
    - label: "Session UUID"
      description: "Start from a known session UUID"
    - label: "Date range"
      description: "Limit search to sessions from specific dates"
```

### Flow C: Confirm Discovered Sessions

After scanning, confirm with user:

```
AskUserQuestion:
  question: "Found N related sessions. Which should we include?"
  header: "Sessions"
  multiSelect: true
  options:
    - label: "All discovered sessions"
      description: "Include complete UUID chain (N sessions, ~X MB total)"
    - label: "Most recent chain only"
      description: "Only the chain leading to target (N sessions)"
    - label: "Manual selection"
      description: "I'll specify which sessions to include"
    - label: "Provide more context"
      description: "The search didn't find what I need, let me clarify"
```

### Flow D: Choose Output Format

```
AskUserQuestion:
  question: "What outputs should be generated?"
  header: "Outputs"
  multiSelect: true
  options:
    - label: "provenance.jsonl (append-only log)"
      description: "NDJSON record with UUIDs, timestamps, contributors"
    - label: "Compressed session context (.jsonl.gz)"
      description: "Gzipped excerpt of relevant session entries"
    - label: "Markdown finding document"
      description: "findings/<name>.md with embedded provenance table"
    - label: "Git commit with provenance"
      description: "Structured commit message with session references"
```

---

## Part 2: Session Archaeology Process

### Step 1: Full Project Scan

Scan all session files in the project folder to build a session index:

```bash
/usr/bin/env bash << 'SCAN_EOF'
PROJECT_SESSIONS="$HOME/.claude/projects/$ENCODED_PATH"

# Build session index
echo "Scanning sessions..."
for session in "$PROJECT_SESSIONS"/*.jsonl; do
  SESSION_ID=$(basename "$session" .jsonl)
  LINE_COUNT=$(wc -l < "$session")
  FIRST_TS=$(head -1 "$session" | jq -r '.timestamp // empty')
  LAST_TS=$(tail -1 "$session" | jq -r '.timestamp // empty')

  echo "$SESSION_ID|$LINE_COUNT|$FIRST_TS|$LAST_TS"
done > /tmp/session_index.txt

echo "Indexed $(wc -l < /tmp/session_index.txt) sessions"
SCAN_EOF
```

### Step 2: Search for Target

Search across all sessions for the target:

```bash
/usr/bin/env bash << 'SEARCH_EOF'
# Search for keyword in all sessions
grep -l "SEARCH_TERM" "$PROJECT_SESSIONS"/*.jsonl

# Extract entries with tool_use containing the target
jq -c 'select(.message.content[]?.type == "tool_use") |
       select(.message.content[].input | tostring | contains("SEARCH_TERM"))' \
  "$PROJECT_SESSIONS"/*.jsonl
SEARCH_EOF
```

### Step 3: Trace UUID Chain

Trace parentUuid chain backwards to find origin:

```bash
/usr/bin/env bash << 'TRACE_EOF'
trace_uuid_chain() {
  local uuid="$1"
  local session_file="$2"
  local depth=0
  local max_depth=100

  echo "Tracing UUID chain from: $uuid"

  while [[ -n "$uuid" && $depth -lt $max_depth ]]; do
    # Find entry with this UUID
    entry=$(jq -c "select(.uuid == \"$uuid\")" "$session_file" 2>/dev/null)

    if [[ -n "$entry" ]]; then
      parent=$(echo "$entry" | jq -r '.parentUuid // empty')
      timestamp=$(echo "$entry" | jq -r '.timestamp // empty')
      type=$(echo "$entry" | jq -r '.type // empty')

      echo "  [$depth] $uuid ($type) @ $timestamp"
      echo "       -> parent: $parent"

      uuid="$parent"
      ((depth++))
    else
      # UUID not in this session - search other sessions
      echo "  UUID $uuid not in current session, searching others..."
      found=false
      for session in "$PROJECT_SESSIONS"/*.jsonl; do
        if grep -q "\"uuid\":\"$uuid\"" "$session" 2>/dev/null; then
          session_file="$session"
          echo "  Found in $(basename "$session")"
          found=true
          break
        fi
      done
      [[ "$found" == "false" ]] && break
    fi
  done

  echo "Chain depth: $depth"
}
TRACE_EOF
```

### Step 4: Extract Edit Context

Extract the exact tool_use that created/modified the target:

```bash
/usr/bin/env bash << 'EXTRACT_EOF'
# Extract tool_use block with context (5 entries before and after)
jq -c 'select(.message.content[]?.type == "tool_use") |
       select(.message.content[].name == "Edit" or .message.content[].name == "Write")' \
  "$SESSION_FILE" | head -20
EXTRACT_EOF
```

---

## Part 3: Output Generation

### NDJSON Provenance Record Schema

Each provenance record in `provenance.jsonl`:

```json
{
  "id": "uuid-v4",
  "type": "finding|decision|contribution",
  "target": {
    "file": "path/to/file.py",
    "identifier": "minimal_3",
    "description": "3-feature baseline model"
  },
  "origin": {
    "session_id": "7380c12f-9c92-426f-9fe8-2c08705c81aa",
    "edit_uuid": "055fa4fe-b85d-4ff1-b337-f15b99d98eac",
    "parent_uuid": "da0ffa7d-7374-414f-8197-7b8bb3d10e52",
    "timestamp": "2026-01-01T01:48:27.634Z",
    "model": "claude-opus-4-5-20251101",
    "contributor": "claude"
  },
  "chain": {
    "sessions_traced": 3,
    "total_entries": 22456,
    "chain_depth": 15
  },
  "artifacts": {
    "session_context": "findings/provenance/session_context_<id>.jsonl.gz",
    "finding_doc": "findings/<name>.md"
  },
  "created_at": "2026-01-01T12:00:00Z"
}
```

### Compressed Session Context

Extract and compress relevant session entries:

```bash
/usr/bin/env bash << 'COMPRESS_EOF'
# Extract 100 entries before target, target entry, 10 after
CONTEXT_FILE="findings/provenance/session_context_${TARGET_ID}.jsonl"

head -n $((TARGET_LINE + 10)) "$SESSION_FILE" | tail -n 110 > "$CONTEXT_FILE"
gzip "$CONTEXT_FILE"

echo "Created: ${CONTEXT_FILE}.gz"
COMPRESS_EOF
```

### Markdown Finding Document Template

```markdown
# Finding: <title>

**Date**: YYYY-MM-DD
**Status**: VALIDATED
**ADR**: [link if applicable]

---

## Summary

<1-2 paragraph description of the finding>

---

## Provenance

| Field | Value |
|-------|-------|
| Session ID | `<session_id>` |
| Timestamp | `<timestamp>` |
| Model | `<model>` |
| Edit UUID | `<edit_uuid>` |
| Parent UUID | `<parent_uuid>` |

### Session Chain

| Session | Lines | Date Range |
|---------|-------|------------|
| <session_1> | <lines> | <start> - <end> |
| <session_2> | <lines> | <start> - <end> |

### Context

<Original Claude message before the edit>

---

## Artifacts

| File | Description |
|------|-------------|
| `provenance/session_context_<id>.jsonl.gz` | Compressed session excerpt |
| `provenance/<name>_edit_context.json` | Exact tool_use block |

---

## Reproduction

```bash
# Commands to reproduce or verify the finding
```

---

*Generated by session-chronicle skill*
```

### Git Commit Message Template

```
feat(finding): <short description>

Session-Chronicle Provenance:
  session_id: <session_id>
  edit_uuid: <edit_uuid>
  parent_uuid: <parent_uuid>
  timestamp: <timestamp>
  model: <model>
  sessions_traced: <count>
  chain_depth: <depth>

Artifacts:
  - findings/<name>.md
  - findings/provenance/session_context_<id>.jsonl.gz
  - findings/provenance/<name>_edit_context.json

Co-authored-by: Claude <noreply@anthropic.com>
```

---

## Part 4: Iterative Fallback

If initial search fails or is insufficient:

### Fallback A: Expand Search Scope

```
AskUserQuestion:
  question: "Search didn't find clear matches. How should we proceed?"
  header: "Fallback"
  multiSelect: false
  options:
    - label: "Expand to all sessions"
      description: "Search entire project history (may be slow)"
    - label: "Different search terms"
      description: "Let me provide alternative keywords"
    - label: "Specific session file"
      description: "I know which session file contains it"
    - label: "Date range narrowing"
      description: "I can narrow down when this was created"
```

### Fallback B: Manual Context

```
AskUserQuestion:
  question: "Please provide additional context for the search"
  header: "Context"
  multiSelect: true
  options:
    - label: "Approximate date"
      description: "When was this approximately created?"
    - label: "Related files"
      description: "What other files were involved?"
    - label: "Conversation topic"
      description: "What were we discussing when this was created?"
    - label: "Session UUID if known"
      description: "I have a specific session UUID to start from"
```

---

## Part 5: Workflow Summary

```
1. PREFLIGHT
   ├── Verify session storage location
   ├── Find current project sessions
   └── Check required tools (jq, gzip)

2. IDENTIFY TARGET
   └── AskUserQuestion: What to trace?

3. FULL PROJECT SCAN
   ├── Index all session files
   ├── Search for target across sessions
   └── Build session timeline

4. TRACE UUID CHAIN
   ├── Find target entry
   ├── Trace parentUuid backwards
   └── Cross-reference multiple sessions if needed

5. CONFIRM WITH USER
   └── AskUserQuestion: Which sessions to include?

6. GENERATE OUTPUTS
   ├── Append to provenance.jsonl
   ├── Create compressed session context
   ├── Generate markdown finding document
   └── Prepare git commit message

7. FALLBACK (if needed)
   └── AskUserQuestion: Provide more context
```

---

## References

- [Session Storage](/plugins/devops-tools/skills/session-recovery/SKILL.md)
- [NDJSON Specification](https://github.com/ndjson/ndjson-spec)
- [jq Manual](https://jqlang.github.io/jq/manual/)

---

## Success Criteria

1. **Complete chain traced** - All UUID links followed to origin
2. **Cross-session tracking** - Auto-compacted sessions handled
3. **Machine-readable output** - NDJSON provenance record created
4. **Human-readable output** - Markdown finding document generated
5. **Git-ready** - Commit message with full provenance prepared
6. **Reproducible** - Compressed context allows verification
