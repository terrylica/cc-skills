**Skill**: [Pueue Job Orchestration](../SKILL.md)

# Environment Variables & Secrets for Pueue Jobs

## Preferred Pattern: python-dotenv for Pueue Job Secrets

Pueue jobs run in **clean shells** without `.bashrc`, `.zshrc`, or mise activation. This means `mise.toml [env]` variables are invisible to pueue jobs. The most portable solution is `python-dotenv`:

### Architecture

```
mise.toml           -> Task definitions only (no [env] for secrets)
.env                -> Secrets (gitignored, loaded by python-dotenv at runtime)
scripts/backfill.sh -> Pueue orchestrator (just `cd $PROJECT_DIR` for dotenv)
```

### Implementation

**1. Project `.env`** (gitignored):

```bash
# .env -- loaded by python-dotenv at runtime
API_KEY=sk-abc123
DATABASE_URL=postgresql://localhost/mydb
```

**2. Python entry point** -- call `load_dotenv()` early:

```python
from dotenv import load_dotenv
load_dotenv()  # Auto-loads .env from cwd

import os
API_KEY = os.getenv("API_KEY")  # Works everywhere
```

**3. Pueue job** -- just needs `cd` to project root:

```bash
# The only requirement: cwd must contain .env
pueue add -- bash -c 'cd ~/project && uv run python my_script.py'
```

### Why This Beats Alternatives

| Approach                   | Interactive Shell | Pueue Job | Cron    | SSH Remote  | Cross-Platform |
| -------------------------- | ----------------- | --------- | ------- | ----------- | -------------- |
| mise `[env]`               | Yes               | **No**    | **No**  | **Fragile** | macOS+Linux    |
| `pueue env set`            | N/A               | Yes       | **No**  | **No**      | N/A            |
| Export in `.bashrc`        | Yes               | **No**    | **No**  | Depends     | Varies         |
| **python-dotenv + `.env`** | **Yes**           | **Yes**   | **Yes** | **Yes**     | **Yes**        |

**Cross-reference**: See `distributed-job-safety` skill -- [G-15](../distributed-job-safety/references/environment-gotchas.md#g-15-pueue-jobs-cannot-see-mise-env-variables), [AP-16](../distributed-job-safety/SKILL.md)

---

## Integration with rangebar-py

The rangebar-py project has Pueue integration scripts:

| Script                           | Purpose                                                  |
| -------------------------------- | -------------------------------------------------------- |
| `scripts/pueue-populate.sh`      | Queue cache population jobs with group-based parallelism |
| `scripts/setup-pueue-linux.sh`   | Install Pueue on Linux servers                           |
| `scripts/populate_full_cache.py` | Python script for individual symbol/threshold jobs       |

### Phase-Based Execution

```bash
# Phase 1: 1000 dbps (fast, 4 parallel)
./scripts/pueue-populate.sh phase1

# Phase 2: 250 dbps (moderate, 2 parallel)
./scripts/pueue-populate.sh phase2

# Phase 3: 500, 750 dbps (3 parallel)
./scripts/pueue-populate.sh phase3

# Phase 4: 100 dbps (resource intensive, 1 at a time)
./scripts/pueue-populate.sh phase4
```
