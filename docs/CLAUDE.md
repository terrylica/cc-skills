# Documentation Guide

Context for working with cc-skills documentation.

## Directory Structure

```
docs/
├── adr/                    ← Architecture Decision Records (MADR 4.0)
├── design/                 ← Implementation specifications (1:1 with ADRs)
├── troubleshooting/        ← Issue resolution guides
├── HOOKS.md                ← Hook development guide
├── RELEASE.md              ← Release workflow guide
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

| Document                          | Purpose                           |
| --------------------------------- | --------------------------------- |
| [HOOKS.md](./HOOKS.md)            | Hook development patterns         |
| [RELEASE.md](./RELEASE.md)        | Release workflow (mise tasks)     |
| [plugin-authoring.md](./plugin-authoring.md) | Shell compatibility      |
| [troubleshooting/](./troubleshooting/) | Issue resolution            |

## Link Conventions

When linking from docs:

| Target              | Format                               |
| ------------------- | ------------------------------------ |
| Other docs          | Relative (`./adr/file.md`)           |
| Plugins             | Repo-root (`/plugins/itp/README.md`) |
| External            | Full URL                             |

## Related

- [Root CLAUDE.md](../CLAUDE.md) - Hub navigation
- [plugins/CLAUDE.md](../plugins/CLAUDE.md) - Plugin development
