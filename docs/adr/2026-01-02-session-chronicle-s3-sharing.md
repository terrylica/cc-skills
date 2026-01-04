---
status: accepted
date: 2026-01-02
decision-maker: Terry Li
consulted: [claude-code-guide, Explore]
research-method: single-agent
clarification-iterations: 2
perspectives: [OperationalService, ProviderToOtherComponents, SecurityBoundary]
---

# ADR: Session Chronicle S3 Artifact Sharing

**Design Spec**: [Implementation Spec](/docs/design/2026-01-02-session-chronicle-s3-sharing/spec.md)

## Context and Problem Statement

The `session-chronicle` skill excavates Claude Code session logs to capture complete provenance for research findings, ADR decisions, and code contributions. Currently, artifacts are stored locally with gzip compression. Coworkers cannot access these provenance artifacts without direct file sharing.

Key issues:

1. **No shared access**: Session artifacts are local-only, preventing team collaboration
2. **Suboptimal compression**: gzip provides lower compression ratios than modern alternatives
3. **No cross-reference**: Artifacts lack structured links to ADRs, design specs, and git commits
4. **Credential management**: No standardized approach for S3 access across team members

### Before/After

**Before**: Local-only artifacts with gzip compression

```
Before: Local-Only Session Artifacts

+---------------------+     +--------------------+     +---------------------+
|  session-chronicle  |     |  gzip compression  |     |  Local storage      |
|  traces UUID chain  | --> |  (.jsonl.gz)       | --> |  No team access     |
+---------------------+     +--------------------+     +---------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Before: Local-Only Session Artifacts"; flow: east; }

[trace] { label: "session-chronicle\\ntraces UUID chain"; }
[gzip] { label: "gzip compression\\n(.jsonl.gz)"; }
[local] { label: "Local storage\\nNo team access"; }

[trace] -> [gzip] -> [local]
```

</details>

**After**: S3-backed artifacts with Brotli compression and 1Password credentials

```
After: S3-Backed Artifact Sharing

+---------------------+     +--------------------+     +---------------------+
|  session-chronicle  |     |  Brotli compress   |     |  S3 upload with     |
|  traces UUID chain  | --> |  (.jsonl.br)       | --> |  1Password creds    |
+---------------------+     +--------------------+     +---------------------+
                                                                 |
                                                                 v
                                                       +---------------------+
                                                       |  Git commit embeds  |
                                                       |  S3 URIs + retrieval|
                                                       +---------------------+
                                                                 |
                                                                 v
                                                       +---------------------+
                                                       |  Coworkers download |
                                                       |  via 1Password+AWS  |
                                                       +---------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "After: S3-Backed Artifact Sharing"; flow: south; }

[trace] { label: "session-chronicle\\ntraces UUID chain"; }
[brotli] { label: "Brotli compress\\n(.jsonl.br)"; }
[s3] { label: "S3 upload with\\n1Password creds"; }
[commit] { label: "Git commit embeds\\nS3 URIs + retrieval"; }
[coworker] { label: "Coworkers download\\nvia 1Password+AWS"; }

[trace] -> [brotli] -> [s3]
[s3] -> [commit]
[commit] -> [coworker]
```

</details>

## Research Summary

| Agent Perspective | Key Finding                                                   | Confidence |
| ----------------- | ------------------------------------------------------------- | ---------- |
| Explore           | session-chronicle uses 7-phase workflow with gzip compression | High       |
| claude-code-guide | 1Password CLI supports credential injection via `op read`     | High       |

## Decision Log

| Decision Area     | Options Evaluated                    | Chosen        | Rationale                                                                   |
| ----------------- | ------------------------------------ | ------------- | --------------------------------------------------------------------------- |
| Compression       | gzip, zstd, Brotli                   | Brotli        | Better compression ratio, widely available via `brew install brotli`        |
| Credential source | AWS profiles, 1Password, Doppler     | 1Password     | Claude Automation vault already stores AWS credentials                      |
| URL format        | Presigned URLs, S3 URIs              | S3 URIs       | Avoids expiration issues; coworkers use 1Password directly                  |
| ADR linking       | Auto-create ADRs, Link existing only | Link existing | Prevents ADR proliferation; user specifies related ADR during CONFIRM phase |
| Upload trigger    | Manual, Automatic before commit      | Automatic     | Seamless integration with existing workflow                                 |

### Trade-offs Accepted

| Trade-off                 | Choice  | Accepted Cost                                                    |
| ------------------------- | ------- | ---------------------------------------------------------------- |
| Presigned URLs vs S3 URIs | S3 URIs | Requires 1Password + AWS CLI for access (no browser-only access) |
| gzip vs Brotli            | Brotli  | Additional tool dependency (`brew install brotli`)               |

## Decision Drivers

- Enable team collaboration on provenance artifacts
- Improve compression efficiency
- Leverage existing 1Password credential infrastructure
- Maintain complete cross-reference between artifacts, ADRs, and commits
- Minimize workflow disruption

## Considered Options

- **Option A**: Keep local-only storage (no sharing capability)
- **Option B**: Use DVC (Data Version Control) for artifact versioning
- **Option C**: Direct S3 upload with 1Password credentials (chosen)

## Decision Outcome

Chosen option: **Option C (Direct S3 upload with 1Password credentials)**, because:

1. DVC adds unnecessary complexity for simple artifact sharing
2. 1Password is already the credential SSoT for the engineering team
3. S3 URIs in git commits provide permanent, auditable references
4. Brotli compression reduces storage costs and transfer times

## Synthesis

**Convergent findings**: Both perspectives agreed on 1Password as credential source and the need for structured cross-references.

**Divergent findings**: Initial consideration of presigned URLs was rejected in favor of direct S3 URIs to avoid expiration issues.

**Resolution**: User chose "no presigned URLs" and "link to existing ADRs only" during clarification iterations.

## Consequences

### Positive

- Coworkers can access provenance artifacts via 1Password + AWS CLI
- Better compression with Brotli (~20-30% smaller than gzip)
- Complete cross-reference matrix between artifacts, ADRs, design specs, and git commits
- Retrieval command embedded in git commit messages

### Negative

- Requires brotli, aws, and op CLI tools installed
- Requires 1Password Claude Automation vault access
- No browser-only access (must use CLI)

## Architecture

```
Session Chronicle S3 Architecture

+---------------------------+
|     Claude Session        |
|     (.jsonl files)        |
+-------------+-------------+
              |
              v
+---------------------------+
|   extract_session_chain   |
|   (Brotli compression)    |
+-------------+-------------+
              |
              v
+---------------------------+
|      s3_upload.sh         |
|  (1Password credentials)  |
+-------------+-------------+
              |
              v
+---------------------------+
|   S3: eon-research-artifacts |
|   session-chronicle/<id>/    |
|   - manifest.json         |
|   - *.jsonl.br            |
+-------------+-------------+
              |
              v
+---------------------------+
|  generate_commit_message  |
|  (S3 URIs + retrieval)    |
+-------------+-------------+
              |
              v
+---------------------------+
|      Git Commit           |
|  Session-Chronicle-S3:    |
|  s3://bucket/prefix       |
+---------------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Session Chronicle S3 Architecture"; flow: south; }

[session] { label: "Claude Session\\n(.jsonl files)"; }
[extract] { label: "extract_session_chain\\n(Brotli compression)"; }
[upload] { label: "s3_upload.sh\\n(1Password credentials)"; }
[s3] { label: "S3: eon-research-artifacts\\nsession-chronicle/<id>/\\n- manifest.json\\n- *.jsonl.br"; }
[commit-gen] { label: "generate_commit_message\\n(S3 URIs + retrieval)"; }
[commit] { label: "Git Commit\\nSession-Chronicle-S3:\\ns3://bucket/prefix"; }

[session] -> [extract]
[extract] -> [upload]
[upload] -> [s3]
[s3] -> [commit-gen]
[commit-gen] -> [commit]
```

</details>

### Cross-Reference Matrix

| From             | To            | Link Format                     |
| ---------------- | ------------- | ------------------------------- |
| Git Commit       | S3 bucket     | `Session-Chronicle-S3:` trailer |
| Git Commit       | ADR           | `Related ADR:` line             |
| Git Commit       | Design Spec   | `Design Spec:` line             |
| Finding Doc      | S3 artifacts  | Artifacts section               |
| Finding Doc      | ADR           | YAML frontmatter + link         |
| provenance.jsonl | S3 artifacts  | `s3_artifacts` field            |
| S3 manifest.json | All artifacts | `related_documentation` field   |

## Implementation Files

| File                                 | Type   | Description                              |
| ------------------------------------ | ------ | ---------------------------------------- |
| `scripts/extract_session_chain.sh`   | Modify | gzip → Brotli compression                |
| `scripts/s3_upload.sh`               | Create | Upload with 1Password credentials        |
| `scripts/retrieve_artifact.sh`       | Create | Coworker download script                 |
| `scripts/generate_commit_message.sh` | Create | Commit message with S3 links             |
| `references/provenance-schema.json`  | Modify | Add `s3_artifacts`, `related_adr` fields |
| `references/s3-manifest-schema.json` | Create | S3 manifest schema                       |

## References

- [Session Chronicle SKILL.md](/plugins/devops-tools/skills/session-chronicle/SKILL.md)
- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [Brotli Compression](https://github.com/google/brotli)
- [AWS CLI S3 Commands](https://docs.aws.amazon.com/cli/latest/reference/s3/)
