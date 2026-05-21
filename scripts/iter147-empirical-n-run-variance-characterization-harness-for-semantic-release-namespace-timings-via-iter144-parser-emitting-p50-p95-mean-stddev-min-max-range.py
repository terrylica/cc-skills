#!/usr/bin/env python3
# iter-147 empirical N-run variance characterization harness for
# semantic-release DEBUG-namespace stderr timings, via the iter-144 parser,
# emitting p50/p95/mean/stddev/min/max/range per namespace across back-to-back
# `npx semantic-release --dry-run --no-ci` captures.
#
# WHY THIS EXISTS (the single-sample variance trap iter-143 fell into):
#
#   Iter-143 introduced four community-validated @semantic-release/github
#   config optimizations and shipped v21.58.4. Empirical timing showed it
#   came in 4.6 SECONDS SLOWER than the v21.58.3 baseline. The natural
#   conclusion would have been "the optimizations made things worse, revert
#   them." That conclusion is wrong — because the comparison was between
#   ONE sample of v21.58.4 and ONE sample of v21.58.3, and the per-release
#   wall-clock distribution is dominated by SSH-handshake + GitHub-API
#   round-trip variance with stddev far larger than the perf delta the
#   optimization was targeting. The four flags remain shipped (zero
#   observable degradation in any subsequent run) but the iter-143
#   commit message had to honestly write up "did not pan out" instead of
#   the originally hypothesized speedup.
#
#   This harness exists so that no future iter-NNN repeats that trap.
#   By running N back-to-back captures and emitting percentile + variance
#   summary across the cohort, an operator can BEFORE-AFTER compare
#   distributions instead of point samples, and make perf claims that
#   actually withstand re-measurement.
#
# WHAT THIS DOES:
#
#   1. Runs N (default 5; tunable via ITER147_VARIANCE_PROFILE_RUN_COUNT)
#      back-to-back `npx semantic-release --dry-run --no-ci` invocations,
#      capturing stderr to /tmp/iter147-variance-profile-run-{i}.log.
#
#   2. Parses each capture with the iter-144 parser
#      (scripts/iter144-...py) to extract per-namespace cumulative-ms.
#
#   3. Aggregates per-namespace timings across runs into a dict-of-lists
#      and computes p50 (median), p95, mean, stddev, min, max, range.
#
#   4. Emits a table sorted by descending p50, with a "variance flag"
#      column marking namespaces whose stddev/p50 ratio exceeds 0.20
#      (these are the namespaces where single-sample comparisons are
#      dangerous — exactly the trap iter-143 walked into).
#
#   5. Also emits a whole-pipeline elapsed-ms p50/p95/stddev so operators
#      can quote the right number ("median dry-run is X ms with 95th
#      percentile Y ms", not "dry-run takes ~X ms").
#
# OUTPUT SHAPE:
#
#   ⧗ ─── Per-namespace timing distribution across N=5 runs ───
#         namespace                              p50    p95   mean  stddev  min  max  range  variance-flag
#         semantic-release:get-git-auth-url     1750   6184   2890    1820  1200 6184  4984  ⚠ HIGH (σ/p50=1.04)
#         semantic-release:get-tags             2410   2520   2438     45   2380 2520   140
#         semantic-release:config                128    140    131      6    122  140    18
#         ...
#   ⧗ Whole-pipeline dry-run wall-clock: p50=Nms, p95=Nms, stddev=Nms across 5 runs.
#
# USAGE:
#
#   # Default: 5 back-to-back runs.
#   uv run --python 3.13 scripts/iter147-...py
#
#   # Custom run count:
#   ITER147_VARIANCE_PROFILE_RUN_COUNT=10 uv run --python 3.13 scripts/iter147-...py
#
#   # Replay existing logs without re-running (e.g., after a long capture):
#   ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS=1 uv run --python 3.13 scripts/iter147-...py
#
# WORKING-DIRECTORY-CLEANLINESS GOTCHA:
#
#   This harness invokes `npx semantic-release --dry-run --no-ci`, which our
#   .releaserc.yml wires to run `scripts/release-preflight.sh` in the
#   `verifyConditions` lifecycle step. The preflight gate ABORTS with
#   "PREFLIGHT FAILED: Working directory not clean" if `git status --porcelain`
#   is non-empty. When preflight aborts at verifyConditions, lifecycle phases
#   downstream of verifyConditions never execute — so `semantic-release:get-tags`,
#   `semantic-release:get-commits`, and other later-phase namespaces will be
#   MISSING from the captured stderr. The harness will still emit a valid
#   distribution table, but with fewer rows (only verifyConditions-phase
#   namespaces like `get-git-auth-url` will appear).
#
#   For full namespace cohort coverage, run this harness against a CLEAN
#   working directory (commit or stash pending changes first).

from __future__ import annotations

import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ITER147_DEFAULT_NUMBER_OF_BACK_TO_BACK_DRY_RUN_CAPTURES_FOR_VARIANCE_CHARACTERIZATION = 5
ITER147_STDERR_LOG_TMPDIR_BASENAME_PREFIX_FOR_PER_RUN_CAPTURE_FILES = "/tmp/iter147-variance-profile-run-"
ITER147_VARIANCE_FLAG_HIGH_STDDEV_TO_P50_RATIO_THRESHOLD_FOR_TRAP_WARNING = 0.20
ITER147_NAMESPACE_TIMING_REGEX_FROM_ITER144_PARSER_OUTPUT_LINE_DIMENSION_1_ACCURATE = re.compile(
    r"^\s+\d+\.\s+(\d+)\s+ms\s+(\S+)\s*$"
)
ITER147_WHOLE_PIPELINE_ELAPSED_REGEX_FROM_ITER144_PARSER_FOOTER_LINE = re.compile(
    r"whole-debug-log elapsed: (\d+)ms"
)


@dataclass
class Iter147PerNamespaceTimingDistributionAcrossNRunsAggregator:
    namespace_to_per_run_elapsed_milliseconds_list_collected_across_n_back_to_back_dry_run_captures: Dict[str, List[int]] = field(default_factory=dict)
    whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures: List[int] = field(default_factory=list)

    def record_per_namespace_elapsed_ms_for_this_single_dry_run_capture(self, namespace: str, elapsed_ms: int) -> None:
        self.namespace_to_per_run_elapsed_milliseconds_list_collected_across_n_back_to_back_dry_run_captures.setdefault(namespace, []).append(elapsed_ms)

    def record_whole_pipeline_elapsed_ms_for_this_single_dry_run_capture(self, elapsed_ms: int) -> None:
        self.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures.append(elapsed_ms)


def iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method(values: List[int], p: float) -> int:
    if not values:
        return 0
    sorted_values = sorted(values)
    if len(sorted_values) == 1:
        return sorted_values[0]
    # Nearest-rank percentile.
    rank_one_indexed = max(1, min(len(sorted_values), int(round(p / 100.0 * len(sorted_values)))))
    return sorted_values[rank_one_indexed - 1]


def iter147_compute_stddev_of_integer_value_sample_list_returns_zero_for_single_value_or_empty(values: List[int]) -> float:
    if len(values) < 2:
        return 0.0
    return statistics.stdev(values)


def iter147_locate_iter144_parser_absolute_path_from_sibling_scripts_directory_relative_to_this_iter147_harness() -> Path:
    this_script_absolute_path = Path(__file__).resolve()
    sibling_scripts_directory_absolute_path = this_script_absolute_path.parent
    iter144_parser_filename = (
        "iter144-semantic-release-plugin-lifecycle-step-timing-instrumentation-via-debug-namespace-stderr-output-parser-emitting-top-n-slowest-bottleneck-ranking-with-cumulative-elapsed-milliseconds-summed-per-plugin-step.py"
    )
    iter144_parser_absolute_path = sibling_scripts_directory_absolute_path / iter144_parser_filename
    if not iter144_parser_absolute_path.is_file():
        raise FileNotFoundError(f"iter-144 parser not found at expected sibling path: {iter144_parser_absolute_path}")
    return iter144_parser_absolute_path


def iter147_run_one_semantic_release_dry_run_capture_writing_stderr_to_per_run_log_file(
    run_index_one_indexed: int,
    repo_root_absolute_path: Path,
) -> Path:
    per_run_stderr_log_path = Path(f"{ITER147_STDERR_LOG_TMPDIR_BASENAME_PREFIX_FOR_PER_RUN_CAPTURE_FILES}{run_index_one_indexed}.log")
    print(f"  → run {run_index_one_indexed}: capturing semantic-release --dry-run stderr → {per_run_stderr_log_path}", file=sys.stderr)
    with open(per_run_stderr_log_path, "w", encoding="utf-8") as per_run_stderr_log_handle:
        completed_process_for_this_run = subprocess.run(
            ["npx", "semantic-release", "--dry-run", "--no-ci"],
            cwd=repo_root_absolute_path,
            stdout=subprocess.DEVNULL,
            stderr=per_run_stderr_log_handle,
            env={**os.environ, "DEBUG": "semantic-release:*"},
            check=False,
        )
    if completed_process_for_this_run.returncode != 0:
        print(f"    ⚠ run {run_index_one_indexed} exited with code {completed_process_for_this_run.returncode} (continuing — variance harness tolerates non-zero exit)", file=sys.stderr)
    return per_run_stderr_log_path


def iter147_invoke_iter144_parser_on_one_per_run_stderr_log_capturing_dimension_1_namespace_timings_and_whole_pipeline_elapsed(
    iter144_parser_absolute_path: Path,
    per_run_stderr_log_path: Path,
    aggregator: Iter147PerNamespaceTimingDistributionAcrossNRunsAggregator,
) -> None:
    completed_process_for_iter144_parse = subprocess.run(
        [sys.executable, str(iter144_parser_absolute_path), str(per_run_stderr_log_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    parser_combined_output_for_regex_extraction = completed_process_for_iter144_parse.stdout + completed_process_for_iter144_parse.stderr

    in_dimension_1_namespace_block_currently = False
    for parser_output_line in parser_combined_output_for_regex_extraction.split("\n"):
        if "ACCURATE per-subsystem bottleneck ranking" in parser_output_line:
            in_dimension_1_namespace_block_currently = True
            continue
        if "plugin-lifecycle-steps by loading-phase" in parser_output_line:
            in_dimension_1_namespace_block_currently = False
            continue
        if in_dimension_1_namespace_block_currently:
            match_per_namespace_timing_line = ITER147_NAMESPACE_TIMING_REGEX_FROM_ITER144_PARSER_OUTPUT_LINE_DIMENSION_1_ACCURATE.match(parser_output_line)
            if match_per_namespace_timing_line:
                elapsed_milliseconds_from_iter144_dimension_1 = int(match_per_namespace_timing_line.group(1))
                namespace_name_from_iter144_dimension_1 = match_per_namespace_timing_line.group(2)
                aggregator.record_per_namespace_elapsed_ms_for_this_single_dry_run_capture(
                    namespace_name_from_iter144_dimension_1,
                    elapsed_milliseconds_from_iter144_dimension_1,
                )

        match_whole_pipeline_elapsed_footer = ITER147_WHOLE_PIPELINE_ELAPSED_REGEX_FROM_ITER144_PARSER_FOOTER_LINE.search(parser_output_line)
        if match_whole_pipeline_elapsed_footer:
            aggregator.record_whole_pipeline_elapsed_ms_for_this_single_dry_run_capture(
                int(match_whole_pipeline_elapsed_footer.group(1))
            )


def iter147_render_per_namespace_timing_distribution_summary_table_sorted_descending_by_p50_with_variance_trap_flag(
    aggregator: Iter147PerNamespaceTimingDistributionAcrossNRunsAggregator,
    n_runs_executed: int,
) -> None:
    print("")
    print("═══════════════════════════════════════════════════════════════════════════════")
    print(f"  ITER-147 VARIANCE CHARACTERIZATION: per-namespace timing distribution across {n_runs_executed} runs")
    print("═══════════════════════════════════════════════════════════════════════════════")
    print("")

    header_row_columns_formatted_fixed_width_for_human_readable_table = (
        f"  {'namespace':<42} {'p50':>6} {'p95':>6} {'mean':>6} {'stddev':>7} {'min':>6} {'max':>6} {'range':>6}  variance-flag"
    )
    print(header_row_columns_formatted_fixed_width_for_human_readable_table)
    print(f"  {'-' * 42} {'-' * 6} {'-' * 6} {'-' * 6} {'-' * 7} {'-' * 6} {'-' * 6} {'-' * 6}  -------------")

    per_namespace_p50_for_sort_key_descending = [
        (namespace, iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method(elapsed_ms_list, 50))
        for namespace, elapsed_ms_list in aggregator.namespace_to_per_run_elapsed_milliseconds_list_collected_across_n_back_to_back_dry_run_captures.items()
    ]
    per_namespace_p50_for_sort_key_descending.sort(key=lambda tup: tup[1], reverse=True)

    high_variance_trap_namespace_count = 0
    for namespace_name_for_this_row, p50_milliseconds_for_this_row in per_namespace_p50_for_sort_key_descending:
        per_run_elapsed_ms_list_for_this_namespace = aggregator.namespace_to_per_run_elapsed_milliseconds_list_collected_across_n_back_to_back_dry_run_captures[namespace_name_for_this_row]
        p95_for_this_row = iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method(per_run_elapsed_ms_list_for_this_namespace, 95)
        mean_for_this_row = int(round(statistics.mean(per_run_elapsed_ms_list_for_this_namespace)))
        stddev_for_this_row = iter147_compute_stddev_of_integer_value_sample_list_returns_zero_for_single_value_or_empty(per_run_elapsed_ms_list_for_this_namespace)
        min_for_this_row = min(per_run_elapsed_ms_list_for_this_namespace)
        max_for_this_row = max(per_run_elapsed_ms_list_for_this_namespace)
        range_for_this_row = max_for_this_row - min_for_this_row

        variance_trap_flag_render_for_this_row = ""
        if p50_milliseconds_for_this_row > 0:
            stddev_over_p50_ratio = stddev_for_this_row / p50_milliseconds_for_this_row
            if stddev_over_p50_ratio > ITER147_VARIANCE_FLAG_HIGH_STDDEV_TO_P50_RATIO_THRESHOLD_FOR_TRAP_WARNING:
                variance_trap_flag_render_for_this_row = f"⚠ HIGH (σ/p50={stddev_over_p50_ratio:.2f})"
                high_variance_trap_namespace_count += 1

        print(
            f"  {namespace_name_for_this_row:<42} "
            f"{p50_milliseconds_for_this_row:>6} "
            f"{p95_for_this_row:>6} "
            f"{mean_for_this_row:>6} "
            f"{stddev_for_this_row:>7.1f} "
            f"{min_for_this_row:>6} "
            f"{max_for_this_row:>6} "
            f"{range_for_this_row:>6}  {variance_trap_flag_render_for_this_row}"
        )

    if high_variance_trap_namespace_count > 0:
        print("")
        print(f"  ⚠ {high_variance_trap_namespace_count} namespace(s) flagged HIGH variance (σ/p50 > {ITER147_VARIANCE_FLAG_HIGH_STDDEV_TO_P50_RATIO_THRESHOLD_FOR_TRAP_WARNING}).")
        print("    Single-sample comparisons on flagged namespaces are UNRELIABLE — use the p50/p95 columns")
        print("    above for any before/after perf-claim. This is the iter-143-style trap this harness exists")
        print("    to prevent.")

    if aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures:
        whole_pipeline_p50 = iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method(aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures, 50)
        whole_pipeline_p95 = iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method(aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures, 95)
        whole_pipeline_stddev = iter147_compute_stddev_of_integer_value_sample_list_returns_zero_for_single_value_or_empty(aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures)
        whole_pipeline_min = min(aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures)
        whole_pipeline_max = max(aggregator.whole_pipeline_elapsed_milliseconds_per_run_list_across_n_back_to_back_dry_run_captures)
        print("")
        print(
            f"  ⧗ Whole-debug-log elapsed across {n_runs_executed} runs: "
            f"p50={whole_pipeline_p50}ms, p95={whole_pipeline_p95}ms, "
            f"stddev={whole_pipeline_stddev:.1f}ms, "
            f"min={whole_pipeline_min}ms, max={whole_pipeline_max}ms"
        )

    print("")
    print("  ⧗ tune via ITER147_VARIANCE_PROFILE_RUN_COUNT=N (default 5)")
    print("  ⧗ replay without re-running via ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS=1")


def iter147_main_entry_point_orchestrates_n_back_to_back_captures_then_aggregates_and_renders_distribution() -> int:
    repo_root_absolute_path = Path(__file__).resolve().parent.parent
    iter144_parser_absolute_path = iter147_locate_iter144_parser_absolute_path_from_sibling_scripts_directory_relative_to_this_iter147_harness()

    n_back_to_back_captures = int(os.environ.get("ITER147_VARIANCE_PROFILE_RUN_COUNT", str(ITER147_DEFAULT_NUMBER_OF_BACK_TO_BACK_DRY_RUN_CAPTURES_FOR_VARIANCE_CHARACTERIZATION)))
    if n_back_to_back_captures < 2:
        print(f"  ✗ ITER147_VARIANCE_PROFILE_RUN_COUNT must be ≥ 2 (got {n_back_to_back_captures}) — variance is undefined for a single sample", file=sys.stderr)
        return 2

    replay_existing_logs_without_re_running = os.environ.get("ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS", "0") == "1"

    print(f"  ⧗ ITER-147 VARIANCE CHARACTERIZATION HARNESS (n={n_back_to_back_captures} back-to-back dry-run captures)")
    if replay_existing_logs_without_re_running:
        print(f"  ⧗ REPLAY mode — reading existing /tmp/iter147-variance-profile-run-*.log without re-running")

    aggregator = Iter147PerNamespaceTimingDistributionAcrossNRunsAggregator()
    wall_clock_start_of_whole_harness_for_total_elapsed_report = time.time()

    for run_index_one_indexed in range(1, n_back_to_back_captures + 1):
        per_run_stderr_log_path: Path
        if replay_existing_logs_without_re_running:
            per_run_stderr_log_path = Path(f"{ITER147_STDERR_LOG_TMPDIR_BASENAME_PREFIX_FOR_PER_RUN_CAPTURE_FILES}{run_index_one_indexed}.log")
            if not per_run_stderr_log_path.is_file():
                print(f"  ✗ REPLAY: expected log {per_run_stderr_log_path} not found — abort", file=sys.stderr)
                return 3
        else:
            per_run_stderr_log_path = iter147_run_one_semantic_release_dry_run_capture_writing_stderr_to_per_run_log_file(
                run_index_one_indexed, repo_root_absolute_path
            )
        iter147_invoke_iter144_parser_on_one_per_run_stderr_log_capturing_dimension_1_namespace_timings_and_whole_pipeline_elapsed(
            iter144_parser_absolute_path, per_run_stderr_log_path, aggregator
        )

    wall_clock_end_of_whole_harness_for_total_elapsed_report = time.time()
    iter147_render_per_namespace_timing_distribution_summary_table_sorted_descending_by_p50_with_variance_trap_flag(
        aggregator, n_back_to_back_captures
    )

    total_harness_wall_clock_elapsed_seconds_for_operator_visibility = (
        wall_clock_end_of_whole_harness_for_total_elapsed_report
        - wall_clock_start_of_whole_harness_for_total_elapsed_report
    )
    print(f"  ⧗ Whole-harness wall-clock elapsed: {total_harness_wall_clock_elapsed_seconds_for_operator_visibility:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(iter147_main_entry_point_orchestrates_n_back_to_back_captures_then_aggregates_and_renders_distribution())
