# Design Specifications Guide

Context for design specifications in cc-skills.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [docs/CLAUDE.md](../CLAUDE.md)

## Overview

Design specs are implementation specifications that pair with ADRs, though not 1:1 — 24 of 41 ADRs have one. Each spec lives in its own subdirectory. A spec is written when an implementation needs one; an ADR without a spec is the normal case, not a gap to fill.

## Directory Structure

One subdirectory per spec, named like its ADR (`YYYY-MM-DD-slug/spec.md`). `ls docs/design` is the list.

## ADR ↔ Design Relationship

Each design spec corresponds to an ADR in `../adr/`. Naming convention matches:

- ADR: `docs/adr/YYYY-MM-DD-slug.md`
- Design: `docs/design/YYYY-MM-DD-slug/`

## Categories

| Category       | Examples                                     |
| -------------- | -------------------------------------------- |
| ITP Workflow   | itp-setup, itp-todo, itp-hooks               |
| DevOps         | mise-env, clickhouse, mlflow                 |
| Hooks          | pretooluse, posttooluse, ruff, release-notes |
| Infrastructure | gitleaks, version-management                 |

## Link Conventions

| Target      | Format                      |
| ----------- | --------------------------- |
| ADRs        | `../adr/YYYY-MM-DD-slug.md` |
| Other specs | `./YYYY-MM-DD-slug/`        |
| Root        | `../../CLAUDE.md`           |
