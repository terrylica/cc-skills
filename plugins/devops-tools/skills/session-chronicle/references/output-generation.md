**Skill**: [Session Chronicle](../SKILL.md)

# Output Generation

Compression scripts and commit message templates for session archival.

---

## Compressed Session Context

For archival, compress sessions with Brotli:

```bash
/usr/bin/env bash << 'COMPRESS_EOF'
set -euo pipefail

# Validate required variables
if [[ -z "${TARGET_ID:-}" ]]; then
  echo "ERROR: TARGET_ID variable not set" >&2
  exit 1
fi

if [[ -z "${SESSION_LIST:-}" ]]; then
  echo "ERROR: SESSION_LIST variable not set" >&2
  exit 1
fi

if [[ -z "${PROJECT_SESSIONS:-}" ]]; then
  echo "ERROR: PROJECT_SESSIONS variable not set" >&2
  exit 1
fi

OUTPUT_DIR="outputs/research_sessions/${TARGET_ID}"
mkdir -p "$OUTPUT_DIR" || {
  echo "ERROR: Failed to create output directory: $OUTPUT_DIR" >&2
  exit 1
}
# NOTE: This directory is gitignored. Artifacts are preserved in S3, not git.

# Compress each session
ARCHIVED_COUNT=0
FAILED_COUNT=0

for session_id in $SESSION_LIST; do
  SESSION_PATH="$PROJECT_SESSIONS/${session_id}.jsonl"
  if [[ -f "$SESSION_PATH" ]]; then
    if brotli -9 -o "$OUTPUT_DIR/${session_id}.jsonl.br" "$SESSION_PATH"; then
      echo "✓ Archived: ${session_id}"
      ((ARCHIVED_COUNT++)) || true
    else
      echo "ERROR: Failed to compress ${session_id}" >&2
      ((FAILED_COUNT++)) || true
    fi
  else
    echo "WARNING: Session file not found: $SESSION_PATH" >&2
  fi
done

if [[ $ARCHIVED_COUNT -eq 0 ]]; then
  echo "ERROR: No sessions were archived" >&2
  exit 1
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
  echo "ERROR: $FAILED_COUNT session(s) failed to compress" >&2
  exit 1
fi

# Create manifest with proper JSON
cat > "$OUTPUT_DIR/manifest.json" << MANIFEST
{
  "target_id": "$TARGET_ID",
  "sessions_archived": $ARCHIVED_COUNT,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFEST

echo "✓ Archived $ARCHIVED_COUNT sessions to $OUTPUT_DIR"
COMPRESS_EOF
```

---

## Git Commit Message Template

```
feat(finding): <short description>

Session-Chronicle Provenance:
registry_id: <registry_id>
github_username: <github_username>
main_sessions: <count>
subagent_sessions: <count>
total_entries: <total>

Artifacts:
- findings/registry.jsonl
- findings/sessions/<id>/iterations.jsonl
- S3: s3://eonlabs-findings/sessions/<id>/

## S3 Artifact Retrieval

# Download compressed artifacts from S3
export AWS_ACCESS_KEY_ID=$(op read "op://Claude Automation/<chronicle-item>/access key id")
export AWS_SECRET_ACCESS_KEY=$(op read "op://Claude Automation/<chronicle-item>/secret access key")
export AWS_DEFAULT_REGION="us-west-2"
aws s3 sync s3://eonlabs-findings/sessions/<id>/ ./artifacts/
for f in ./artifacts/*.br; do brotli -d "$f"; done

Co-authored-by: Claude <noreply@anthropic.com>
```
