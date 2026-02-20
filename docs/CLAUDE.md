# Documentation Guide

Context for working with cc-skills documentation.

**Hub**: [Root CLAUDE.md](../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../plugins/CLAUDE.md)

## Directory Structure

```
docs/
├── adr/                    ← Architecture Decision Records (MADR 4.0)
├── design/                 ← Implementation specifications (1:1 with ADRs)
├── troubleshooting/        ← Issue resolution guides
├── HOOKS.md                ← Hook development guide
├── RELEASE.md              ← Release workflow guide
├── RESUME.md               ← Session resume context
└── plugin-authoring.md     ← Shell compatibility patterns
```

## ADR Conventions

**Naming**: `YYYY-MM-DD-slug.md` (no sequential numbers)

**Format**: [MADR 4.0](https://github.com/adr/madr)

**Creation**: ADRs are created automatically by `/itp:go` preflight phase.

**ASCII Diagrams**: Use `Skill(itp:adr-graph-easy-architect)` - never hand-draw.

## Design Specs

**Location**: `docs/design/YYYY-MM-DD-slug/spec.md`

**Relationship**: 1:1 with ADRs. Each ADR has a corresponding design spec.

**Content**: Implementation details, code snippets, file modifications.

## Spoke Documents

| Document                                     | Purpose                       |
| -------------------------------------------- | ----------------------------- |
| [HOOKS.md](./HOOKS.md)                       | Hook development patterns     |
| [RELEASE.md](./RELEASE.md)                   | Release workflow (mise tasks) |
| [PLUGIN-LIFECYCLE.md](./PLUGIN-LIFECYCLE.md) | Plugin internals & config     |
| [RESUME.md](./RESUME.md)                     | Session resume context        |
| [plugin-authoring.md](./plugin-authoring.md) | Shell compatibility           |
| [troubleshooting/](./troubleshooting/)       | Issue resolution              |

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

Full details: [itp-hooks CLAUDE.md](../plugins/itp-hooks/CLAUDE.md#vale-terminology-enforcement)

## Toolchain

**Bun-first** for JavaScript globals. See [Root CLAUDE.md](../CLAUDE.md#development-toolchain).
