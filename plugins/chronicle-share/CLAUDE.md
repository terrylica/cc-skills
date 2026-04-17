# chronicle-share Plugin

> Producer-side session chronicle sharing pipeline. Bundles Claude Code JSONL, sanitizes, uploads to Cloudflare R2, emits a 7-day presigned URL.

**Status:** skeleton. Scaffolded 2026-04-17. Nothing runs yet; this commit establishes the plugin folder only.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why this exists

Terry (supervisor) needs a reliable way to receive my session chronicles for review. Manual zip-and-upload is too slow; automated pipeline was requested in Bruntwork Assignments topic on 2026-04-16. The existing `devops-tools:session-chronicle` skill ships chronicles into `s3://example-findings-bucket` (Terry's bucket, credentials in shared 1Password vault); I have read access there but not write. This plugin is my own producer-side pipeline into R2.

## Target architecture

```
1. Bundle      bun script enumerates ~/.claude/projects/<encoded-cwd>/ JSONL files,
               tars them into a staging dir.
                         │
                         ▼
2. Sanitize    Shell out to the upstream sanitizer:
               ~/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/
                 skills/session-chronicle/scripts/sanitize_sessions.py
               — never skipped, never re-implemented locally.
                         │
                         ▼
3. Compress    Brotli-9 the sanitized files, zip into a single archive.
                         │
                         ▼
4. Upload      aws s3 cp / aws s3api put-object against the R2 endpoint
               (R2 speaks S3-compat API). Credentials loaded from 1Password.
                         │
                         ▼
5. Presign     aws s3 presign --expires-in 604800 (7 days).
                         │
                         ▼
6. Emit        Print the URL to stdout. Optionally pipe to tlg:send-media
               for direct posting into the Bruntwork Assignments topic.
```

## Key design decisions (to be formalized)

| Decision | Choice | Rationale |
| --- | --- | --- |
| Storage | Cloudflare R2 | Free tier (10 GB), no egress fees, S3-compat API. Confirmed by Terry as recommended. |
| Sanitizer | Shell out to upstream | Single source of truth; never drifts when Terry updates the patterns. |
| Compression | Brotli | Matches upstream pipeline convention. |
| URL format | Presigned, 7-day expiry | Matches Terry's own pipeline's `X-Amz-Expires=604800`. |
| Credentials | 1Password (separate item from Terry's) | Isolation: my R2 creds are mine, not the company's. |
| Telegram post | Delegated to `tlg:send-media` | Uses existing Telethon personal-account session; no new bot infra. |

## Not yet implemented

- [ ] R2 account + bucket + API token provisioning (one-time, manual)
- [ ] 1Password item for R2 credentials (one-time, manual)
- [ ] `scripts/bundle.ts` — enumerate + tar session JSONL
- [ ] `scripts/upload.sh` — aws s3 cp against R2 endpoint
- [ ] `scripts/presign.sh` — aws s3 presign, 7-day expiry
- [ ] `skills/share/SKILL.md` — full workflow (currently a stub)
- [ ] `/chronicle:share` slash command wrapper (requires appending to `.mise.toml` `[task_config].includes` — **not yet done** because editing upstream-owned files needs Nasim's explicit sign-off per the fork rule)
- [ ] `/chronicle:doctor` + `/chronicle:check-full` (required by Eon cross-repo pattern)
- [ ] ADR + design spec in `docs/adr/` + `docs/design/` (also deferred pending rule clarification)

## Boundary with upstream cc-skills

Per the memory rule set 2026-04-17: in this fork, Claude only adds new content authored by Nasim. Registration into upstream-owned registry files (`.claude-plugin/marketplace.json`, `.mise.toml`) is intentionally **not** done in the scaffolding commit — to be addressed as a separate, explicit step.

## References

- Upstream consumer-side skill: `plugins/devops-tools/skills/session-chronicle/SKILL.md`
- Upstream sanitizer: `plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py`
- Upstream S3 sharing ADR (opposite direction, for reference only): `docs/adr/2026-01-02-session-chronicle-s3-sharing.md`
- Telegram posting skill: `plugins/tlg/skills/send-media/SKILL.md`
