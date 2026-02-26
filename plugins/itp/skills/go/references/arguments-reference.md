**Skill**: [ITP Go Workflow](../SKILL.md)

# Arguments Reference

## Usage Examples

```text
# Fresh start modes (no release)
/itp:go                   # Derive slug, stay on current branch
/itp:go my-feature        # Custom slug, stay on current branch
/itp:go -b                # Derive slug, create {type}/{adr-id} branch
/itp:go my-feature -b     # Custom slug, create {type}/{adr-id} branch

# Feature branch with release intent (reminder shown, Phase 3 skips)
/itp:go my-feature -b -r        # Intent to release after merge
/itp:go my-feature -b -r -p     # Intent to release + publish after merge

# Release modes (on main/master only)
/itp:go -r                # On main: run semantic-release only
/itp:go -p                # On main: run PyPI publish only
/itp:go -r -p             # On main: full release + publish

# Continuation modes
/itp:go -c                # Continue: auto-detect ADR, resume
/itp:go -c "use Redis"    # Continue with explicit decision
```

## Mode Selection

- Fresh start: `[slug] [-b]` -- creates new ADR
- Continuation: `-c [decision]` -- resumes existing ADR

These modes are **mutually exclusive**. `-c` cannot be combined with `slug` or `-b`.

## Branch Type

Determine `{type}` from ADR nature (conventional commits):

| Type       | When                                   |
| ---------- | -------------------------------------- |
| `feat`     | New capability or feature              |
| `fix`      | Bug fix                                |
| `refactor` | Code restructuring, no behavior change |
| `docs`     | Documentation only                     |
| `chore`    | Maintenance, tooling, dependencies     |
| `perf`     | Performance improvement                |

## Slug Derivation

If no slug is provided, derive an appropriate kebab-case slug from the Global Plan's context (the feature/task being implemented). The slug should be descriptive (3-5 words) and capture the essence of the feature.

**Word Economy Rule**: Each word in the slug MUST convey unique meaning. Avoid redundancy.

| Example                          | Verdict | Reason                                                           |
| -------------------------------- | ------- | ---------------------------------------------------------------- |
| `clickhouse-database-migration`  | Bad     | "database" redundant (ClickHouse IS a database)                  |
| `clickhouse-aws-ohlcv-ingestion` | Good    | clickhouse=tech, aws=platform, ohlcv=data-type, ingestion=action |
| `user-auth-token-refresh`        | Good    | user=scope, auth=domain, token=artifact, refresh=action          |
| `api-endpoint-rate-limiting`     | Good    | api=layer, endpoint=target, rate=metric, limiting=action         |

## ADR ID in Branch, ADR, Design, and Code

The ADR ID (`YYYY-MM-DD-slug`) is the canonical identifier used in:

- ADR file, Design folder, Code references, Branch name (if `-b`)
