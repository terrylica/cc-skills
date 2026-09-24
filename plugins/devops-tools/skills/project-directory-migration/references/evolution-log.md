# project-directory-migration Evolution Log

Reverse-chronological log of skill improvements.

---

## 2026-09-24: Phase 8 no longer runs `mise trust`

mise is retired. The script still detects `.mise.toml` / `.mise.local.toml`, but now only warns that the config is dead and should move to `.prototools` and `moon.yml`; it never invokes mise.

---

## 2026-02-09: Initial skill creation

**Source**: Empirical validation during CKVD package rename (data-source-manager → crypto-kline-vision-data)

**Validation data**: 33 sessions + 259 history entries migrated with zero data loss

**Features**:

- 9-phase migration script (pre-flight through post-flight)
- 4-phase AskUserQuestion interactive workflow
- Dry-run mode with session/history audit
- Timestamped backup with rollback support
- Backward-compatibility symlink
- Phase 8 environment fixups: mise trust, venv recreation, direnv/asdf warnings
- Session storage anatomy reference (empirically discovered)

**Bug caught during POC**: `originalPath` top-level field in `sessions-index.json` was initially missed — only `entries[].projectPath` and `entries[].fullPath` were being rewritten. Fixed before production run.

**Frontmatter**:

- `allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion`
- `TRIGGERS` keywords for Claude invocation matching
