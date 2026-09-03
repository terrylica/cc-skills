# Documentation Guide

Context for working with cc-skills documentation.

**Hub**: [Root CLAUDE.md](../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../plugins/CLAUDE.md)

## Directory Structure

```
docs/
├── adr/                    ← Architecture Decision Records (MADR 4.0)
├── design/                 ← Implementation specifications (33 of 58 ADRs have one)
├── troubleshooting/        ← Issue resolution guides
├── HOOKS.md                ← Hook development guide
├── RELEASE.md              ← Release workflow guide
└── plugin-authoring.md     ← Shell compatibility patterns
```

## ADR Conventions

**Naming**: `YYYY-MM-DD-slug.md` (no sequential numbers)

**Format**: [MADR 4.0](https://github.com/adr/madr)

**Creation**: ADRs are created automatically by `/itp:go` preflight phase.

## Design Specs

**Location**: `docs/design/YYYY-MM-DD-slug/spec.md`

**Relationship**: partial, not 1:1 — 33 of 58 ADRs have a design spec. The shortfall is structural rather than a backlog: `/itp:go` preflight creates an ADR automatically for every change, while a design spec is written only when an implementation needs one. Do not read a missing spec as an omission to fix.

**Content**: Implementation details, code snippets, file modifications.

## Spoke Documents

| Document                                                                   | Purpose                         |
| -------------------------------------------------------------------------- | ------------------------------- |
| [HOOKS.md](./HOOKS.md)                                                     | Hook development patterns       |
| [RELEASE.md](./RELEASE.md)                                                 | Release workflow (moon tasks)   |
| [PLUGIN-LIFECYCLE.md](./PLUGIN-LIFECYCLE.md)                               | Plugin internals & config       |
| [cargo-tty-suspension-prevention.md](./cargo-tty-suspension-prevention.md) | Cargo TTY fix (PUEUE isolation) |
| [LESSONS.md](./LESSONS.md)                                                 | Lessons learned (extracted)     |
| [plugin-authoring.md](./plugin-authoring.md)                               | Shell compatibility             |
| [pii-staged-content-guard.md](./pii-staged-content-guard.md)               | Pre-commit PII guard            |
| [troubleshooting/](./troubleshooting/)                                     | Issue resolution                |

## Link Conventions

When linking from docs:

| Target     | Format                               |
| ---------- | ------------------------------------ |
| Other docs | Relative (`./adr/file.md`)           |
| Plugins    | Repo-root (`/plugins/itp/README.md`) |
| External   | Full URL                             |

## Terminology Enforcement

CLAUDE.md files are linted for consistent terminology via Vale hooks:

- **SSoT**: `~/.claude/docs/GLOSSARY.md` (canonical term definitions)
- **Hook chain**: PreToolUse rejects edits with violations; PostToolUse shows informational warnings
- **Configuration**: `~/.claude/.vale.ini` (global) or per-project `.vale.ini`

Full details: [itp-hooks CLAUDE.md](../plugins/itp-hooks/docs/vale-terminology-enforcement.md)

## Toolchain

**Bun-first** for JavaScript globals. See [Root CLAUDE.md](../CLAUDE.md#development-toolchain).
