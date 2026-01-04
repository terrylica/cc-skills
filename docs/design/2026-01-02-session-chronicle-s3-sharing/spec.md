---
adr: 2026-01-02-session-chronicle-s3-sharing
source: ~/.claude/plans/resilient-sleeping-pnueli.md
implementation-status: complete
s3_artifacts:
  bucket: s3://eonlabs-findings
  prefix: sessions/
  credential_source: 1Password Employee vault (2liqctzsbycqkodhf3vq5pnr3e)
---

# Design Spec: Session-Chronicle S3 Artifact Sharing

**ADR**: [Session Chronicle S3 Sharing ADR](/docs/adr/2026-01-02-session-chronicle-s3-sharing.md)

**Goal**: Enable coworkers to access session-chronicle artifacts via S3, with Brotli compression and 1Password credentials.

---

## Summary

Extend `session-chronicle` skill to:

1. Use **Brotli** compression (not gzip)
2. **Auto-upload** artifacts to S3 before git commit
3. Embed **S3 links in git commit message**
4. Cross-reference with **ADRs and design specs**
5. Enable coworker retrieval via 1Password credentials

---

## Prerequisites (Coworker Setup)

```bash
# Install tools
brew install brotli awscli 1password-cli

# Verify 1Password access
op signin
op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/access key id" >/dev/null && echo "OK"
```

---

## Implementation Steps

### Phase 1: ADR & Design Spec (Following /itp:go pattern)

| Task               | File                                                          |
| ------------------ | ------------------------------------------------------------- |
| Create ADR         | `docs/adr/2026-01-02-session-chronicle-s3-sharing.md`         |
| Create Design Spec | `docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md` |

### Phase 2: Update Compression (gzip → Brotli)

| Task                     | File                                                                                | Change                     |
| ------------------------ | ----------------------------------------------------------------------------------- | -------------------------- |
| Replace gzip with brotli | `plugins/devops-tools/skills/session-chronicle/scripts/extract_session_chain.sh:69` | `gzip -c` → `brotli -9 -o` |
| Update file extension    | Same file                                                                           | `.jsonl.gz` → `.jsonl.br`  |
| Add preflight check      | `plugins/devops-tools/skills/session-chronicle/SKILL.md`                            | Add brotli verification    |

### Phase 3: New Scripts

| Script                               | Purpose                             |
| ------------------------------------ | ----------------------------------- |
| `scripts/s3_upload.sh`               | Upload artifacts to S3              |
| `scripts/retrieve_artifact.sh`       | Coworker download & decompress      |
| `scripts/generate_commit_message.sh` | Create commit message with S3 links |

### Phase 4: Credential Access Pattern

**1Password item**: `2liqctzsbycqkodhf3vq5pnr3e` (Employee vault)

```bash
# Credential injection (in s3_upload.sh)
/usr/bin/env bash << 'CREDS_EOF'
export AWS_ACCESS_KEY_ID=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/access key id")
export AWS_SECRET_ACCESS_KEY=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/secret access key")
export AWS_DEFAULT_REGION="us-west-2"

aws s3 cp "$FILE" "s3://eonlabs-findings/$PATH"
CREDS_EOF
```

### Phase 5: Schema Extension

| File                                | Changes                                                  |
| ----------------------------------- | -------------------------------------------------------- |
| `references/provenance-schema.json` | Add `s3_artifacts`, `related_adr`, `related_design_spec` |

### Phase 6: SKILL.md Workflow Update

**Current workflow** (7 phases):

```
1. PREFLIGHT → 2. IDENTIFY → 3. SCAN → 4. TRACE → 5. CONFIRM → 6. GENERATE → 7. FALLBACK
```

**New workflow** (9 phases):

```
1. PREFLIGHT    → Add: verify brotli, aws, op
2. IDENTIFY     → (unchanged)
3. SCAN         → (unchanged)
4. TRACE        → (unchanged)
5. CONFIRM      → (unchanged)
6. GENERATE     → Change: Brotli compression
7. S3 UPLOAD    → NEW: Upload to S3
8. GIT COMMIT   → NEW: Embed S3 links in commit message
9. FALLBACK     → (unchanged)
```

### Phase 7: Git Commit Message Format

**No presigned URLs** - Coworkers use 1Password + AWS CLI directly.

```
feat(provenance): <description>

Session-Chronicle Provenance:
  session_id: <uuid>
  edit_uuid: <uuid>
  ...

Artifacts (S3):
  bucket: s3://eonlabs-findings/sessions/<id>
  files:
    - manifest.json
    - <session_1>.jsonl.br
    - <session_2>.jsonl.br

Related ADR: <existing-adr-slug-if-applicable>
Design Spec: /docs/design/<adr-slug>/spec.md

Retrieval (requires 1Password Employee vault access):
  /usr/bin/env bash << 'RETRIEVE_EOF'
  export AWS_ACCESS_KEY_ID=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/access key id")
  export AWS_SECRET_ACCESS_KEY=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/secret access key")
  export AWS_DEFAULT_REGION="us-west-2"
  aws s3 sync s3://eonlabs-findings/sessions/<id>/ ./artifacts/
  RETRIEVE_EOF

Session-Chronicle-S3: s3://eonlabs-findings/sessions/<id>
```

**ADR Linking**: Link to existing ADRs only (no auto-creation). User specifies which ADR relates to the finding during the CONFIRM phase.

---

## Complete Cross-Reference Matrix

### All Document ↔ S3 ↔ Git Linkages

| From                 | To                 | Link Format                         | Example                                                                    |
| -------------------- | ------------------ | ----------------------------------- | -------------------------------------------------------------------------- |
| **Git Commit**       | S3 bucket          | `Session-Chronicle-S3:` trailer     | `Session-Chronicle-S3: s3://eonlabs-findings/sessions/<id>` |
| **Git Commit**       | ADR                | `Related ADR:` line                 | `Related ADR: 2025-12-15-finding-name`                                     |
| **Git Commit**       | Design Spec        | `Design Spec:` line                 | `Design Spec: /docs/design/2025-12-15-finding-name/spec.md`                |
| **Finding Doc**      | S3 artifacts       | Artifacts section                   | `s3://eonlabs-findings/sessions/<id>/manifest.json`         |
| **Finding Doc**      | ADR                | YAML frontmatter + link             | `ADR: [Title](/docs/adr/YYYY-MM-DD-slug.md)`                               |
| **Finding Doc**      | Design Spec        | YAML frontmatter + link             | `Design Spec: [Title](/docs/design/YYYY-MM-DD-slug/spec.md)`               |
| **Finding Doc**      | Git Commit         | Provenance table                    | `Git Commit: <sha>`                                                        |
| **provenance.jsonl** | S3 artifacts       | `s3_artifacts` field                | `"s3_location": "s3://..."`                                                |
| **provenance.jsonl** | Git Commit         | `git_commit` field                  | `"git_commit": "<sha>"`                                                    |
| **provenance.jsonl** | ADR                | `related_adr` field                 | `"related_adr": "2025-12-15-slug"`                                         |
| **ADR**              | Design Spec        | Related links section               | `- [Design Spec](/docs/design/YYYY-MM-DD-slug/spec.md)`                    |
| **ADR**              | Related Findings   | Related links section               | `- [Finding](/findings/finding-name.md)`                                   |
| **Design Spec**      | ADR                | YAML frontmatter                    | `adr: 2025-12-15-slug`                                                     |
| **Design Spec**      | S3 artifacts       | Implementation artifacts section    | `S3 Location: s3://eonlabs-findings/...`                             |
| **Design Spec**      | Source Plan        | YAML frontmatter                    | `source: ~/.claude/plans/xxx.md`                                           |
| **SKILL.md**         | Implementation ADR | References section                  | `- [S3 Sharing ADR](/docs/adr/2026-01-02-session-chronicle-s3-sharing.md)` |
| **S3 manifest.json** | Finding doc        | `finding.local_path` field          | `"local_path": "findings/finding-name.md"`                                 |
| **S3 manifest.json** | ADR                | `related_documentation.adr`         | `"adr": {"id": "2025-12-15-slug", "path": "/docs/adr/..."}`                |
| **S3 manifest.json** | Design Spec        | `related_documentation.design_spec` | `"design_spec": {"path": "/docs/design/..."}`                              |
| **S3 manifest.json** | Git Commit         | `finding.git_commit`                | `"git_commit": "<sha>"`                                                    |

### Visual Cross-Reference Diagram

```
                         ┌──────────────────────────────────────────────────────────────────┐
                         │                        GIT COMMIT                                │
                         │  - Session-Chronicle-S3: s3://...                                │
                         │  - Related ADR: YYYY-MM-DD-slug                                  │
                         │  - Design Spec: /docs/design/.../spec.md                         │
                         │  - Retrieval command (embedded)                                  │
                         └───────────────────────────┬──────────────────────────────────────┘
                                                     │
          ┌──────────────────────────────────────────┼──────────────────────────────────────┐
          │                                          │                                      │
          ▼                                          ▼                                      ▼
┌─────────────────────────┐              ┌─────────────────────────┐            ┌─────────────────────────┐
│   ADR (docs/adr/)       │◄────────────►│   DESIGN SPEC           │◄──────────►│   S3 ARTIFACTS          │
│                         │              │   (docs/design/)        │            │   (s3://bucket/...)     │
│ - Status, Decision      │              │                         │            │                         │
│ - Design spec link      │              │ - ADR backlink          │            │ - manifest.json         │
│ - Related findings      │              │ - Source plan           │            │ - *.jsonl.br files      │
│ - S3 artifacts (if any) │              │ - S3 artifacts section  │            │ - uuid_chain.jsonl      │
└─────────────────────────┘              └─────────────────────────┘            └─────────────────────────┘
          │                                          │                                      │
          │                                          │                                      │
          ▼                                          ▼                                      ▼
┌─────────────────────────┐              ┌─────────────────────────┐            ┌─────────────────────────┐
│   FINDING DOC           │◄────────────►│   provenance.jsonl      │◄──────────►│   S3 manifest.json      │
│   (findings/*.md)       │              │   (repo root)           │            │   (in S3 bucket)        │
│                         │              │                         │            │                         │
│ - ADR reference         │              │ - s3_artifacts field    │            │ - finding.local_path    │
│ - Design spec link      │              │ - git_commit field      │            │ - related_documentation │
│ - S3 artifacts section  │              │ - related_adr field     │            │ - artifacts list        │
│ - Git commit SHA        │              │ - session chain         │            │ - provenance metadata   │
│ - Retrieval command     │              │                         │            │ - retrieval commands    │
└─────────────────────────┘              └─────────────────────────┘            └─────────────────────────┘
          │                                                                                 │
          │                                                                                 │
          ▼                                                                                 ▼
┌─────────────────────────┐                                                     ┌─────────────────────────┐
│   SKILL.md              │                                                     │   README.md             │
│   (session-chronicle)   │                                                     │   (devops-tools)        │
│                         │                                                     │                         │
│ - References section    │                                                     │ - S3 sharing mention    │
│   with ADR link         │                                                     │ - 1Password credential  │
│                         │                                                     │   reference             │
└─────────────────────────┘                                                     └─────────────────────────┘
```

---

## Files to Modify (Complete List)

### Core Implementation

| File                                                                               | Type   | Description                                                |
| ---------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------- |
| `plugins/devops-tools/skills/session-chronicle/SKILL.md`                           | Modify | Add S3 upload phase, preflight checks                      |
| `plugins/devops-tools/skills/session-chronicle/scripts/extract_session_chain.sh`   | Modify | Replace gzip with brotli, change `.gz` to `.br`            |
| `plugins/devops-tools/skills/session-chronicle/scripts/s3_upload.sh`               | Create | Upload artifacts to S3 with 1Password credential injection |
| `plugins/devops-tools/skills/session-chronicle/scripts/retrieve_artifact.sh`       | Create | Coworker download and decompress script                    |
| `plugins/devops-tools/skills/session-chronicle/scripts/generate_commit_message.sh` | Create | Generate commit message with S3 links                      |

### Schemas

| File                                                                               | Type   | Description                                                     |
| ---------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------- |
| `plugins/devops-tools/skills/session-chronicle/references/provenance-schema.json`  | Modify | Add `s3_artifacts`, `related_adr`, `related_design_spec` fields |
| `plugins/devops-tools/skills/session-chronicle/references/s3-manifest-schema.json` | Create | Schema for S3 manifest with full cross-reference structure      |

### Documentation

| File                                                                             | Type   | Description                                         |
| -------------------------------------------------------------------------------- | ------ | --------------------------------------------------- |
| `plugins/devops-tools/skills/session-chronicle/references/s3-retrieval-guide.md` | Create | Coworker instructions for downloading/decompressing |
| `plugins/devops-tools/README.md`                                                 | Modify | Add S3 sharing capability description               |

### Test Fixtures & Validation Scripts

| File                                                                                        | Type   | Description                          |
| ------------------------------------------------------------------------------------------- | ------ | ------------------------------------ |
| `plugins/devops-tools/skills/session-chronicle/tests/fixtures/mock-session.jsonl`           | Create | Synthetic session for testing        |
| `plugins/devops-tools/skills/session-chronicle/tests/fixtures/mock-uuid-chain.jsonl`        | Create | Pre-traced UUID chain                |
| `plugins/devops-tools/skills/session-chronicle/tests/fixtures/expected-manifest.json`       | Create | Expected manifest output             |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-prerequisites.sh`     | Create | Tool installation check              |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-brotli.sh`            | Create | Compression round-trip test          |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-credential-access.sh` | Create | 1Password access test                |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-s3-upload.sh`         | Create | S3 connectivity test                 |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-extract-chain.sh`     | Create | Script modification check            |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-commit-format.sh`     | Create | Commit message format check          |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-e2e.sh`               | Create | Master validation runner             |
| `plugins/devops-tools/skills/session-chronicle/tests/scripts/validate-cross-references.sh`  | Create | Cross-reference integrity validation |
| `plugins/devops-tools/skills/session-chronicle/tests/README.md`                             | Create | Test documentation                   |

**Total: 23 files** (5 modify, 18 create)

---

## Coworker Retrieval Workflow

**Requires**: 1Password Employee vault access

```bash
# Download and decompress artifacts
/usr/bin/env bash << 'RETRIEVE_EOF'
export AWS_ACCESS_KEY_ID=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/access key id")
export AWS_SECRET_ACCESS_KEY=$(op read "op://Employee/2liqctzsbycqkodhf3vq5pnr3e/secret access key")
export AWS_DEFAULT_REGION="us-west-2"

# Sync all artifacts
aws s3 sync s3://eonlabs-findings/sessions/<id>/ ./artifacts/

# Decompress Brotli files
for f in ./artifacts/*.br; do brotli -d "$f"; done
RETRIEVE_EOF
```

**Alternative**: Use the retrieval script

```bash
./scripts/retrieve_artifact.sh s3://eonlabs-findings/sessions/<id>/ ./artifacts
```

---

## Validation Checklist

> **Audit Report**: [AUDIT-REPORT-2026-01-02.md](/plugins/devops-tools/skills/session-chronicle/tests/AUDIT-REPORT-2026-01-02.md)

- [x] `brotli` installed and working — `brotli 1.2.0` (validate-prerequisites.sh)
- [x] `aws` CLI installed — `aws-cli/2.32.26` (validate-prerequisites.sh)
- [x] `op` (1Password CLI) signed in — `op 2.32.0` (validate-credential-access.sh)
- [x] Employee vault accessible — AWS keys retrieved (validate-credential-access.sh)
- [x] S3 bucket writable — Upload to `s3://eonlabs-findings` succeeded (validate-s3-upload.sh)
- [x] Git commit includes S3 URIs (not presigned URLs) — Commit 34f0082 (validate-commit-format.sh)
- [x] Existing ADR cross-referenced in commit (if applicable) — `ADR: 2026-01-02-session-chronicle-s3-sharing`
- [x] Retrieval command in commit message works — E2E test verified (retrieve_artifact.sh)

---

## S3 Bucket Details

| Field          | Value                        |
| -------------- | ---------------------------- |
| Bucket         | `s3://eonlabs-findings`      |
| Region         | `us-west-2`                  |
| Account        | `050214414362`               |
| 1Password Item | `2liqctzsbycqkodhf3vq5pnr3e` |
| Prefix         | `sessions/`                  |

---

## Schema Definitions

### provenance.jsonl Schema Extension

Add to `references/provenance-schema.json`:

```json
{
  "s3_artifacts": {
    "type": "object",
    "description": "S3 storage details for large artifacts",
    "properties": {
      "bucket": { "type": "string" },
      "prefix": { "type": "string" },
      "manifest_key": { "type": "string" },
      "uploaded_at": { "type": "string", "format": "date-time" },
      "files": {
        "type": "array",
        "items": { "type": "string" }
      }
    }
  },
  "related_adr": {
    "type": "string",
    "description": "ADR slug if this finding relates to a decision (YYYY-MM-DD-slug format)"
  },
  "related_design_spec": {
    "type": "string",
    "description": "Path to related design spec (/docs/design/.../spec.md)"
  }
}
```

### S3 manifest.json Schema

Create `references/s3-manifest-schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "S3 Session Chronicle Manifest",
  "type": "object",
  "required": [
    "version",
    "session_id",
    "created_at",
    "bucket",
    "prefix",
    "artifacts"
  ],
  "properties": {
    "version": { "type": "string", "const": "1.0.0" },
    "session_id": { "type": "string", "format": "uuid" },
    "created_at": { "type": "string", "format": "date-time" },
    "bucket": { "type": "string" },
    "prefix": { "type": "string" },
    "finding": {
      "type": "object",
      "properties": {
        "id": { "type": "string" },
        "title": { "type": "string" },
        "local_path": { "type": "string" },
        "git_commit": { "type": "string" }
      }
    },
    "related_documentation": {
      "type": "object",
      "properties": {
        "adr": {
          "type": "object",
          "properties": {
            "id": { "type": "string" },
            "path": { "type": "string" },
            "title": { "type": "string" }
          }
        },
        "design_spec": {
          "type": "object",
          "properties": {
            "path": { "type": "string" },
            "title": { "type": "string" }
          }
        }
      }
    },
    "artifacts": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "key": { "type": "string" },
          "size_bytes": { "type": "integer" },
          "checksum_sha256": { "type": "string" },
          "description": { "type": "string" }
        }
      }
    },
    "provenance": {
      "type": "object",
      "properties": {
        "edit_uuid": { "type": "string" },
        "parent_uuid": { "type": "string" },
        "timestamp": { "type": "string" },
        "model": { "type": "string" },
        "contributor": { "type": "string" }
      }
    },
    "retrieval": {
      "type": "object",
      "properties": {
        "aws_cli": { "type": "string" },
        "credential_source": { "type": "string" }
      }
    }
  }
}
```
