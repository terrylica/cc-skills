---
status: superseded
date: 2026-01-22
superseded-date: 2026-01-31
decision-maker: Terry Li
consulted: [lifecycle-reference.md, ml-data-pipeline-architecture SKILL]
research-method: multi-perspective-subagent-analysis
---

# ADR: Polars Preference Hook (Efficiency Preferences Framework)

> **SUPERSEDED (2026-01-31)**: This hook was disabled due to excessive noise during normal development. The Polars preference remains a best practice but is no longer enforced via hooks.

## Context and Problem Statement

Claude Code has no enforcement for dataframe library choice. This leads to:

1. Inconsistent Pandas usage where Polars would be 5-30x faster
2. Multiple memory copies in data pipelines (Pandas copies data 3x; Arrow/Polars: 0-1x)
3. Lost opportunity for lazy evaluation and zero-copy data flows

This ADR establishes **efficiency preferences** as a systematic pattern, starting with Polars over Pandas.

## Decision Drivers

- Consistent enforcement of efficiency best practices
- Belt-and-suspenders: PreToolUse blocks, PostToolUse reminds as backup
- Escape hatch for legitimate exceptions (MLflow, upstream APIs)
- Minimal cognitive load (simple comment to opt out)

## Efficiency Preferences Framework

### Current Active Preferences

| Preference           | Hook Location                       | Mechanism    | Exception Path        |
| -------------------- | ----------------------------------- | ------------ | --------------------- |
| UV over pip          | `posttooluse-reminder.ts`           | Block/Remind | —                     |
| Polars over Pandas   | `pretooluse-polars-preference.ts`   | Ask dialog   | `# polars-exception:` |
| graph-easy skill     | `posttooluse-reminder.ts`           | Block/Remind | —                     |
| gh CLI over WebFetch | `gh-tools` (pretooluse-webfetch.ts) | Soft block   | —                     |

### Future Candidates

| Preference                    | Rationale                            | Status  |
| ----------------------------- | ------------------------------------ | ------- |
| platformdirs over hardcoded   | XDG-compliant paths                  | Planned |
| loguru over stdlib logging    | Structured logging, less boilerplate | Planned |
| httpx over requests           | Async-first, HTTP/2 support          | Planned |
| pydantic-settings over dotenv | Type-safe configuration              | Planned |

### Arrow/Polars Zero-Copy Data Flow

The core efficiency pattern for ML pipelines:

```
Rust Vec<f64>          # Native Rust data
    ↓ zero-copy
Arrow Float64Array     # Arrow columnar format
    ↓ zero-copy
PyArrow RecordBatch    # Python-accessible Arrow
    ↓ zero-copy
Polars DataFrame       # High-level API
    ↓ single copy
NumPy ndarray → Tensor # ML framework input
```

**Result**: 1.2x peak memory vs Pandas 3x peak memory.

**Reference**: [ml-data-pipeline-architecture](/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md) for decision tree and benchmarks.

## Considered Options

### Option A: PostToolUse Reminder Only

Add Polars reminder to existing posttooluse-reminder.ts.

**Pros**: Simple, non-disruptive
**Cons**: Tool already executed, Claude may ignore

### Option B: PreToolUse Hard Block

Block all Pandas without user override.

**Pros**: Strong enforcement
**Cons**: Breaks legitimate use cases (MLflow, pandas-ta)

### Option C: PreToolUse Ask + PostToolUse Backup (Selected)

PreToolUse shows dialog; PostToolUse catches edge cases.

**Pros**: User choice + defense in depth
**Cons**: Two hooks to maintain

## Decision Outcome

**Chosen option**: Option C - PreToolUse dialog + PostToolUse backup.

### Implementation

| Layer       | Hook                              | Behavior                   |
| ----------- | --------------------------------- | -------------------------- |
| PreToolUse  | `pretooluse-polars-preference.ts` | `permissionDecision: ask`  |
| PostToolUse | `posttooluse-reminder.ts`         | `decision: block` (inform) |

### Detection Patterns

```typescript
const PANDAS_PATTERNS = [
  /^import pandas/m,
  /^from pandas import/m,
  /\bimport pandas as pd\b/,
  /\bpd\.DataFrame\(/,
  /\bpd\.read_csv\(/,
  /\bpd\.read_parquet\(/,
];
```

### Exception Mechanism

Add magic comment at file top to bypass both hooks:

```python
# polars-exception: MLflow requires Pandas DataFrames
import pandas as pd
```

### Auto-Skip Paths

| Path            | Reason                              |
| --------------- | ----------------------------------- |
| `mlflow-python` | MLflow tracking API requires Pandas |
| `legacy/`       | Legacy code maintenance             |
| `third-party/`  | Third-party integrations            |

Also skipped when Polars already imported (hybrid usage is intentional).

### Migration Cheatsheet (in hook message)

```
pd.read_csv()     → pl.read_csv() / pl.scan_csv()
pd.DataFrame()    → pl.DataFrame()
df.groupby()      → df.group_by()
pd.concat()       → pl.concat()
df.merge()        → df.join()
```

## Files Modified

| File                                   | Change                    |
| -------------------------------------- | ------------------------- |
| `pretooluse-polars-preference.ts`      | NEW - PreToolUse guard    |
| `pretooluse-polars-preference.test.ts` | NEW - 22 unit tests       |
| `posttooluse-reminder.ts`              | Added backup Polars check |
| `posttooluse-reminder.test.ts`         | Added 8 Polars tests      |
| `hooks.json`                           | Registered PreToolUse     |
| `plugins/itp-hooks/CLAUDE.md`          | Documented Polars section |

## Consequences

### Positive

- Consistent Polars preference enforcement
- User retains choice via exception comment
- Defense in depth catches edge cases
- Educational feedback with migration guide

### Negative

- May slow down quick Pandas prototypes (user must approve)
- Two hooks to maintain (PreToolUse + PostToolUse)

## References

- [Polars Migration Guide](https://docs.pola.rs/user-guide/migration/pandas/)
- [ml-data-pipeline-architecture](/plugins/devops-tools/skills/ml-data-pipeline-architecture/SKILL.md)
- [PostToolUse Hook Visibility ADR](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md)
