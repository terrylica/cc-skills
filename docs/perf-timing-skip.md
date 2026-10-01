# Perf-timing skip convention (`CC_SKILLS_SKIP_PERF_TIMING`)

**Helper (SSoT):** [`scripts/lib/perf-timing-skip.sh`](../scripts/lib/perf-timing-skip.sh)
**Consumers:** `test-iter167-*.sh` (Group D), `test-iter174-*.sh` (per-scenario cap
verdict — the harness `test-iter180-*.sh` / `test-iter181-*.sh` invoke end-to-end).

## Problem

A few regression tests assert **absolute wall-clock caps** (iter-174's per-scenario `median ≤ cap`; iter-167 now only measures, as telemetry). Those caps are useful when a human runs the test deliberately, but they **flake under heavy load** — most visibly during a release, where `release:preflight` runs the whole hook-regression suite while semantic-release and its subprocesses compete for the CPU. A transient spike blows a cap and **spuriously blocks the release**, even though nothing regressed (the same test passes instantly when re-run standalone). Measured 2026-09-03 on the iter-167 cap before it was replaced: correct code under load ran 713 ms while the DELIBERATELY BROKEN implementation ran 816 ms on an idle machine — so the cap could not separate "busy machine" from "regression", and was additionally decaying, since the broken path had fallen from its 1184 ms baseline to 816 ms and a slightly faster machine would have passed it outright.

## Solution

Don't widen the caps (that permanently weakens regression detection) or delete
the tests. Instead: when `CC_SKILLS_SKIP_PERF_TIMING` is set, each consumer
**downgrades only its load-sensitive timing assertion to informational** (a `⊘`
line for iter-167, a non-failing `✓ … perf timing NOT gated` line for the
iter-174 harness). Every **structural / correctness** assertion still runs and
still gates. Standalone runs (flag unset) enforce the timing fully, so perf
regressions are still caught the moment anyone runs the test on purpose.

Two callers set the flag, both for the whole hook-regression suite: the **release preflight** (`tasks/release/preflight`) and **`moon run repo:test-hooks`** (`env:` in `moon.yml`), which makes `repo:check` and the pre-push gate no more load-sensitive than the publish gate (#142). Nothing else sets it, so running a test file directly (`bash tasks/tests/<test>.sh`) still enforces every cap.

## Authoring a new perf-timing test

Source the helper and guard the load-sensitive assertion — never the structural
ones:

```bash
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel)}"
# shellcheck source=../../../scripts/lib/perf-timing-skip.sh
source "$REPO_ROOT/scripts/lib/perf-timing-skip.sh"

if perf_timing_skip_active; then
    echo "  ⊘ <label>: perf timing NOT gated (CC_SKILLS_SKIP_PERF_TIMING); observed ${ms}ms"
    # do NOT increment the failure counter
else
    # the normal absolute-cap assertion (increments failure counter on breach)
fi
```

`perf_timing_skip_active` returns true unless `CC_SKILLS_SKIP_PERF_TIMING` is
unset / `0` / `false` / `no`.

## Invariant for harness consumers

When downgrading, keep the output shape the callers depend on: iter-180 counts
exactly six `✓ A[1-6]:` verdict lines and iter-181 expects `7/7 assertions
PASSED`, so the iter-174 harness emits a **`✓`-prefixed, non-failing** line for
an over-cap scenario under the flag (not a `✗ … REGRESS`).
