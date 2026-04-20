# chronicle-share

Producer-side session chronicle sharing pipeline.

**Status:** skeleton (scaffolded 2026-04-17). Not yet functional — see [CLAUDE.md](./CLAUDE.md) for the roadmap.

## Intent

Bundle Claude Code session JSONL files, sanitize secrets via the upstream `session-chronicle` sanitizer, upload the archive to Cloudflare R2 under my own account, and emit a 7-day presigned URL suitable for pasting into Telegram.

## Relationship to upstream

The upstream `devops-tools:session-chronicle` skill is **consumer-side** (authored by Terry, for downloading chronicles he publishes to `s3://eonlabs-findings`). This plugin is **producer-side** for my own chronicles. The two do not overlap; they share only the sanitizer script, which is invoked in-place from the installed upstream plugin (not copied).

## Docs

- [CLAUDE.md](./CLAUDE.md) — architecture, roadmap, conventions
- [skills/share/SKILL.md](./skills/share/SKILL.md) — the `/chronicle:share` entry point (stub)
