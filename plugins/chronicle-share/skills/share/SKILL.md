---
name: share
description: "STUB — bundle, sanitize, upload Claude Code sessions to Cloudflare R2, emit 7-day presigned URL. TRIGGERS - share my chronicle, upload sessions, chronicle share, send chronicle to supervisor"
allowed-tools: Bash, Read, AskUserQuestion
---

# chronicle:share (stub)

**Status:** stub. This skill is scaffolded but not functional. Target workflow documented below; implementation is pending.

## Planned workflow

1. **Preflight** — verify `brotli`, `aws`, `op`, `bun` installed; verify R2 bucket reachable; verify 1Password access.
2. **Bundle** — run `scripts/bundle.sh` to enumerate session JSONL under `~/.claude/projects/<encoded-cwd>/` and stage them with a manifest. See [Plugin CLAUDE.md](../../CLAUDE.md#phase-1-bundle--implemented) for the CLI and manifest schema.
3. **Sanitize** — shell out to upstream sanitizer. Never skip, never re-implement:

   ```bash
   SKILL_DIR="$(find $HOME/.claude/plugins/marketplaces/cc-skills -type d -name session-chronicle | head -1)"
   "$SKILL_DIR/scripts/sanitize_sessions.py" \
     --input  /path/to/staging-raw \
     --output /path/to/staging-sanitized \
     --report /path/to/redaction_report.txt
   ```

4. **Compress** — Brotli-9 sanitized files.
5. **Upload** — `aws s3 cp` to R2 endpoint, credentials from 1Password.
6. **Presign** — `aws s3 presign --expires-in 604800` (7 days, matches Terry's own pipeline).
7. **Emit** — print URL; optionally pipe to `tlg:send-media` for direct Telegram posting.

## Plugin docs

[Plugin CLAUDE.md](../../CLAUDE.md) — architecture, roadmap, boundary with upstream cc-skills.
