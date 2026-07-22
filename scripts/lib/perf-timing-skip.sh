#!/usr/bin/env bash
# scripts/lib/perf-timing-skip.sh — shared control for load-sensitive perf-timing
# assertions. ONE home for the CC_SKILLS_SKIP_PERF_TIMING convention.
#
# Why this exists
# ---------------
# A few regression tests assert ABSOLUTE wall-clock caps (e.g. "median < 700ms").
# Those caps are meaningful when a human runs the test deliberately, but they
# FLAKE when the machine is under heavy load — most notably during a release,
# where `release:preflight` runs the entire hook-regression suite while
# semantic-release and its subprocesses compete for the CPU. A transient load
# spike then blows a timing cap and spuriously blocks the release, even though
# the optimization under test has not regressed at all (the same test passes
# instantly when re-run standalone).
#
# The fix is NOT to widen the caps (that permanently weakens regression
# detection) nor to delete the tests. Instead, when CC_SKILLS_SKIP_PERF_TIMING
# is set, a consumer DOWNGRADES only its load-sensitive TIMING assertion to
# informational — its structural / correctness assertions still run and still
# gate. Standalone runs (flag unset) enforce the timing fully, so perf
# regressions are still caught the moment anyone runs the test on purpose.
#
# Contract for consumers
# ----------------------
#   1. source this file (path: "$REPO_ROOT/scripts/lib/perf-timing-skip.sh")
#   2. guard the timing assertion:
#        if perf_timing_skip_active; then
#            echo "  ⊘ <label>: perf timing NOT gated (CC_SKILLS_SKIP_PERF_TIMING); observed <n>ms"
#            # do NOT increment the failure counter
#        else
#            # the normal absolute-cap assertion
#        fi
#   3. the release preflight sets CC_SKILLS_SKIP_PERF_TIMING=1 for the
#      regression-suite invocation; nothing else sets it.
#
# SSoT for the convention + rationale: docs/perf-timing-skip.md
# Consumers: .mise/tasks/tests/test-iter167-*.sh (Group D),
#            .mise/tasks/tests/test-iter174-*.sh (per-scenario cap verdict; the
#            harness that iter-180 / iter-181 invoke end-to-end).

# Return 0 (true) when perf-timing assertions should be downgraded to
# informational; 1 (false) otherwise. Unset / 0 / false / no ⇒ enforce.
perf_timing_skip_active() {
  case "${CC_SKILLS_SKIP_PERF_TIMING:-}" in
  "" | 0 | false | FALSE | no | NO) return 1 ;;
  *) return 0 ;;
  esac
}
