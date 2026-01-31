# quality-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-6-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Code quality and validation tools for Claude Code: clone detection, multi-agent E2E validation, performance profiling, and schema testing.

## Skills

| Skill                               | Description                                                   |
| ----------------------------------- | ------------------------------------------------------------- |
| `clickhouse-architect`              | ClickHouse schema design, compression codecs, ORDER BY keys   |
| `code-clone-assistant`              | Detect and refactor code duplication with PMD CPD and Semgrep |
| `multi-agent-e2e-validation`        | Parallel E2E validation for database refactors and migrations |
| `multi-agent-performance-profiling` | Parallel performance profiling for pipeline bottlenecks       |
| `schema-e2e-validation`             | Earthly E2E validation for schema-first data contracts        |
| `symmetric-dogfooding`              | Bidirectional integration validation between repositories     |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install quality-tools@cc-skills
```

## Usage

Skills are model-invoked based on context.

**Trigger phrases:**

- "ClickHouse schema", "compression codecs", "ORDER BY key" → clickhouse-architect
- "code clones", "DRY violations", "duplicate code", "PMD CPD" → code-clone-assistant
- "E2E validation", "schema migration", "database refactor" → multi-agent-e2e-validation
- "performance profiling", "pipeline bottlenecks", "parallel profiling" → multi-agent-performance-profiling
- "schema validation", "YAML schema", "Earthly E2E" → schema-e2e-validation
- "cross-repo validation", "polyrepo integration", "bidirectional testing" → symmetric-dogfooding

## Features

### ClickHouse Architect

- Schema design patterns for ClickHouse Cloud (SharedMergeTree) and self-hosted (ReplicatedMergeTree)
- Compression codec selection based on column data types
- ORDER BY key optimization for query patterns
- Table structure auditing and recommendations

### Code Clone Detection

- PMD CPD integration for copy-paste detection
- Semgrep patterns for semantic duplicates
- Refactoring suggestions with shared abstractions

### Multi-Agent E2E Validation

- Parallel agent execution for independent validation tasks
- Database refactor validation with before/after comparison
- Bulk data pipeline verification

### Performance Profiling

- Multi-agent parallel profiling for concurrent bottleneck detection
- Pipeline stage timing and throughput analysis
- Resource utilization tracking

### Schema E2E Validation

- Earthly-based containerized schema testing
- YAML schema contract validation against live databases
- Drift detection between schema and implementation

### Symmetric Dogfooding

- Bidirectional validation: repo A tests repo B's consumer, repo B tests repo A's producer
- Polyrepo integration testing before release
- Cross-repo dependency verification

## Troubleshooting

| Issue                        | Cause                  | Solution                             |
| ---------------------------- | ---------------------- | ------------------------------------ |
| PMD CPD not found            | Not installed          | `brew install pmd`                   |
| Semgrep timeout              | Large codebase         | Add `--max-target-bytes` flag        |
| Earthly build fails          | Docker not running     | Start Docker Desktop                 |
| ClickHouse connection error  | Network issue          | Verify ClickHouse Cloud connectivity |
| Multi-agent validation hangs | Insufficient resources | Reduce parallel agent count          |

## License

MIT
