# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-06-05: Add write — `create-doc` (native Google Docs) + rate-limit backoff

**Trigger**: Real task needed to publish a team document to Drive as a _native_ Google Doc (so the team can
comment inline), and a burst of writes hit **HTTP 403 `rateLimitExceeded`**. The skill was read-only
(list/search/info/download/sync) with no create path, and rclone's `--drive-import-formats` was unreliable
for native-Doc conversion on the target remote.

**What changed**:

- **New `create-doc` command** (`cli.ts` + `createDoc()` in `lib/drive.ts`): converts a local HTML/`.docx`
  source into a native Google Doc via `files.create` (target mimeType in metadata + source as media, the
  multipart-conversion pattern — confirmed against Google's docs as the recommended approach). `--update`
  overwrites an existing Doc in place.
- **`withBackoff()` retry wrapper** (`lib/drive.ts`), now wrapping every Drive call (list/search/info +
  create): exponential backoff + jitter on 403 rateLimitExceeded/userRateLimitExceeded and 429,
  `min(2^n·1000 + rand, 64s)`, finite ceiling, non-rate-limit errors rethrow loud. Matches Google's
  official guidance (handle-errors guide).
- **OAuth scope** (`lib/config.ts`): added least-privilege `drive.file` next to `drive.readonly` so writes
  work; first write re-prompts for consent (documented; same pattern as gmail-commander adding
  `gmail.compose`).
- **SKILL.md**: new "Creating a native Google Doc (write)" + "Rate limits & retries" sections.
- Fixed pre-existing biome nits surfaced on the touched files (parseInt radix, `import type`).

**Why update this skill (not a new plugin)**: gdrive-access is the natural home for Drive read+write, and a
sibling plugin (gmail-commander) already shows one plugin doing both read and write for a Google service.

**Files**: `scripts/cli.ts`, `scripts/lib/drive.ts`, `scripts/lib/config.ts`, `SKILL.md`,
`references/evolution-log.md`. Rebuild the binary with `bun run build`.

**Evidence**: the same `files.create`/multipart pattern (prototyped via the rclone OAuth token) produced a
verified native Doc (`application/vnd.google-apps.document` + `docs.google.com/document/...` link); the
binary compiles (`bun build`) and `gdrive --help` lists `create-doc`.

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
