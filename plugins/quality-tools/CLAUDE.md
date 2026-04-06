# quality-tools Plugin

> Code quality and validation: clone detection, multi-agent E2E validation, performance profiling, schema testing.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Skills

| Skill                               | Purpose                                                     |
| ----------------------------------- | ----------------------------------------------------------- |
| `clickhouse-architect`              | ClickHouse schema design, compression codecs, ORDER BY keys |
| `code-clone-assistant`              | Detect and refactor code duplication (PMD CPD, Semgrep)     |
| `multi-agent-e2e-validation`        | Parallel E2E validation for database refactors              |
| `multi-agent-performance-profiling` | Parallel performance profiling for bottlenecks              |
| `pre-ship-review`                   | Structured quality review before shipping (PRs, releases)   |
| `schema-e2e-validation`             | Earthly E2E validation for schema-first data contracts      |
| `symmetric-dogfooding`              | Bidirectional integration validation between repos          |
| `dead-code-detector`                | Detect dead code with Vulture and coverage analysis         |
| `alpha-forge-preship`               | Alpha-forge specific pre-ship gates                         |
| `telemetry-terminology-similarity`  | Detect similar/duplicate field names in telemetry schemas   |

## Conventions

- **Three-phase review**: external tools → cc-skills orchestration → human judgment
- **9-category anti-pattern taxonomy** for integration boundary failures
- **TodoWrite templates** for new features, bug fixes, and refactoring ships
