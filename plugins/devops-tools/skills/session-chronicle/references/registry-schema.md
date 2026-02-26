**Skill**: [Session Chronicle](../SKILL.md)

# Registry Schema Reference

Complete schema definitions and examples for `registry.jsonl` and `iterations.jsonl`.

---

## registry.jsonl (Master Index)

Each line is a complete, self-contained JSON object:

```json
{
  "id": "2026-01-01-multiyear-momentum",
  "type": "research_session",
  "title": "Multi-Year Cross-Sectional Momentum Strategy Validation",
  "project": "research-repo",
  "branch": "feat/2026-01-01-multiyear-cs-momentum-research",
  "created_at": "2026-01-03T01:00:00Z",
  "created_by": {
    "github_username": "terrylica",
    "model": "claude-opus-4-5-20251101",
    "session_uuid": "8c821a19-e4f4-45d5-9338-be3a47ac81a3"
  },
  "strategy_type": "cross_sectional_momentum",
  "date_range": { "start": "2022-01-01", "end": "2025-12-31" },
  "session_contexts": [
    {
      "session_uuid": "8c821a19-...",
      "type": "main",
      "entries": 1128,
      "description": "Primary session - research iterations, PR preparation"
    },
    {
      "session_uuid": "agent-a728ebe",
      "type": "subagent",
      "entries": 113,
      "timestamp_start": "2026-01-02T07:25:47.658Z",
      "description": "Explore agent - codebase analysis"
    }
  ],
  "metrics": {
    "sharpe_2bps": 1.05,
    "sharpe_13bps": 0.31,
    "max_drawdown": -0.18
  },
  "tags": ["momentum", "cross-sectional", "multi-year", "validated"],
  "artifacts": {
    "adr": "docs/adr/2026-01-02-multiyear-momentum-vs-ml.md",
    "strategy_config": "examples/02_strategies/cs_momentum_multiyear.yaml",
    "research_log": "outputs/research_sessions/2026-01-01-multiyear-momentum/research_log.md",
    "iteration_configs": "outputs/research_sessions/2026-01-01-multiyear-momentum/",
    "s3": "s3://example-findings-bucket/sessions/2026-01-01-multiyear-momentum/"
  },
  "status": "validated",
  "finding": "BiLSTM time-series models show no predictive edge (49.05% hit rate). Simple CS momentum outperforms.",
  "recommendation": "Deploy CS Momentum 120+240 strategy. Abandon ML-based approaches for this market regime."
}
```

---

## Required Fields

- `id` - Unique identifier (format: `YYYY-MM-DD-slug`)
- `type` - `research_session` | `finding` | `decision`
- `created_at` - ISO8601 timestamp
- `created_by.github_username` - **MANDATORY** - GitHub username
- `session_contexts` - **MANDATORY** - Array of ALL session UUIDs

## Optional Fields

- `title` - Human-readable title
- `project` - Project/repository name
- `branch` - Git branch name
- `strategy_type` - Strategy classification (for research_session type)
- `date_range` - `{start, end}` date range covered
- `metrics` - Key performance metrics object
- `tags` - Searchable tags array
- `artifacts` - Object with paths (see Artifact Paths below)
- `status` - `draft` | `validated` | `production` | `archived`
- `finding` - Summary of what was discovered
- `recommendation` - What to do next

## Artifact Paths

| Key                 | Location                               | Purpose                     |
| ------------------- | -------------------------------------- | --------------------------- |
| `adr`               | `docs/adr/...`                         | Committed ADR document      |
| `strategy_config`   | `examples/...`                         | Committed strategy example  |
| `research_log`      | `outputs/research_sessions/.../`       | Gitignored research log     |
| `iteration_configs` | `outputs/research_sessions/.../`       | Gitignored config files     |
| `s3`                | `s3://example-findings-bucket/sessions/<id>/` | S3 archive for team sharing |

---

## iterations.jsonl (Detailed Records)

Located at `findings/sessions/<id>/iterations.jsonl`. For iteration-level tracking:

```json
{
  "id": "iter-001",
  "registry_id": "2026-01-01-multiyear-momentum",
  "type": "iteration",
  "created_at": "2026-01-01T10:00:00Z",
  "created_by": {
    "github_username": "terrylica",
    "model": "claude-opus-4-5-20251101",
    "session_uuid": "8c821a19-e4f4-45d5-9338-be3a47ac81a3"
  },
  "hypothesis": "Test BiLSTM with conservative clip",
  "config": { "strategy": "bilstm", "clip": 0.05 },
  "results": { "train_sharpe": 0.31, "test_sharpe": -1.15 },
  "finding": "BiLSTM shows no edge",
  "status": "FAILED"
}
```
