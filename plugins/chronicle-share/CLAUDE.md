# chronicle-share Plugin

> Producer-side session chronicle sharing pipeline. Bundles Claude Code JSONL, sanitizes, uploads to Cloudflare R2, emits a 7-day presigned URL.

**Status:** Phases 0 (R2 provisioning), 1 (bundle), 2 (sanitize) complete. Phases 3–8 pending.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why this exists

Terry (supervisor) needs a reliable way to receive my session chronicles for review. Manual zip-and-upload is too slow; automated pipeline was requested in Bruntwork Assignments topic on 2026-04-16. The existing `devops-tools:session-chronicle` skill ships chronicles into `s3://eonlabs-findings` (Terry's bucket, credentials in shared 1Password vault); I have read access there but not write. This plugin is my own producer-side pipeline into R2.

## Target architecture

```
1. Bundle      scripts/bundle.sh enumerates ~/.claude/projects/<encoded-cwd>/
               JSONL files into a staging dir + manifest.json.
                         │
                         ▼
2. Sanitize    Shell out to the upstream sanitizer:
               ~/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/
                 skills/session-chronicle/scripts/sanitize_sessions.py
               — never skipped, never re-implemented locally.
                         │
                         ▼
3. Archive     zip the sanitized sessions + manifest into a single .zip.
                         │
                         ▼
4. Upload      aws s3 cp against the R2 endpoint (S3-compat API).
               Credentials loaded from 1Password.
                         │
                         ▼
5. Presign     aws s3 presign --expires-in 604800 (7 days).
                         │
                         ▼
6. Emit        Print the URL to stdout. Optionally inline Telethon post
               into Bruntwork Assignments topic (nasim profile).
```

## Phase 1 (bundle) — implemented

**Script:** [`scripts/bundle.sh`](./scripts/bundle.sh)

### CLI surface
```
bundle.sh [--project PATH] [--out DIR] [--limit N]
```
- `--project`: project dir whose sessions to bundle (default: `$PWD`). Encoded per Claude Code's scheme (strip leading `/`, replace `/` and `.` with `-`, prepend `-`).
- `--out`: staging dir to create (default: `$TMPDIR/chronicle-share-<UTC>`). Must not exist (fail-safe).
- `--limit N`: bundle only the N newest sessions by mtime. `0` = all.

Stdout: the staging dir path. Stderr: all logs. Exit codes: `0` ok, `1` usage error, `2` no sessions.

### Staging layout
```
<OUT_DIR>/
├── manifest.json
└── sessions/
    └── <session-uuid>.jsonl   (one per session, newest first)
```

### Manifest schema (v1)
Downstream phases mutate this file in place. Single evolving record.

```jsonc
{
  "manifest_version": 1,
  "generated_at_utc": "2026-04-21T00:00:00Z",
  "generated_by": "chronicle-share/bundle.sh",
  "source": {
    "project_path":    "/Users/mdnasim/eon/cc-skills",
    "project_encoded": "-Users-mdnasim-eon-cc-skills",
    "host":            "MDs-MacBook-Pro",
    "claude_user":     "mdnasim"
  },
  "sessions": [
    {
      "session_id":  "<uuid>",
      "filename":    "<uuid>.jsonl",
      "size_bytes":  2570551,
      "line_count":  1793,
      "mtime_utc":   "2026-04-20T23:30:36Z",
      "sha256":      "b41fef...abf99"
    }
  ],
  "totals": {
    "session_count":    9,
    "total_size_bytes": 11532055
  },
  "sanitized": false,   // Phase 2 flips to true + adds redactions metadata
  "archived":  false    // Phase 3 flips to true + adds archive_path + archive_sha256
}
```

### Test coverage
15-case suite covers: `--help`, happy path, manifest shape, file count agreement, SHA-256 round-trip, `--limit 1` picks newest, explicit `--project`, nonexistent project (exit 1), missing session dir (exit 2), `--out` collision refused, `--limit 3` ordering, `--limit` clamping, `--limit 0 = all`, negative `--limit` rejected, unknown flag rejected. All pass as of 2026-04-21.

## Phase 2 (sanitize) — implemented

**Script:** [`scripts/sanitize.sh`](./scripts/sanitize.sh)

### CLI surface
```
sanitize.sh [--sanitizer PATH] STAGING_DIR
```
- Positional `STAGING_DIR`: the path returned by `bundle.sh` on stdout.
- `--sanitizer PATH`: override the auto-discovered upstream sanitizer. Auto-search order:
  1. `~/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py` (installed marketplace)
  2. `~/eon/cc-skills/plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py` (dev mirror)

Stdout: same `STAGING_DIR` (for chaining). Stderr: logs. Exit codes: `0` ok, `1` usage/validation, `2` sanitizer invocation failure.

### Key behaviors
- **Never re-implements redaction logic** — shells out to Terry's upstream `sanitize_sessions.py`; its SHA-256 is recorded in the manifest so consumers can detect script drift.
- **Idempotency guard** — refuses to run if `manifest.sanitized` is already `true`. Bundle a fresh staging dir to re-sanitize.
- **Non-destructive** — keeps raw `sessions/` intact; sanitized output goes to a **new** `sessions-sanitized/` sibling.
- **Output count check** — fails (exit 2) if the sanitizer's output file count diverges from the manifest's session count.
- **Dependency check** — fails fast if `uv`, `jq`, or `shasum` is missing.

### Post-Phase-2 staging layout
```
<STAGING>/
├── manifest.json              (mutated: sanitized=true + new fields)
├── sessions/                   (unchanged — forensic audit trail)
├── sessions-sanitized/         (new — redacted JSONL, Phase 3 will archive this)
└── redaction_report.txt        (new — human-readable report)
```

### Manifest v2 additions
Phase 2 flips `sanitized: true` and adds two new top-level objects plus three fields per session.

```jsonc
{
  // ... all Phase 1 fields unchanged ...
  "sanitized": true,                                        // was false
  "sessions": [
    {
      // ... all Phase 1 session fields unchanged ...
      "sanitized_size_bytes": 2103987,                      // NEW
      "sanitized_line_count": 1793,                         // NEW
      "sanitized_sha256":     "a0b1c2...deadbeef"           // NEW
    }
  ],
  "sanitization": {                                         // NEW
    "sanitized_at_utc": "2026-04-21T00:46:12Z",
    "sanitizer_path":   "/Users/mdnasim/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py",
    "sanitizer_sha256": "f6eda9be...06ff5c",                // fingerprint of the script used
    "report_path":      "<STAGING>/redaction_report.txt"
  },
  "redactions": {                                           // NEW
    "total": 272,
    "by_pattern": {
      "email_address":        110,
      "onepassword_item_id":   52,
      "onepassword_op_url":    48,
      "aws_access_key":        18,
      "tailscale_cgnat_ip":    17
      // ... other patterns that had non-zero counts ...
    }
  }
}
```

### Test coverage
14-case suite covers: `--help`, missing staging dir (exit 1), staging without manifest (exit 1), staging without sessions/ (exit 1), missing `STAGING_DIR` arg, happy path end-to-end, post-sanitize manifest schema, file count parity raw↔sanitized, sanitized SHA-256 round-trip + valid JSONL, idempotency guard (re-sanitize refused), **canary with 4 known secrets** (email / GitHub PAT / AWS key / JWT — all replaced with correct placeholders), bad `--sanitizer` path rejected, unknown flag rejected, two positional args rejected. All pass as of 2026-04-21.

## Key design decisions (to be formalized)

| Decision | Choice | Rationale |
| --- | --- | --- |
| Storage | Cloudflare R2 | Free tier (10 GB), no egress fees, S3-compat API. Confirmed by Terry as recommended. |
| Sanitizer | Shell out to upstream | Single source of truth; never drifts when Terry updates the patterns. |
| Compression | Brotli | Matches upstream pipeline convention. |
| URL format | Presigned, 7-day expiry | Matches Terry's own pipeline's `X-Amz-Expires=604800`. |
| Credentials | 1Password (separate item from Terry's) | Isolation: my R2 creds are mine, not the company's. |
| Telegram post | Delegated to `tlg:send-media` | Uses existing Telethon personal-account session; no new bot infra. |

## Roadmap

- [x] **Phase 0** — R2 account + bucket + API token + 1Password item (done 2026-04-21; verified via end-to-end presigned-URL download)
- [x] **Phase 1** — `scripts/bundle.sh` (done 2026-04-21; 15/15 tests pass)
- [x] **Phase 2** — `scripts/sanitize.sh` (done 2026-04-21; 14/14 tests pass including canary with 4 real-format secrets)
- [ ] **Phase 3** — `scripts/archive.sh` (zip staging into single `.zip`; add `archive_path` + `archive_sha256` to manifest)
- [ ] **Phase 4** — `scripts/upload.sh` (aws s3 cp + presign; add presigned URL + object key to manifest)
- [ ] **Phase 5** — `scripts/share.sh` (orchestrator chaining 1→4; first working end-to-end)
- [ ] **Phase 6** — inline Telethon post (nasim profile → Bruntwork topic 2)
- [ ] **Phase 7** — full `skills/share/SKILL.md` workflow + `skills/doctor/SKILL.md` preflight
- [ ] **Phase 8** — discoverability: user-global `~/.claude/commands/chronicle-share.md` OR marketplace.json registration (requires Nasim's explicit sign-off per fork rule)

## Boundary with upstream cc-skills

Per the memory rule set 2026-04-17: in this fork, Claude only adds new content authored by Nasim. Registration into upstream-owned registry files (`.claude-plugin/marketplace.json`, `.mise.toml`) is intentionally **not** done in the scaffolding commit — to be addressed as a separate, explicit step.

## References

- Upstream consumer-side skill: `plugins/devops-tools/skills/session-chronicle/SKILL.md`
- Upstream sanitizer: `plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py`
- Upstream S3 sharing ADR (opposite direction, for reference only): `docs/adr/2026-01-02-session-chronicle-s3-sharing.md`
- Telegram posting skill: `plugins/tlg/skills/send-media/SKILL.md`
