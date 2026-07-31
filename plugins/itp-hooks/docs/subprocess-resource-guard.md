← [Back to itp-hooks CLAUDE.md](../CLAUDE.md)

# Subprocess resource guard (memory + concurrency)

<!-- SSoT-OK: the "added in" line below is a historical incident reference, not a version pin. -->

**Added**: the release that shipped this document · **Module**:
`hooks/lib/subprocess-resident-memory-watchdog-and-machine-wide-concurrency-slot-guard-iter124.ts`

Bounds hook-spawned subprocesses that can allocate without limit. Opt-in per tool via
`residentMemoryGuardedToolName` on the shared spawn helper. Currently enabled for `ty` on BOTH
the per-file PostToolUse check AND the project-wide Stop hook; `tsc`/`oxlint`/`biome` spawn
through the same helper and can adopt it by adding one field.

---

## Why

2026-07-30: this machine froze hard enough to need a power cycle, **twice in 38 minutes**.
The kernel's jetsam report named the cause:

```
/Library/Logs/DiagnosticReports/JetsamEvent-2026-07-30-115148.ips
largestProcess: ty
ty x5   ->  73,442 MB   (21.0 / 19.1 / 15.8 / 15.8 GB + 7 MB)
iTerm2        1,547 MB          <- the app that looked guilty was a bystander
compressor    157,861 -> 1,163,083 pages between the 11:15 and 11:51 events
```

`ty` runs after **every** `.py`/`.pyi` Write|Edit, in **every** concurrent Claude Code
session. Four sessions were editing Python at once. Measured normal behaviour on that same
project: **35–47 MB** for one file, **119 MB** for the whole project, **473 MB** for four
concurrent whole-project runs. 15–21 GB is a tool pathology, not a scaling curve.

2026-07-31: An unguarded Stop-hook run reached **14.4 GB** and was killed by the kernel at
17 minutes old. The Stop hook runs on session exit, so multiple concurrent sessions exiting
could trigger several whole-tree `ty check .` runs simultaneously — exactly the pattern that
caused 2026-07-30. The fix: migrate the Stop hook to the async spawn path with full resource
guards, reusing the infrastructure from the iter-95 shared helper and iter-124 watchdog.

**The pre-existing guardrails could not have stopped either incident.** `AbortSignal.timeout(4000)`
bounds DURATION — but the report shows those processes were **7.2–8.9 s old and already at
15.8–21.0 GB**, having outlived the 4 s deadline, and Bun's default `killSignal` is SIGTERM,
which a process cannot honour promptly while the compressor thrashes. `maxBuffer` bounds
OUTPUT SIZE, which was never the problem.

---

## What macOS actually allows

Probed directly through libc on this kernel — **not** taken from documentation:

| Limit                              | Result                                       |
| ---------------------------------- | -------------------------------------------- |
| `RLIMIT_AS` / `RLIMIT_RSS`         | **EINVAL** at every value, 0.1 GB → 64 GB    |
| `RLIMIT_DATA`                      | **EINVAL**                                   |
| `RLIMIT_STACK`                     | **EINVAL**                                   |
| `RLIMIT_CPU`                       | **accepted, and enforced** (SIGXCPU, rc −24) |
| `RLIMIT_FSIZE` / `CORE` / `NOFILE` | accepted                                     |

`ulimit -v` and `-d` are rejected by the shell with _"setrlimit failed: invalid argument."_
macOS has no cgroups and **no kernel memory cap available to a user process**. The common
advice to "just set `ulimit -v`" silently does nothing here.

---

## The three layers

Ordered by leverage, because they are not interchangeable.

### 1. Machine-wide concurrency slots — default 2

The incident _required_ four simultaneous processes, so this is the only layer that helps
when each process looks individually plausible but the fleet does not. `O_EXCL` slot files
under `/tmp` (cleared on boot), reclaimed by holder liveness (`kill(pid,0)`) with an age
backstop for pid reuse.

**Non-blocking by design.** A busy slot **skips** the check rather than queueing — this runs
inside a PostToolUse hook (and on Stop-hook exit), so waiting would put the user's edit
behind another session's subprocess, and a type check is advisory. Failing open by doing
_less_ is the only safe direction.

### 2. RSS watchdog — SIGKILL above 1500 MB

The only real memory bound obtainable on macOS. 1500 MB is ~12× the measured whole-project
peak: high enough that no honest check trips it, low enough that four simultaneous runaways
cost 6 GB instead of 73 GB.

**SIGKILL, never SIGTERM** — the incident showed SIGTERM'd processes surviving seconds at
20 GB. SIGKILL cannot be blocked, caught, or slowed by the target.

### 3. `ulimit -t` CPU ceiling — 20 CPU-seconds

Kernel-enforced backstop via `sh -c 'ulimit -t N; exec …'`, so a runaway still dies if the
Bun process is itself starved and its watchdog timer never runs. `exec` matters: it keeps
the reported pid equal to the tool's own pid, which the watchdog polls. Arguments are
single-quoted with the `'\''` escape so a hostile filename cannot break out.

---

## Cost on the hot path

**Zero for healthy subprocesses.** The watchdog's first poll is deferred 300 ms — past a
normal check's entire lifetime — so it spawns no `ps` at all in the common case. Only an
already-misbehaving process pays for the watchdog.

---

## Tuning

All constants are exported from the guard module:

| Constant                                                    | Default |
| ----------------------------------------------------------- | ------- |
| `GUARDED_SUBPROCESS_RESIDENT_MEMORY_KILL_CEILING_MEGABYTES` | 1500    |
| `MACHINE_WIDE_CONCURRENT_GUARDED_SUBPROCESS_SLOT_COUNT`     | 2       |
| `GUARDED_SUBPROCESS_CPU_SECONDS_HARD_CEILING`               | 20      |
| `RESIDENT_MEMORY_WATCHDOG_FIRST_POLL_DELAY_MILLISECONDS`    | 300     |
| `RESIDENT_MEMORY_WATCHDOG_POLL_INTERVAL_MILLISECONDS`       | 200     |

To disable for a tool, drop `residentMemoryGuardedToolName` from its spawn options.

---

## When it fires

The ty subhooks surface a memory kill to the operator rather than swallowing it — silence is
how the 2026-07-30 fault recurred after its own reboot. The message names the observed peak
and points at `uv tool upgrade ty` plus the upstream issue.

---

## Protected paths

| Path                                              | When                      | Guard status                                                                              |
| ------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------- |
| `posttooluse-ty-type-check.ts` (per-file)         | After every .py/.pyi edit | ✅ guarded (iter-124 watchdog + machine-wide concurrency slots since incident 2026-07-30) |
| `stop-ty-project-check.ts` (project-wide on exit) | Stop hook on session exit | ✅ guarded (iter-124 watchdog + machine-wide concurrency slots since incident 2026-07-31) |

---

## Testing

`…-iter124.test.ts`, 11 tests: slot exhaustion at exactly N, dead-holder reclaim,
live-holder protection, SIGKILL above ceiling, **no false positive below it**, disarm after
exit (pid-reuse safety), argv quoting against filename injection (asserted _behaviourally_ —
the escaped text does appear in the command string, so a substring assertion would fail
while the code is correct), and that `RLIMIT_CPU` is still enforced by this kernel.

**Every allocation in the suite is capped at 120 MB**, so it can never reproduce the failure
it guards against.

---

## Residual risk

The watchdog polls every 200 ms, so a process allocating at ~2 GB/s can overshoot to roughly
2 GB before dying; two slots means ~4 GB worst case instead of 73 GB. Bounded and
survivable, **not zero**. Eliminating it needs the upstream fix:
[astral-sh/ty#4147](https://github.com/astral-sh/ty/issues/4147). `ty` is pinned to 0.0.64
meanwhile.
