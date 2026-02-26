# Autoscaler

Pueue has no resource awareness. The autoscaler complements it with dynamic parallelism tuning.

**How it works**: Reads CPU load + available memory, then adjusts `pueue parallel N` per group.

```
CPU < 40% AND MEM < 60%  ->  SCALE UP (+1 per group)
CPU > 80% OR  MEM > 80%  ->  SCALE DOWN (-1 per group)
Otherwise                 ->  HOLD
```

## Incremental Scaling Protocol

Don't jump to max capacity. Ramp up in steps and verify stability at each level:

```
Step 1: Start with conservative defaults (e.g., group1=2, group2=3)
Step 2: After jobs stabilize (~5 min), probe: uptime + free -h + ps aux
Step 3: If load < 40% cores AND memory < 60% available:
        Bump by +1-2 jobs per group
Step 4: Wait ~5 min for new jobs to reach peak memory
Step 5: Probe again. If still within 80% margin, bump again
Step 6: Repeat until load ~50% cores OR memory ~70% available
```

**Why incremental**: Job memory footprint grows over time (a job may start at ~500 MB and peak at 5+ GB). Jumping straight to max parallelism risks OOM when all jobs hit peak simultaneously.

**Safety bounds**: Each group should have min/max limits the autoscaler won't exceed. It should also check per-job memory estimates before scaling up (don't add a 5 GB job if only 3 GB available).

## Dynamic Adjustment

Pueue supports live tuning without restarting jobs:

```bash
# Scale up when resources are available
pueue parallel 4 --group group1
pueue parallel 5 --group group2

# Scale down if memory pressure detected
pueue parallel 2 --group group1
```

## Per-Family Groups

When jobs have vastly different resource profiles, give each family its own pueue group. This prevents a single high-memory job type from starving lighter jobs:

```bash
# Example: high-volume symbols need fewer concurrent jobs (5 GB each)
pueue group add highvol-yearly --parallel 2

# Low-volume symbols can run more concurrently (1 GB each)
pueue group add lowvol-yearly --parallel 6
```
