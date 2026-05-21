#!/usr/bin/env python3
"""iter-144: semantic-release plugin-lifecycle-step timing instrumentation.

Parses a captured `DEBUG=semantic-release:* npx semantic-release ...` stderr
log file and emits a top-N slowest plugin-lifecycle-step ranking with
cumulative elapsed-milliseconds summed per (plugin, lifecycle-step) tuple.

Why this script exists:
    Iter-139 RELEASE_TIMING_PROFILE pipeline-level instrumentation revealed
    Phase 2 (`mise run release:version` — semantic-release) consumes ~30s of
    the ~45-49s release wall-clock (67% of pipeline). Iter-142 / iter-143
    confirmed that the post-release successCmd block (iter-140 instrumented)
    is only ~2.3s, meaning the actual 28s lives INSIDE semantic-release
    plugin internals. Iter-143 tried optimizing @semantic-release/github
    config options that online research surfaced as community-validated
    bottlenecks — but the empirical wall-clock did not drop (variance even
    made v21.58.4 come in 4.6s slower than v21.58.3). The conclusion:
    further optimization without instrumentation is gambling.

    This parser closes the visibility gap. semantic-release uses the `debug`
    npm module which, when `DEBUG=semantic-release:*` is set, emits stderr
    lines prefixed with ISO8601 timestamps + namespace
    (`semantic-release:config`, `semantic-release:plugins`, etc.). When the
    `debug` module emits without a TTY, it uses the timestamp-prefixed
    format (no `+Nms` deltas — those only appear in TTY mode).

    The parser:
      1. Walks the log line-by-line tracking the currently-active plugin
         lifecycle step (extracted from `semantic-release:plugins options
         for <PLUGIN>/<STEP>:` marker lines).
      2. For each timestamped line, computes the millisecond delta from the
         previous timestamped line and attributes it to the currently-active
         plugin-lifecycle-step.
      3. Multi-line JSON-dump continuations (without their own timestamp
         prefix) are correctly skipped — they're already accounted for in
         the previous timestamped line's delta-to-next-line.
      4. Emits a top-N slowest plugin-lifecycle-step ranking sorted
         descending by cumulative elapsed-milliseconds, matching the
         iter-130 / iter-139 / iter-140 ranking output convention.

Output convention:
    Mirrors iter-130/139/140 top-N ranking:
        ⧗ ─── Top N slowest semantic-release plugin-lifecycle-steps
             (iter-144 plugin-pipeline bottleneck ranking) ───
              1.   N1 ms  PLUGIN_1/STEP_1
              2.   N2 ms  PLUGIN_2/STEP_2
              ...

Limitations (documented honestly, not glossed over):
    - In `--dry-run` mode semantic-release SKIPS the publish + success
      lifecycle steps. Their entry-point "options for X" log lines still
      appear, but only ~1-2ms of timing is captured per skipped step
      because the body isn't executed. To time the publish/success steps
      accurately, the parser must be run against a LIVE release log (e.g.
      `DEBUG=semantic-release:* mise run release:version 2> /tmp/log;
      ./scripts/iter144-...py /tmp/log`).
    - The currently-active step before the first "options for X" marker
      is attributed to the "(unattributed-pre-plugin-pipeline-bootstrap)"
      bucket (typically config-load / get-tags / get-commits — runs once,
      shows up as a single small bucket).
    - The script is python3 not bash+awk because portable parsing of
      ISO8601 timestamps requires datetime.fromisoformat() which gawk's
      mktime() can emulate but BSD awk on macOS cannot. python3 is already
      required throughout the codebase (sync-versions.mjs has python deps
      in preflight; iter-143 regression test uses python3 for YAML parsing).

Usage:
    python3 scripts/iter144-...py <debug-log-file>
    [ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY=N]
        (default 10, mirrors iter-130/139/140 top-N convention)
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import os
import re
import sys
from dataclasses import dataclass, field

# ─── Constants (self-documenting names per CLAUDE.md directive) ───────────────

ITER144_DEBUG_NAMESPACE_PREFIX_FOR_SEMANTIC_RELEASE_NPM_MODULE_LOG_LINES = (
    "semantic-release:"
)

ITER144_LIFECYCLE_STEP_MARKER_REGEX_FROM_DEBUG_PLUGINS_NAMESPACE_OPTIONS_FOR_LINE = (
    re.compile(
        r"^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s+"
        r"semantic-release:plugins\s+"
        r"options for "
        r"(?P<plugin_lifecycle_step_with_provenance>[^:\s]+):"
    )
)

ITER144_ISO8601_TIMESTAMP_LINE_PREFIX_REGEX_FOR_DEBUG_NPM_MODULE_OUTPUT_LINES = (
    re.compile(
        r"^(?P<iso8601_timestamp_string>\d{4}-\d{2}-\d{2}T[\d:.]+Z)\s+"
        r"(?P<remainder_of_debug_line_after_timestamp_prefix>.*)$"
    )
)

# Captures the `semantic-release:<namespace>` immediately after the timestamp.
# Examples: semantic-release:config, semantic-release:plugins, semantic-release:git,
# semantic-release:get-git-auth-url, semantic-release:get-tags, semantic-release:get-commits
ITER144_DEBUG_NAMESPACE_REGEX_FOR_SECOND_RANKING_DIMENSION_PER_NPM_DEBUG_MODULE_NAMESPACE = (
    re.compile(
        r"^\d{4}-\d{2}-\d{2}T[\d:.]+Z\s+"
        r"(?P<debug_namespace_after_iso8601_timestamp_prefix>semantic-release:[a-zA-Z0-9_-]+)"
    )
)

ITER144_UNATTRIBUTED_PRE_PLUGIN_PIPELINE_BOOTSTRAP_BUCKET_LABEL_FOR_LINES_BEFORE_FIRST_OPTIONS_FOR_MARKER = (
    "(pre-plugin-pipeline-bootstrap — config-load + get-tags + get-commits)"
)

ITER144_DEFAULT_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY_IN_RANKING_OUTPUT = 10

ITER144_OPERATOR_TUNABLE_TOP_N_OVERRIDE_ENVIRONMENT_VARIABLE_NAME = (
    "ITER144_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY"
)


# ─── Data classes ─────────────────────────────────────────────────────────────


@dataclass
class Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry:
    """One bucket of cumulative elapsed-ms attributed to one plugin lifecycle step."""

    plugin_lifecycle_step_label_with_provenance_from_debug_plugins_options_for_marker_line: str
    cumulative_elapsed_milliseconds_summed_across_all_timestamp_deltas_attributed_to_this_step: float = 0.0
    log_line_count_attributed_to_this_step: int = 0


@dataclass
class Iter144DebugLogParseResult:
    """Aggregate result of walking the debug log."""

    per_plugin_lifecycle_step_cumulative_elapsed_milliseconds_accumulator_keyed_by_plugin_step_label: dict[
        str,
        Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry,
    ] = field(default_factory=dict)
    # Second ranking dimension: per debug-namespace cumulative ms. This is the
    # ACCURATE attribution for executed work (e.g., semantic-release:git +
    # semantic-release:get-git-auth-url captures SSH auth verification +
    # git ops). The "options-for plugin/step" ranking above is only meaningful
    # for the plugin-LOADING phase — post-iter-144-discovery known to
    # MISATTRIBUTE post-loading execution to whichever step was last loaded
    # (typically `@semantic-release/exec/fail` since `fail` is the last
    # lifecycle step in plugin config order). Debug-namespace ranking does
    # not suffer this misattribution because every executed code path has
    # its own namespace.
    per_debug_namespace_cumulative_elapsed_milliseconds_accumulator_keyed_by_npm_debug_module_namespace_label: dict[
        str,
        Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry,
    ] = field(default_factory=dict)
    # Forensic finding from iter-144 dry-run instrumentation: count occurrences
    # of "SyntaxError: undefined is not valid JSON" stack traces emitted by
    # the silent `catch (error) { debug(error); }` in semantic-release's
    # getTagsNotes (node_modules/semantic-release/lib/git.js:346). These come
    # from tags with empty notes refs at refs/notes/semantic-release-vX.Y.Z
    # (per iter-144 forensic: v4.9.0, v4.10.0, v5.1.0, v5.1.2, v5.1.4 in
    # this repo). Each one wastes CPU on stack-trace generation + logging
    # per release. Fix scheduled for iter-146.
    silent_json_parse_syntax_error_stack_trace_occurrence_count_from_get_tags_notes_swallowed_catch_block: int = (
        0
    )
    total_timestamped_log_lines_parsed_from_debug_namespace_stderr_output: int = 0
    total_log_lines_skipped_as_multiline_continuation_without_iso8601_prefix: int = 0
    first_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation: _datetime.datetime | None = (
        None
    )
    last_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation: _datetime.datetime | None = (
        None
    )


# ─── Core parser ──────────────────────────────────────────────────────────────


def iter144_parse_semantic_release_debug_namespace_stderr_log_file_into_per_plugin_lifecycle_step_cumulative_elapsed_milliseconds_accumulator(
    debug_log_file_absolute_path: str,
) -> Iter144DebugLogParseResult:
    """Walk a captured semantic-release DEBUG stderr log; build per-step cumulative-ms accumulator.

    Algorithm:
        1. Track the currently-active plugin lifecycle step (string label).
        2. For each line with an ISO8601 timestamp prefix, compute the
           delta-ms from the previously-seen timestamped line and attribute
           it to the currently-active step.
        3. When a line matches the "options for PLUGIN/STEP:" marker,
           transition the currently-active step to that new label.
        4. Multi-line continuations (lines without ISO8601 prefix) are
           skipped — their content is already accounted for in the
           previous-to-next timestamped-line delta.
    """
    aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds = (
        Iter144DebugLogParseResult()
    )

    currently_active_plugin_lifecycle_step_label_with_provenance_inherited_from_most_recent_options_for_marker = ITER144_UNATTRIBUTED_PRE_PLUGIN_PIPELINE_BOOTSTRAP_BUCKET_LABEL_FOR_LINES_BEFORE_FIRST_OPTIONS_FOR_MARKER
    previous_log_line_debug_namespace_label_for_per_namespace_cumulative_elapsed_ms_attribution: str = (
        "(pre-first-debug-line)"
    )

    previous_timestamped_log_line_iso8601_datetime_for_delta_computation_to_next_timestamped_line: _datetime.datetime | None = (
        None
    )

    with open(debug_log_file_absolute_path, encoding="utf-8") as debug_log_file_handle:
        for raw_log_line_from_debug_namespace_stderr_capture in debug_log_file_handle:
            stripped_log_line_with_trailing_newline_removed = (
                raw_log_line_from_debug_namespace_stderr_capture.rstrip("\n")
            )

            iso8601_prefix_match = (
                ITER144_ISO8601_TIMESTAMP_LINE_PREFIX_REGEX_FOR_DEBUG_NPM_MODULE_OUTPUT_LINES.match(
                    stripped_log_line_with_trailing_newline_removed
                )
            )

            if iso8601_prefix_match is None:
                # Multi-line continuation (e.g. JSON dump body) — skipped because
                # the next timestamped line will close out its parent's delta.
                aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.total_log_lines_skipped_as_multiline_continuation_without_iso8601_prefix += 1
                continue

            iso8601_timestamp_string_from_current_log_line = iso8601_prefix_match.group(
                "iso8601_timestamp_string"
            )
            current_log_line_iso8601_datetime_parsed_from_string_prefix = (
                _datetime.datetime.fromisoformat(
                    iso8601_timestamp_string_from_current_log_line.replace("Z", "+00:00")
                )
            )

            aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.total_timestamped_log_lines_parsed_from_debug_namespace_stderr_output += 1

            if (
                aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.first_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation
                is None
            ):
                aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.first_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation = current_log_line_iso8601_datetime_parsed_from_string_prefix
            aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.last_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation = current_log_line_iso8601_datetime_parsed_from_string_prefix

            if previous_timestamped_log_line_iso8601_datetime_for_delta_computation_to_next_timestamped_line is not None:
                delta_milliseconds_since_previous_timestamped_log_line = (
                    current_log_line_iso8601_datetime_parsed_from_string_prefix
                    - previous_timestamped_log_line_iso8601_datetime_for_delta_computation_to_next_timestamped_line
                ).total_seconds() * 1000.0

                # Dimension 1: per (plugin/lifecycle-step) ranking. Known
                # misattribution post-loading-phase — documented in output.
                step_accumulator_entry = aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.per_plugin_lifecycle_step_cumulative_elapsed_milliseconds_accumulator_keyed_by_plugin_step_label.setdefault(
                    currently_active_plugin_lifecycle_step_label_with_provenance_inherited_from_most_recent_options_for_marker,
                    Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry(
                        plugin_lifecycle_step_label_with_provenance_from_debug_plugins_options_for_marker_line=currently_active_plugin_lifecycle_step_label_with_provenance_inherited_from_most_recent_options_for_marker
                    ),
                )
                step_accumulator_entry.cumulative_elapsed_milliseconds_summed_across_all_timestamp_deltas_attributed_to_this_step += delta_milliseconds_since_previous_timestamped_log_line
                step_accumulator_entry.log_line_count_attributed_to_this_step += 1

                # Dimension 2: per (debug-namespace) ranking. ACCURATE
                # attribution — every executed code path has its own
                # namespace, no marker-based misattribution.
                namespace_accumulator_entry = aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.per_debug_namespace_cumulative_elapsed_milliseconds_accumulator_keyed_by_npm_debug_module_namespace_label.setdefault(
                    previous_log_line_debug_namespace_label_for_per_namespace_cumulative_elapsed_ms_attribution,
                    Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry(
                        plugin_lifecycle_step_label_with_provenance_from_debug_plugins_options_for_marker_line=previous_log_line_debug_namespace_label_for_per_namespace_cumulative_elapsed_ms_attribution
                    ),
                )
                namespace_accumulator_entry.cumulative_elapsed_milliseconds_summed_across_all_timestamp_deltas_attributed_to_this_step += delta_milliseconds_since_previous_timestamped_log_line
                namespace_accumulator_entry.log_line_count_attributed_to_this_step += 1

            # Extract debug-namespace from current line for the NEXT line's
            # delta attribution.
            current_line_debug_namespace_match = ITER144_DEBUG_NAMESPACE_REGEX_FOR_SECOND_RANKING_DIMENSION_PER_NPM_DEBUG_MODULE_NAMESPACE.match(
                stripped_log_line_with_trailing_newline_removed
            )
            if current_line_debug_namespace_match is not None:
                previous_log_line_debug_namespace_label_for_per_namespace_cumulative_elapsed_ms_attribution = current_line_debug_namespace_match.group(
                    "debug_namespace_after_iso8601_timestamp_prefix"
                )

            # Forensic count: silent JSON.parse SyntaxError stack traces from
            # the swallowed catch block in getTagsNotes (iter-144 discovery).
            if "SyntaxError" in stripped_log_line_with_trailing_newline_removed and (
                'is not valid JSON' in stripped_log_line_with_trailing_newline_removed
            ):
                aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds.silent_json_parse_syntax_error_stack_trace_occurrence_count_from_get_tags_notes_swallowed_catch_block += 1

            # Transition currently-active step if this line is an "options for" marker.
            options_for_marker_match = ITER144_LIFECYCLE_STEP_MARKER_REGEX_FROM_DEBUG_PLUGINS_NAMESPACE_OPTIONS_FOR_LINE.match(
                stripped_log_line_with_trailing_newline_removed
            )
            if options_for_marker_match is not None:
                currently_active_plugin_lifecycle_step_label_with_provenance_inherited_from_most_recent_options_for_marker = options_for_marker_match.group(
                    "plugin_lifecycle_step_with_provenance"
                )

            previous_timestamped_log_line_iso8601_datetime_for_delta_computation_to_next_timestamped_line = current_log_line_iso8601_datetime_parsed_from_string_prefix

    return aggregate_parse_result_carrying_per_step_accumulator_and_wall_clock_bounds


def _iter144_render_one_ranking_dimension_as_top_n_sorted_descending_by_cumulative_elapsed_milliseconds(
    human_readable_ranking_dimension_label: str,
    accumulator_keyed_by_bucket_label: dict[
        str,
        Iter144PluginLifecycleStepCumulativeElapsedMillisecondsAccumulatorEntry,
    ],
    top_n_threshold: int,
    explanatory_caveat_about_attribution_accuracy: str,
) -> None:
    """Helper to render one ranking dimension. DRY for the dual-ranking output."""
    if not accumulator_keyed_by_bucket_label:
        print(f"  ⧗ iter-144: {human_readable_ranking_dimension_label} — no data", file=sys.stderr)
        return

    sorted_entries_descending = sorted(
        accumulator_keyed_by_bucket_label.values(),
        key=lambda entry: entry.cumulative_elapsed_milliseconds_summed_across_all_timestamp_deltas_attributed_to_this_step,
        reverse=True,
    )

    print("")
    print(f"  ⧗ ─── {human_readable_ranking_dimension_label} ───")
    for rank_one_indexed, entry in enumerate(sorted_entries_descending[:top_n_threshold], start=1):
        print(
            f"      {rank_one_indexed:2d}. "
            f"{entry.cumulative_elapsed_milliseconds_summed_across_all_timestamp_deltas_attributed_to_this_step:6.0f} ms  "
            f"{entry.plugin_lifecycle_step_label_with_provenance_from_debug_plugins_options_for_marker_line}"
        )
    if explanatory_caveat_about_attribution_accuracy:
        print(f"  ⧗ {explanatory_caveat_about_attribution_accuracy}")


def iter144_render_top_n_slowest_plugin_lifecycle_step_bottleneck_ranking_summary_to_stdout(
    aggregate_parse_result_from_debug_log_walker: Iter144DebugLogParseResult,
    top_n_threshold_for_slowest_plugin_lifecycle_step_ranking_display: int,
) -> None:
    """Emit DUAL top-N rankings + forensic findings.

    Dimension 1 (debug-namespace, ACCURATE): every executed code path has
    its own namespace, no marker-based misattribution. This is the
    actionable ranking for finding which semantic-release subsystem
    consumes wall-clock (config-load / git ops / get-tags / get-commits /
    get-git-auth-url SSH verification / plugins-pipeline).

    Dimension 2 (plugin/lifecycle-step, LOADING-PHASE-ONLY): based on
    "options-for PLUGIN/STEP" markers in the debug log. Only accurate
    during the plugin-LOADING phase. Post-loading work gets misattributed
    to whichever step was loaded LAST (typically `@semantic-release/exec/
    fail` because `fail` is the last lifecycle step in plugin config
    order). Documented in output for honesty.

    Forensic finding: count of silent JSON.parse SyntaxError stack traces
    swallowed by getTagsNotes catch block (iter-144 discovery; per-tag
    cost from refs/notes/semantic-release-vX.Y.Z with empty content).
    """
    whole_log_wall_clock_milliseconds = 0.0
    if (
        aggregate_parse_result_from_debug_log_walker.first_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation
        is not None
        and aggregate_parse_result_from_debug_log_walker.last_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation
        is not None
    ):
        whole_log_wall_clock_milliseconds = (
            aggregate_parse_result_from_debug_log_walker.last_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation
            - aggregate_parse_result_from_debug_log_walker.first_log_line_iso8601_timestamp_observed_for_whole_log_wall_clock_calculation
        ).total_seconds() * 1000.0

    # Dimension 1: per debug-namespace (ACCURATE).
    _iter144_render_one_ranking_dimension_as_top_n_sorted_descending_by_cumulative_elapsed_milliseconds(
        human_readable_ranking_dimension_label=(
            f"Top {top_n_threshold_for_slowest_plugin_lifecycle_step_ranking_display} "
            f"slowest semantic-release debug-namespaces "
            f"(iter-144 ACCURATE per-subsystem bottleneck ranking)"
        ),
        accumulator_keyed_by_bucket_label=aggregate_parse_result_from_debug_log_walker.per_debug_namespace_cumulative_elapsed_milliseconds_accumulator_keyed_by_npm_debug_module_namespace_label,
        top_n_threshold=top_n_threshold_for_slowest_plugin_lifecycle_step_ranking_display,
        explanatory_caveat_about_attribution_accuracy=(
            "This dimension is the actionable target for further optimization."
        ),
    )

    # Dimension 2: per plugin/lifecycle-step (LOADING-PHASE-ONLY).
    _iter144_render_one_ranking_dimension_as_top_n_sorted_descending_by_cumulative_elapsed_milliseconds(
        human_readable_ranking_dimension_label=(
            f"Top {top_n_threshold_for_slowest_plugin_lifecycle_step_ranking_display} "
            f"plugin-lifecycle-steps by loading-phase elapsed-ms "
            f"(iter-144 supplementary ranking; LOADING-PHASE-ONLY)"
        ),
        accumulator_keyed_by_bucket_label=aggregate_parse_result_from_debug_log_walker.per_plugin_lifecycle_step_cumulative_elapsed_milliseconds_accumulator_keyed_by_plugin_step_label,
        top_n_threshold=top_n_threshold_for_slowest_plugin_lifecycle_step_ranking_display,
        explanatory_caveat_about_attribution_accuracy=(
            "CAVEAT: post-loading execution misattributes to the LAST loaded step "
            "(typically `@semantic-release/exec/fail`). Use dimension 1 above for "
            "actionable per-subsystem ms attribution."
        ),
    )

    print("")
    print(
        f"  ⧗ (override top-N count via {ITER144_OPERATOR_TUNABLE_TOP_N_OVERRIDE_ENVIRONMENT_VARIABLE_NAME}=N)"
    )
    print(
        f"  ⧗ whole-debug-log elapsed: {whole_log_wall_clock_milliseconds:.0f}ms across "
        f"{aggregate_parse_result_from_debug_log_walker.total_timestamped_log_lines_parsed_from_debug_namespace_stderr_output} timestamped lines + "
        f"{aggregate_parse_result_from_debug_log_walker.total_log_lines_skipped_as_multiline_continuation_without_iso8601_prefix} continuation lines"
    )

    # Forensic finding: silent JSON.parse SyntaxError occurrences.
    forensic_count = aggregate_parse_result_from_debug_log_walker.silent_json_parse_syntax_error_stack_trace_occurrence_count_from_get_tags_notes_swallowed_catch_block
    if forensic_count > 0:
        print("")
        print(
            f"  ⚠ FORENSIC FINDING (iter-144): {forensic_count} silent JSON.parse SyntaxError stack traces "
            "swallowed by getTagsNotes catch block (node_modules/semantic-release/lib/git.js:346)."
        )
        print(
            "    Root cause: tags with empty `refs/notes/semantic-release-vX.Y.Z` notes — "
            "JS coerces undefined to string 'undefined' → JSON.parse fails → debug(error) "
            "logs stack trace + continues silently."
        )
        print(
            "    Cost: stack-trace generation + logging per occurrence (sub-second total, "
            "but pure waste). Fix scheduled for iter-145+."
        )

    print(
        "  ⧗ NOTE: in --dry-run mode, publish/success step bodies are skipped — "
        "namespace timing reflects only verifyConditions/analyzeCommits/generateNotes/prepare. "
        "Capture a LIVE release log to time publish/success steps accurately."
    )


# ─── CLI entry point ──────────────────────────────────────────────────────────


def iter144_main_entry_point_parses_cli_args_invokes_debug_log_walker_and_renders_top_n_ranking() -> (
    int
):
    cli_argument_parser_for_iter144_debug_log_parser_script = argparse.ArgumentParser(
        description=(
            "iter-144 semantic-release plugin-lifecycle-step timing parser. "
            "Reads a captured DEBUG=semantic-release:* stderr log file; "
            "emits top-N slowest plugin-lifecycle-step bottleneck ranking."
        )
    )
    cli_argument_parser_for_iter144_debug_log_parser_script.add_argument(
        "debug_log_file_absolute_path",
        type=str,
        help="Path to captured `DEBUG=semantic-release:* npx semantic-release ...` stderr log",
    )
    parsed_cli_arguments_namespace = (
        cli_argument_parser_for_iter144_debug_log_parser_script.parse_args()
    )

    if not os.path.exists(parsed_cli_arguments_namespace.debug_log_file_absolute_path):
        print(
            f"iter-144: debug log file not found: {parsed_cli_arguments_namespace.debug_log_file_absolute_path}",
            file=sys.stderr,
        )
        return 1

    top_n_threshold_resolved_from_env_or_default = int(
        os.environ.get(
            ITER144_OPERATOR_TUNABLE_TOP_N_OVERRIDE_ENVIRONMENT_VARIABLE_NAME,
            ITER144_DEFAULT_TOP_N_SLOWEST_PLUGIN_LIFECYCLE_STEPS_TO_DISPLAY_IN_RANKING_OUTPUT,
        )
    )

    aggregate_parse_result = iter144_parse_semantic_release_debug_namespace_stderr_log_file_into_per_plugin_lifecycle_step_cumulative_elapsed_milliseconds_accumulator(
        parsed_cli_arguments_namespace.debug_log_file_absolute_path
    )
    iter144_render_top_n_slowest_plugin_lifecycle_step_bottleneck_ranking_summary_to_stdout(
        aggregate_parse_result, top_n_threshold_resolved_from_env_or_default
    )
    return 0


if __name__ == "__main__":
    sys.exit(
        iter144_main_entry_point_parses_cli_args_invokes_debug_log_walker_and_renders_top_n_ranking()
    )
