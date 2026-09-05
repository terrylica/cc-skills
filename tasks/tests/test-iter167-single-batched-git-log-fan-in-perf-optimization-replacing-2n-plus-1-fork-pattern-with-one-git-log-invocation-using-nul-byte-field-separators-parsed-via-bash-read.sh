#!/usr/bin/env bash
# Iter-167 single-batched-git-log-fan-in perf regression test. Iter-165 originally invoked git log 2N+1 times per pending-release computation (1 for SHA list + 2 per commit for subject + body), making fork+exec overhead dominate at large N. Iter-167 collapses this to a single git log call with NUL-byte field separators parsed in pure bash via three IFS= read -r -d '' calls per record. Test asserts (a) iter-165 source contains the canonical iter-167 NUL-separator pattern (format string '%H%x00%s%x00%b%x00') proving fan-in optimization is in place, (b) iter-165 source does NOT contain the pre-iter-167 'git log -1 --format' per-commit pattern (proves 2N-fork code removed), (c) the FORK-COUNT invariant that iter-167 actually established — a counting git PATH shim observes exactly ONE 'git log' fork per aggregator run at N=50, and the SAME count at N=8, i.e. git-log forks are O(1) in N rather than the pre-iter-167 2N+1 (17 at N=8, 101 at N=50; both measured), (d) post-iter-167 produces IDENTICAL classification output as the same N=50 scenario (correctness invariant — optimization must preserve aggregator semantics). Group D deliberately asserts the fork COUNT rather than a wall-clock cap: an absolute millisecond threshold measures the machine, not the code, and went red during a real release run purely because the host was busy. Wall-clock numbers (min/median/max at N=50) are still emitted for operator reference but are INFORMATIONAL and never gate; iter-165's wall-clock is gated separately by test-iter174-*.sh scenario A5, which owns latency baselines for the whole toolkit.
set -euo pipefail

# Absolute dir of THIS script — resolved before any cd so the shared perf-timing
# lib loads even when a caller sets AUDIT_REPO_ROOT_OVERRIDE / changes cwd.
ITER167_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ITER167_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER167_REPO_ROOT"

# Shared perf-timing gate control (CC_SKILLS_SKIP_PERF_TIMING). Group D no
# longer GATES on wall clock at all (see the Group D header for why), so this
# flag now controls whether the load-sensitive wall-clock BENCHMARK is measured
# at all: under the release preflight the numbers would be meaningless anyway,
# so we skip the four aggregator runs and say so. Every assertion in this file —
# Groups A-D — gates unconditionally, flag set or not.
# shellcheck source=/dev/null
source "$ITER167_SCRIPT_DIR/../../scripts/lib/perf-timing-skip.sh"

ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH="$ITER167_REPO_ROOT/scripts/iter165-pending-release-aggregator-computing-cumulative-semver-bump-across-all-unreleased-commits-since-most-recent-git-tag-by-aggregating-iter161-classifier-output-and-rendering-concrete-iter164-next-version-preview.sh"

ITER167_TOTAL_ASSERTIONS_EVALUATED=0
ITER167_TOTAL_ASSERTIONS_FAILED=0

iter167_assert_truthy() {
    local label="$1" cond="$2"
    ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$cond" == "true" ]]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label"
        ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

# Synthesize a temp repo with N commits since one tag for benchmarking.
iter167_synthesize_temporary_git_repo_with_n_synthetic_commits_since_tag_for_perf_benchmark() {
    local synthetic_commit_count="$1"
    local synthetic_repo_dir
    synthetic_repo_dir=$(mktemp -d -t "iter167-perf-bench-N${synthetic_commit_count}-XXXXXX")
    (
        cd "$synthetic_repo_dir"
        git init -q
        git config user.email "iter167-perf-bench@example.com"
        git config user.name "iter167-perf-bench"
        git commit --allow-empty -q -m "baseline before tag"
        git tag v1.0.0
        for i in $(seq 1 "$synthetic_commit_count"); do
            case $((i % 4)) in
                0) git commit --allow-empty -q -m "feat: feature commit $i" ;;
                1) git commit --allow-empty -q -m "fix: bug fix commit $i" ;;
                2) git commit --allow-empty -q -m "docs: docs update $i" ;;
                3) git commit --allow-empty -q -m "chore: chore $i" ;;
            esac
        done
    ) >/dev/null 2>&1
    echo "$synthetic_repo_dir"
}

iter167_measure_wall_clock_milliseconds_of_aggregator_invocation_against_target_repo() {
    local target_repo="$1"
    local time_before time_after
    time_before=$(perl -MTime::HiRes=time -e 'print time')
    (
        cd "$target_repo"
        bash "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json >/dev/null 2>&1
    )
    time_after=$(perl -MTime::HiRes=time -e 'print time')
    perl -e "printf '%.3f', ($time_after - $time_before) * 1000"
}

# Count how many `git log` processes ONE aggregator run actually forks.
#
# This is the direct measurement of what iter-167 changed. A counting shim named
# `git` is placed at the head of PATH for exactly one aggregator invocation; it
# appends the git subcommand to a log file and then execs the REAL git by
# absolute path, so behaviour is bit-identical and only the invocation count is
# observed. The shim reads its two parameters from the environment rather than
# having them interpolated into its body, which keeps the generated script fully
# single-quoted and immune to quoting accidents.
#
# Deliberately NOT used for timing: the extra bash wrapper per fork inflates
# wall clock. Fork COUNT is an integer, is identical on a loaded and an idle
# machine, and separates the two implementations by 101 to 1 rather than by a
# ratio that shrinks as hardware gets faster.
iter167_count_git_log_forks_issued_by_a_single_aggregator_invocation_against_target_repo() {
    local target_repo="$1"
    local shim_directory shim_invocation_log real_git_absolute_path observed_git_log_fork_count
    shim_directory=$(mktemp -d -t iter167-git-fork-counting-shim-XXXXXX)
    shim_invocation_log="$shim_directory/git-subcommand-invocations.log"
    : >"$shim_invocation_log"
    real_git_absolute_path=$(command -v git)

    # Records the first non-option argument — the git subcommand — so that
    # `git log …`, `git describe …` and `git rev-parse …` are told apart.
    cat >"$shim_directory/git" <<'ITER167_GIT_COUNTING_SHIM_BODY'
#!/usr/bin/env bash
# Transient counting shim installed by the iter-167 regression test. Records the
# subcommand of this invocation, then hands over to the real git unchanged.
for iter167_each_shim_argument in "$@"; do
    case "$iter167_each_shim_argument" in
    -*) ;;
    *)
        printf '%s\n' "$iter167_each_shim_argument" >>"${ITER167_GIT_FORK_COUNTING_SHIM_LOG_ABSOLUTE_PATH:-/dev/null}"
        break
        ;;
    esac
done
exec "$ITER167_REAL_GIT_ABSOLUTE_PATH_FOR_SHIM_DELEGATION" "$@"
ITER167_GIT_COUNTING_SHIM_BODY
    chmod +x "$shim_directory/git"

    (
        cd "$target_repo"
        ITER167_GIT_FORK_COUNTING_SHIM_LOG_ABSOLUTE_PATH="$shim_invocation_log" \
            ITER167_REAL_GIT_ABSOLUTE_PATH_FOR_SHIM_DELEGATION="$real_git_absolute_path" \
            PATH="$shim_directory:$PATH" \
            bash "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json >/dev/null 2>&1
    )

    # grep -c exits 1 on zero matches; it still prints the 0 we want to report.
    observed_git_log_fork_count=$(grep -cx 'log' "$shim_invocation_log" || true)
    rm -rf "$shim_directory"
    echo "$observed_git_log_fork_count"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-167 SINGLE-BATCHED-GIT-LOG-FAN-IN PERF-OPTIMIZATION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: structural validity preserved ─────────────────────────────────
echo ""
echo "GROUP A (2 assertions): iter-165 still structurally valid after iter-167 optimization"

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A1: iter-165 aggregator passes bash -n after iter-167 optimization"
else
    echo "  ✗ A1: iter-165 aggregator FAILS bash -n syntax check"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A2: iter-165 aggregator passes shellcheck (zero warnings) after iter-167 optimization"
    else
        echo "  ✗ A2: iter-165 aggregator has shellcheck warnings"
        ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A2: shellcheck not installed — SKIPPED"
    ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: iter-167 canonical NUL-separator pattern in place ─────────────
echo ""
echo "GROUP B (3 assertions): iter-167 canonical fan-in pattern present + 2N-fork pattern removed"

ITER167_AGGREGATOR_SOURCE_CONTENTS_FOR_STATIC_GREP=$(cat "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH")

iter167_assert_truthy \
    "B1: iter-165 source contains canonical NUL-separator git log format ('%H%x00%s%x00%b%x00') proving iter-167 fan-in is in place" \
    "$([[ "$ITER167_AGGREGATOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *"'%H%x00%s%x00%b%x00'"* ]] && echo true || echo false)"

iter167_assert_truthy \
    "B2: iter-165 source does NOT contain pre-iter-167 per-commit 'git log -1 --format' pattern (proves 2N-fork code removed)" \
    "$([[ "$ITER167_AGGREGATOR_SOURCE_CONTENTS_FOR_STATIC_GREP" != *"git log -1 --format"* ]] && echo true || echo false)"

iter167_assert_truthy \
    "B3: iter-165 source uses 'IFS= read -r -d' NUL-delimited bash read pattern (canonical iter-167 parsing technique)" \
    "$([[ "$ITER167_AGGREGATOR_SOURCE_CONTENTS_FOR_STATIC_GREP" == *"IFS= read -r -d ''"* ]] && echo true || echo false)"

# ─── Group C: correctness invariant — output unchanged ──────────────────────
echo ""
echo "GROUP C (3 assertions): post-iter-167 produces IDENTICAL classification output to pre-iter-167 semantics"

ITER167_CORRECTNESS_REPO=$(iter167_synthesize_temporary_git_repo_with_n_synthetic_commits_since_tag_for_perf_benchmark 12)
ITER167_CORRECTNESS_JSON=$(cd "$ITER167_CORRECTNESS_REPO" && bash "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER167_CORRECTNESS_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["commit_count_since_tag"] == 12
assert d["aggregate_bump_label_per_semver_precedence"] == "MINOR"
assert d["iter164_next_version_preview"]["next_version"] == "v1.1.0"
' 2>/dev/null; then
    echo "  ✓ C1: N=12 mixed-commit window correctly aggregates to MINOR + v1.1.0 after iter-167 optimization"
else
    echo "  ✗ C1: N=12 aggregation broke after iter-167 optimization"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER167_CORRECTNESS_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
records = d["per_commit_bump_breakdown"]
assert len(records) == 12
for r in records:
    assert set(r.keys()) == {"short_sha", "subject", "bump_label", "rationale"}
    assert len(r["short_sha"]) == 8
    assert r["subject"]
    assert r["bump_label"] in ("MAJOR", "MINOR", "PATCH", "NONE")
' 2>/dev/null; then
    echo "  ✓ C2: all 12 per-commit records have populated 4-field schema (short_sha + subject + bump_label + rationale) — single-git-log fan-in preserves field integrity"
else
    echo "  ✗ C2: per-commit record schema broke after iter-167 (likely NUL parser bug)"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Verify multi-line body still parses correctly via the NUL-delimited reader.
ITER167_MULTILINE_BODY_REPO=$(mktemp -d -t iter167-multiline-body-correctness-XXXXXX)
(
    cd "$ITER167_MULTILINE_BODY_REPO"
    git init -q
    git config user.email "iter167@example.com"
    git config user.name "iter167"
    git commit --allow-empty -q -m "baseline"
    git tag v1.0.0
    printf 'feat: subject with multi-line body and footer\n\nThis body spans\nmultiple\nlines for testing.\n\nBREAKING CHANGE: api removed\n' | git commit --allow-empty -q -F -
) >/dev/null 2>&1
ITER167_MULTILINE_JSON=$(cd "$ITER167_MULTILINE_BODY_REPO" && bash "$ITER167_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)
ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER167_MULTILINE_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
# Body-footer BREAKING CHANGE should still bump to MAJOR even after iter-167 optimization
assert d["aggregate_bump_label_per_semver_precedence"] == "MAJOR"
assert d["iter164_next_version_preview"]["next_version"] == "v2.0.0"
' 2>/dev/null; then
    echo "  ✓ C3: multi-line body with embedded newlines + BREAKING CHANGE footer still correctly parses → MAJOR + v2.0.0 (NUL-delimited reader preserves body integrity)"
else
    echo "  ✗ C3: multi-line body parsing broke after iter-167 (NUL parser dropped body content)"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi
rm -rf "$ITER167_MULTILINE_BODY_REPO"
rm -rf "$ITER167_CORRECTNESS_REPO"

# ─── Group D: fork-count regression guard ───────────────────────────────────
#
# What this group used to be, and why it changed
# ----------------------------------------------
# Group D used to assert an ABSOLUTE wall-clock cap: "N=50 median < 700ms". That
# threshold measures the machine, not the code. It went red during a real release
# run on a host with ~18 concurrent agent sessions while passing 9/9 standalone —
# and the failure mode is the harmful direction: a red gate caused by ambient
# load teaches people to re-run until green, which is exactly how a genuine
# regression gets waved through. It also decays: measured here, the pre-iter-167
# implementation now completes N=50 in ~816ms on this hardware, so as machines
# get faster the 700ms cap will eventually pass ON BROKEN CODE.
#
# What iter-167 actually changed is a FORK COUNT — 2N+1 `git log` invocations
# collapsed to 1 — so that is what is asserted. It is an integer, it is identical
# on an idle and a loaded machine, and it separates the two implementations by
# 101 to 1 instead of by a shrinking millisecond margin. Measured both ways while
# making this change (see the negative-control numbers in D1/D2 labels below).
#
# Alternatives weighed and rejected:
#   * A self-relative ratio t(N=50)/t(N=10) in one run. Measured: 2.76 optimized
#     vs 3.87 pre-iter-167 — only a 1.4x separation, because the aggregator's
#     per-commit work is O(N) in bash and dominates the ratio. Too weak.
#   * Running a copy of the pre-iter-167 code path alongside for a speedup ratio.
#     That means carrying a duplicate implementation in the test forever; it
#     references the same three ITER167_* array names, so a rename would silently
#     turn the "baseline" into something that is no longer the old path while it
#     still produces a plausible-looking ratio.
#
# Wall-clock is still MEASURED and REPORTED below for operator reference, but it
# does not gate here. iter-165's latency is gated by test-iter174-*.sh scenario
# A5, which owns wall-clock baselines for the whole toolkit and already carries
# the CC_SKILLS_SKIP_PERF_TIMING downgrade — this group was duplicating it.
echo ""
echo "GROUP D (2 assertions + informational benchmark): git-log fork count is O(1) in N, not the pre-iter-167 2N+1"

ITER167_PERF_REPO=$(iter167_synthesize_temporary_git_repo_with_n_synthetic_commits_since_tag_for_perf_benchmark 50)
ITER167_SMALL_FORK_COUNT_REPO=$(iter167_synthesize_temporary_git_repo_with_n_synthetic_commits_since_tag_for_perf_benchmark 8)

ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50=$(iter167_count_git_log_forks_issued_by_a_single_aggregator_invocation_against_target_repo "$ITER167_PERF_REPO")
ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_8=$(iter167_count_git_log_forks_issued_by_a_single_aggregator_invocation_against_target_repo "$ITER167_SMALL_FORK_COUNT_REPO")
ITER167_EXPECTED_GIT_LOG_FORK_COUNT_AFTER_FAN_IN=1

echo "    observed git-log forks: N=8 → ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_8}   N=50 → ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50}"
echo "    pre-iter-167 (2N+1):    N=8 → 17                  N=50 → 101   (both measured against a reverted copy)"

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if (( ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50 == ITER167_EXPECTED_GIT_LOG_FORK_COUNT_AFTER_FAN_IN )); then
    echo "  ✓ D1: N=50 aggregator run forks 'git log' exactly ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50}× (pre-iter-167 forked 101×) — single-batched fan-in in force at runtime, not just in the source text"
else
    echo "  ✗ D1: N=50 aggregator run forked 'git log' ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50}× (expected ${ITER167_EXPECTED_GIT_LOG_FORK_COUNT_AFTER_FAN_IN}) — the single-batched-git-log fan-in has regressed"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER167_TOTAL_ASSERTIONS_EVALUATED=$((ITER167_TOTAL_ASSERTIONS_EVALUATED + 1))
if (( ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_8 == ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50 )); then
    echo "  ✓ D2: git-log fork count is INVARIANT in N (${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_8} at N=8, ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50} at N=50) — O(1), the property iter-167 established; the 2N+1 shape would read 17 vs 101"
else
    echo "  ✗ D2: git-log fork count GROWS with N (${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_8} at N=8 → ${ITER167_OBSERVED_GIT_LOG_FORK_COUNT_AT_N_50} at N=50) — per-commit forking has returned"
    ITER167_TOTAL_ASSERTIONS_FAILED=$((ITER167_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Informational wall-clock benchmark. Never gates — see the group header. Under
# the release preflight the host is too loaded for the number to mean anything,
# so the four runs are skipped outright rather than measured and ignored.
if perf_timing_skip_active; then
    echo "    wall-clock benchmark:  skipped (CC_SKILLS_SKIP_PERF_TIMING set — host under release load, timing would be noise)"
else
    # Warm-up run (page cache, lib sourcing) — discard.
    iter167_measure_wall_clock_milliseconds_of_aggregator_invocation_against_target_repo "$ITER167_PERF_REPO" >/dev/null

    # 3 measured runs.
    ITER167_BENCHMARK_RUN_1_MILLISECONDS=$(iter167_measure_wall_clock_milliseconds_of_aggregator_invocation_against_target_repo "$ITER167_PERF_REPO")
    ITER167_BENCHMARK_RUN_2_MILLISECONDS=$(iter167_measure_wall_clock_milliseconds_of_aggregator_invocation_against_target_repo "$ITER167_PERF_REPO")
    ITER167_BENCHMARK_RUN_3_MILLISECONDS=$(iter167_measure_wall_clock_milliseconds_of_aggregator_invocation_against_target_repo "$ITER167_PERF_REPO")

    # Compute median (sort 3 numbers, take middle).
    ITER167_BENCHMARK_MEDIAN_MILLISECONDS=$(printf '%s\n' "$ITER167_BENCHMARK_RUN_1_MILLISECONDS" "$ITER167_BENCHMARK_RUN_2_MILLISECONDS" "$ITER167_BENCHMARK_RUN_3_MILLISECONDS" | sort -n | sed -n 2p)
    ITER167_BENCHMARK_MIN_MILLISECONDS=$(printf '%s\n' "$ITER167_BENCHMARK_RUN_1_MILLISECONDS" "$ITER167_BENCHMARK_RUN_2_MILLISECONDS" "$ITER167_BENCHMARK_RUN_3_MILLISECONDS" | sort -n | sed -n 1p)
    ITER167_BENCHMARK_MAX_MILLISECONDS=$(printf '%s\n' "$ITER167_BENCHMARK_RUN_1_MILLISECONDS" "$ITER167_BENCHMARK_RUN_2_MILLISECONDS" "$ITER167_BENCHMARK_RUN_3_MILLISECONDS" | sort -n | sed -n 3p)

    echo "    benchmark runs (N=50): ${ITER167_BENCHMARK_RUN_1_MILLISECONDS}ms / ${ITER167_BENCHMARK_RUN_2_MILLISECONDS}ms / ${ITER167_BENCHMARK_RUN_3_MILLISECONDS}ms  [INFORMATIONAL — does not gate]"
    echo "    benchmark stats:       min=${ITER167_BENCHMARK_MIN_MILLISECONDS}ms  median=${ITER167_BENCHMARK_MEDIAN_MILLISECONDS}ms  max=${ITER167_BENCHMARK_MAX_MILLISECONDS}ms"
    echo "    pre-iter-167 baseline: ~1184ms median (5-run measurement, same N=50 scenario, original hardware)"
fi

rm -rf "$ITER167_PERF_REPO"
rm -rf "$ITER167_SMALL_FORK_COUNT_REPO"

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER167_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-167 REGRESSION TEST: ${ITER167_TOTAL_ASSERTIONS_EVALUATED}/${ITER167_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-167 REGRESSION TEST: $((ITER167_TOTAL_ASSERTIONS_EVALUATED - ITER167_TOTAL_ASSERTIONS_FAILED))/${ITER167_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER167_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
