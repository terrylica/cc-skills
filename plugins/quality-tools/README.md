# quality-tools

Code quality and validation tools for Claude Code.

## Skills

### clickhouse-architect

Prescriptive ClickHouse schema design, compression codec selection, and performance optimization. Use when designing schemas, selecting ORDER BY keys, choosing compression codecs, auditing table structure, or optimizing query performance. Covers both ClickHouse Cloud (SharedMergeTree) and self-hosted (ReplicatedMergeTree).

### code-clone-assistant

Detects and refactors code duplication using PMD CPD and Semgrep. Use when identifying code clones, addressing DRY violations, or refactoring duplicate code.

### multi-agent-e2e-validation

Multi-agent parallel E2E validation workflow for database refactors and system migrations. Use when validating deployments, schema migrations, or bulk data pipelines.

### multi-agent-performance-profiling

Multi-agent parallel performance profiling for identifying bottlenecks. Use when investigating performance issues or optimizing data pipelines.

### schema-e2e-validation

Earthly E2E validation for schema-first data contracts. Use when validating schema changes or testing YAML against live databases.

### symmetric-dogfooding

Bidirectional integration validation where two repositories validate each other before release. Use for polyrepo integration testing, cross-repo validation, and ensuring producer/consumer relationships work correctly.

## Installation

Install via cc-skills marketplace:

```bash
# From Claude Code
/install-plugin quality-tools
```

## License

MIT
