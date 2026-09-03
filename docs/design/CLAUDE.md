# Design Specifications Guide

Context for design specifications in cc-skills.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [docs/CLAUDE.md](../CLAUDE.md)

## Overview

Design specs are implementation specifications that pair with ADRs, though not 1:1 — 33 of 58 ADRs have one. Each spec lives in its own subdirectory. A spec is written when an implementation needs one; an ADR without a spec is the normal case, not a gap to fill.

## Directory Structure

```
docs/design/
├── 2025-12-05-centralized-version-management/
├── 2025-12-05-itp-setup-todowrite-workflow/
├── 2025-12-05-itp-todo-insertion-merge/
├── 2025-12-06-pretooluse-posttooluse-hooks/
├── 2025-12-06-release-notes-adr-linking/
├── 2025-12-06-shell-command-portability-zsh/
├── 2025-12-07-gitleaks-setup-integration/
├── 2025-12-07-idempotency-backup-traceability/
├── 2025-12-07-itp-hooks-settings-installer/
├── 2025-12-07-setup-hooks-reminder/
├── 2025-12-08-clickhouse-cloud-management-skill/
├── 2025-12-08-mise-env-centralized-config/
├── 2025-12-08-mise-tasks-skill/
├── 2025-12-09-clickhouse-architect-skill/
├── 2025-12-09-clickhouse-pydantic-config-skill/
├── 2025-12-09-clickhouse-schema-documentation/
├── 2025-12-09-itp-hooks-plan-file-exemption/
├── 2025-12-09-itp-hooks-workflow-aware-graph-easy/
├── 2025-12-10-clickhouse-skill-delegation/
├── 2025-12-10-clickhouse-skill-documentation-gaps/
├── 2025-12-11-link-checker-plugin-extraction/
├── 2025-12-11-ruff-posttooluse-linting/
├── 2025-12-12-mlflow-python-skill/
├── 2025-12-14-alpha-forge-worktree-management/
├── 2025-12-15-iterm2-layout-config/
├── 2025-12-20-ralph-rssi-eternal-loop/
├── 2025-12-27-fake-data-guard-universal/
├── 2026-01-02-ralph-guidance-freshness-detection/
├── 2026-01-02-session-chronicle-s3-sharing/
├── 2026-01-10-uv-reminder-hook/
└── 2026-01-18-sred-dynamic-discovery/
```

## ADR ↔ Design Relationship

Each design spec corresponds to an ADR in `../adr/`. Naming convention matches:

- ADR: `docs/adr/YYYY-MM-DD-slug.md`
- Design: `docs/design/YYYY-MM-DD-slug/`

## Categories

| Category       | Examples                         |
| -------------- | -------------------------------- |
| ITP Workflow   | itp-setup, itp-todo, itp-hooks   |
| DevOps         | mise-tasks, mise-env, clickhouse |
| Hooks          | pretooluse, posttooluse, ruff    |
| Infrastructure | gitleaks, version-management     |

## Link Conventions

| Target      | Format                      |
| ----------- | --------------------------- |
| ADRs        | `../adr/YYYY-MM-DD-slug.md` |
| Other specs | `./YYYY-MM-DD-slug/`        |
| Root        | `../../CLAUDE.md`           |

## Toolchain

Spec creation uses Bun/Node.js. See [Root CLAUDE.md](../../CLAUDE.md#development-toolchain).
