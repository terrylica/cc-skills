---
name: share
description: "STUB — bundle, sanitize, upload Claude Code sessions to Cloudflare R2, emit 7-day presigned URL. TRIGGERS - share my chronicle, upload sessions, chronicle share, send chronicle to supervisor"
allowed-tools: Bash, Read, AskUserQuestion
---

# chronicle:share (stub)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

**Status:** stub. This skill is scaffolded but not functional. Target workflow documented below; implementation is pending.

## Planned workflow

1. **Preflight** — verify `brotli`, `aws`, `op`, `bun` installed; verify R2 bucket reachable; verify 1Password access.
2. **Bundle** — run `scripts/bundle.sh` to enumerate session JSONL under `~/.claude/projects/<encoded-cwd>/` and stage them with a manifest. See [Plugin CLAUDE.md](../../CLAUDE.md#phase-1-bundle--implemented) for the CLI and manifest schema.
3. **Sanitize** — run `scripts/sanitize.sh <STAGING_DIR>`. Wraps the upstream `sanitize_sessions.py`, auto-discovers it, fingerprints it, mutates the manifest. See [Plugin CLAUDE.md](../../CLAUDE.md#phase-2-sanitize--implemented).

4. **Compress** — Brotli-9 sanitized files.
5. **Upload** — `aws s3 cp` to R2 endpoint, credentials from 1Password.
6. **Presign** — `aws s3 presign --expires-in 604800` (7 days, matches Terry's own pipeline).
7. **Emit** — print URL; optionally pipe to `tlg:send-media` for direct Telegram posting.

## Plugin docs

[Plugin CLAUDE.md](../../CLAUDE.md) — architecture, roadmap, boundary with upstream cc-skills.

## Post-Execution Reflection

After this skill completes (once it is no longer a stub), reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
