**Skill**: [Pueue Job Orchestration](../SKILL.md)

# ClickHouse Parallelism Tuning (pueue + ClickHouse)

When using pueue to orchestrate ClickHouse queries, the interaction between pueue parallelism and ClickHouse's thread scheduler determines actual throughput.

## The Thread Soft Limit

ClickHouse has a `concurrent_threads_soft_limit_ratio_to_cores` setting (default: 2). On a 32-core machine, this means ClickHouse allows **64 concurrent execution threads** total, regardless of how many queries are running.

Each query requests `max_threads` threads (default: auto = nproc = 32 on a 32-core machine). With 8 parallel queries each requesting 32 threads (= 256 requested), ClickHouse throttles to 64 actual threads. **The queries get ~8 effective threads each, not 32.**

## Right-Size `max_threads` Per Query

**Anti-pattern**: Letting each query request 32 threads when it only gets 8 effective threads. This creates scheduling overhead for no benefit.

**Fix**: Set `--max_threads` to match the effective thread count:

```bash
# In the job wrapper script:
clickhouse-client --max_threads=8 --multiquery < "$SQL_FILE"
```

This reduces thread scheduling overhead and allows higher pueue parallelism without oversubscription.

## Parallelism Sizing Formula

```
effective_threads_per_query = concurrent_threads_soft_limit / pueue_parallel_slots
concurrent_threads_soft_limit = nproc * concurrent_threads_soft_limit_ratio_to_cores

# Example: 32-core machine, ratio=2, soft_limit=64
# 8 pueue slots  -> 8 effective threads/query  -> ~55% CPU (baseline)
# 16 pueue slots -> 4 effective threads/query  -> ~87% CPU (1.5-1.8x throughput)
# 24 pueue slots -> 2-3 effective threads/query -> ~95% CPU (diminishing returns)
```

## Decision Matrix

| Dimension     | Check                                         | Safe Threshold                     |
| ------------- | --------------------------------------------- | ---------------------------------- |
| **Memory**    | p99 per-query x N slots < server memory limit | < 50% of `max_server_memory_usage` |
| **CPU**       | Load average < 90% of nproc                   | load < 0.9 x nproc                 |
| **I/O**       | `iostat` disk utilization                     | < 70%                              |
| **Swap**      | `vmstat` si/so columns                        | Must be 0                          |
| **CH errors** | `system.query_log` ExceptionWhileProcessing   | Must be 0                          |

## Live Tuning (No Restart Required)

Pueue parallelism can be changed live -- running jobs finish with old settings, new jobs use the new limit:

```bash
# Check current
pueue group | grep mygroup

# Bump up
pueue parallel 16 -g mygroup

# Monitor for 2-3 minutes, then check
uptime                    # Load average
free -h                   # Memory
vmstat 1 3                # Swap (si/so = 0?)
clickhouse-client --query "SELECT count() FROM system.query_log
    WHERE event_time > now() - INTERVAL 5 MINUTE
    AND type = 'ExceptionWhileProcessing'"  # Errors = 0?
```
