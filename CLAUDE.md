# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Claude Code skills marketplace: 15 plugins with 39 skills for ADR-driven development workflows.

**Key Documentation**:

- [README.md](./README.md) - Installation, plugins, terminology
- [plugins/itp/README.md](./plugins/itp/README.md) - Core /itp:go workflow
- `docs/adr/` - Architecture Decision Records (MADR 4.0)
- `docs/design/` - Implementation specifications (1:1 with ADRs)

## Essential Commands

| Task                 | Command                   |
| -------------------- | ------------------------- |
| Release (dry-run)    | `npm run release:dry`     |
| Release (production) | `npm run release`         |
| Format files         | `prettier --write .`      |
| Execute workflow     | `/itp:go feature-name -b` |
| Setup environment    | `/itp:setup`              |
| Manage hooks         | `/itp:hooks install`      |

## Architecture

**Directory Structure**:

- `plugins/` - 15 marketplace plugins (each with skills/, README.md)
- `docs/adr/` - ADRs with `YYYY-MM-DD-slug.md` naming
- `docs/design/` - Design specs mirroring ADR structure

**Core Plugin**: `plugins/itp/` - 4-phase ADR-driven workflow:

1. Preflight: Create ADR + design spec
2. Phase 1: Implementation
3. Phase 2: Format + push
4. Phase 3: Release

## Development Patterns

**Workflow**: All features use `/itp:go` which creates ADR in `docs/adr/` and spec in `docs/design/`.

**Link Conventions**: Marketplace plugins use **relative paths** (`./`, `../`) - absolute paths break when installed to `~/.claude/skills/`.

**Release**: Semantic-release with conventional commits. ALL commit types trigger patch releases (marketplace constraint).

## Key Files

| File                         | Purpose                            |
| ---------------------------- | ---------------------------------- |
| `plugin.json`                | Root plugin manifest               |
| `.releaserc.yml`             | Semantic-release config            |
| `plugins/itp/commands/go.md` | Core workflow definition           |
| `plugins/itp-hooks/hooks/`   | PreToolUse/PostToolUse enforcement |
