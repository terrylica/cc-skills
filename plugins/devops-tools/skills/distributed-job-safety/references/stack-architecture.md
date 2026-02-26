# The Mise + Pueue + systemd-run Stack

```
mise (environment + task discovery)
  |-- .mise.toml [env] -> SSoT for defaults
  |-- .mise/tasks/jobs.toml -> task definitions
  |     |-- mise run jobs:submit-all
  |     |     |-- submit-all.sh (orchestrator)
  |     |           |-- pueue add (per-unit, NOT per-query)
  |     |                 |-- submit_unit.sh (per unit)
  |     |                       |-- xargs -P16 (parallel queries)
  |     |                             |-- wrapper.sh (per query)
  |     |                                   |-- clickhouse-client < sql_file
  |     |                                   |-- flock + append NDJSON
  |     |
  |     |-- mise run jobs:process-all (Python pipeline variant)
  |     |     |-- job-runner.sh (orchestrator)
  |     |           |-- pueue add (per-job)
  |     |                 |-- systemd-run --scope -p MemoryMax=XG -p MemorySwapMax=0
  |     |                       |-- uv run python scripts/process.py
  |     |                             |-- run_resumable_job()
  |     |                                   |-- get_checkpoint_path() -> param-aware
  |     |                                   |-- checkpoint.save() -> atomic write
  |     |                                   |-- checkpoint.unlink() -> missing_ok=True
  |     |
  |     |-- mise run jobs:autoscale-loop
  |           |-- autoscaler.sh --loop (60s interval)
  |                 |-- reads: free -m, uptime, pueue status --json
  |                 |-- adjusts: pueue parallel N --group <group>
```

## Responsibility Boundaries

| Layer           | Responsibility                                             |
| --------------- | ---------------------------------------------------------- |
| **mise**        | Environment variables, tool versions, task discovery       |
| **pueue**       | Daemon persistence, parallelism limits, restart, `--after` |
| **systemd-run** | Per-job cgroup memory caps (Linux only, no-op on macOS)    |
| **autoscaler**  | Dynamic parallelism tuning based on host resources         |
| **Python/app**  | Domain logic, checkpoint management, data integrity        |
