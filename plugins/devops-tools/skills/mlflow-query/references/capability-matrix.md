**Skill**: [MLflow Query Skill](../SKILL.md)

## 📊 Capability Matrix (Quick Reference)

| Capability            | Supported        | Method                         | Constraints                        |
|-----------------------|------------------|--------------------------------|------------------------------------|
| **List experiments**  | ✅                | `mlflow experiments search`    | None                               |
| **List runs**         | ✅                | `mlflow runs list`             | Table output (parse or export CSV) |
| **Get run details**   | ✅                | `mlflow runs describe`         | JSON output, complete data         |
| **Filter by metrics** | ✅                | Manual grep/awk                | AND-only in Python API             |
| **Filter by params**  | ⚠️               | Manual grep/awk + quote values | AND-only, params are strings       |
| **OR filters**        | ❌                | Run multiple queries           | MLflow limitation                  |
| **Export CSV**        | ✅                | `mlflow experiments csv`       | Efficient for bulk                 |
| **Metric history**    | ❌ CLI / ✅ Python | Use Python API                 | CLI doesn't support time-series    |
| **Aggregation**       | ❌                | Client-side (awk/python)       | No SUM/AVG in MLflow               |
| **Create runs**       | ❌                | Out of scope                   | Read-only skill                    |
| **Modify runs**       | ❌                | Out of scope                   | Read-only skill                    |
| **Streaming**         | ❌                | Pagination                     | Poll-based only                    |
| **Doppler creds**     | ✅                | Atomic secrets pattern         | Recommended for production         |

