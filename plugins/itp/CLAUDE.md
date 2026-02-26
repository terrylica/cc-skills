# itp Plugin

> Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, formatting, and release automation.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Overview

Execute approved plans from Claude Code's Plan Mode through an ADR-driven 4-phase workflow: preflight → implementation → formatting → release. The neutral acronym "ITP" avoids action inference that caused Claude to skip preflight.

## 4-Phase Workflow

```
Preflight (ADR + Spec) → Phase 1 (Implement) → Phase 2 (Format) → Phase 3 (Release)
```

1. **Preflight**: Creates ADR (MADR 4.0), design spec, and graph-easy diagrams
2. **Phase 1**: Implement from design spec with TodoWrite tracking
3. **Phase 2**: Format with Prettier, push to GitHub
4. **Phase 3**: Release with semantic-release (main/master only)

## Plan Mode Bridge

Two paths from Plan Mode to `/itp:go`:

| Path                              | Steps          | Interface                               |
| --------------------------------- | -------------- | --------------------------------------- |
| **A**: Type in rejection feedback | Fewer (direct) | Plain text field                        |
| **B**: Defer to command prompt    | Extra step     | Native slash commands with autocomplete |

## Skills

| Skill                      | Purpose                                     |
| -------------------------- | ------------------------------------------- |
| `implement-plan-preflight` | ADR and design spec creation                |
| `adr-graph-easy-architect` | ASCII architecture diagrams (Graph::Easy)   |
| `graph-easy`               | General ASCII diagram tool                  |
| `impl-standards`           | Code quality standards                      |
| `adr-code-traceability`    | ADR-to-code linking                         |
| `code-hardcode-audit`      | Magic number detection (jscpd)              |
| `semantic-release`         | Versioning automation                       |
| `pypi-doppler`             | Local PyPI publishing (Doppler)             |
| `mise-configuration`       | Centralized env var configuration (mise)    |
| `mise-tasks`               | Task orchestration with dependencies (mise) |
| `bootstrap-monorepo`       | Monorepo scaffolding                        |
| `release`                  | Release phase execution                     |
| `setup`                    | Environment setup and dependency check      |
| `go`                       | Main workflow entry point                   |
| `hooks`                    | Hook installation management                |

## Commands

| Command        | Purpose                                        |
| -------------- | ---------------------------------------------- |
| `/itp:go`      | Execute 4-phase workflow                       |
| `/itp:setup`   | Install dependencies and configure environment |
| `/itp:hooks`   | Install/uninstall enforcement hooks            |
| `/itp:release` | Run release phase independently                |

## Dependencies

| Tool       | Install               | Notes                              |
| ---------- | --------------------- | ---------------------------------- |
| uv         | `mise install uv`     | Or `brew install uv`               |
| gh         | `brew install gh`     | **NEVER use mise** (iTerm2 issues) |
| prettier   | `bun add -g prettier` | Bun-first policy                   |
| graph-easy | `cpanm Graph::Easy`   | Requires `brew install cpanminus`  |
