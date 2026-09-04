#!/usr/bin/env python3
# FILE-SIZE-OK: Single-file analytics CLI for a single JSONL schema. Splitting
# the metric-computation helpers, the record dataclass, the parser, and the
# CLI into separate modules would fragment cohesion without reducing
# complexity — every helper here is a small pure function over the same
# ParsedGatewayStateRecord dataclass and is consumed only by the single
# render_full_operator_report_to_stdout coordinator. ~560 lines stays under
# the 1000-line hard block.
# SSoT-OK: Standalone read-only CLI; module-level constants
# (DEFAULT_GATEWAY_STATE_JSONL_LOG_PATH, DEFAULT_LOOKBACK_WINDOW_SPECIFIER,
# SUPPORTED_METRIC_NAMES, TIME_WINDOW_UNIT_TO_SECONDS_MULTIPLIER) ARE the
# config and are validated at the CLI boundary
# (parse_command_line_arguments_into_namespace) per SSoT principle #3
# (Entry-Point Validation). A Config Singleton would add ceremony without
# any cross-call state to centralize. The JSONL log path is overridable via
# --jsonl per SSoT principle #2 (None-default + resolver pattern: CLI arg
# OR DEFAULT_GATEWAY_STATE_JSONL_LOG_PATH).
"""Gateway telemetry analytics CLI for the statusline-tools plugin.

Reads ~/.claude/gateway-state.jsonl (the per-render structured log appended
by plugins/statusline-tools/statusline/custom-statusline.sh's L2 statistics
surface) and emits a time-windowed operator report covering:

  * Uptime / reachability percentage broken down by gateway state
  * Failure-status distribution (verbatim official HTTP statuses from schema v2, 2026-06-11; AU/QT/CF/UP/IN letter codes in pre-v2 records aggregate identically
    taxonomy) so the operator can see which failure dimension dominated the
    window
  * Unified-state-name distribution (since-boot / flapping / partial-outage /
    outage / healthy) — the actionable severity histogram
  * State-machine transition counts (how many times the gateway flipped
    between unified states across the window) — leading indicator of
    flapping behavior even when point-in-time samples look healthy
  * Pre-warning event timeline (wrapper-skew, wrapper-at-floor, pool-thin,
    partial-outage) — when each pre-warning fired during the window
  * Pool-resilience-state-machine distribution (healthy / degraded /
    partial-outage / total-outage) — orthogonal to canary state per the
    L1d design

Usage:
    gateway-telemetry-analytics-from-statusline-jsonl-log.py [--since <window>]
                                                              [--metric <name>]
                                                              [--jsonl <path>]

    --since <window>     Time window starting from now, lookback. Accepts
                         '15m', '1h', '24h', '7d', '30d'. Default: '24h'.
    --metric <name>      Optional. One of: uptime, type-codes, state-names,
                         state-transitions, pre-warnings, pool-health, all.
                         Default: 'all' (single comprehensive report).
    --jsonl <path>       Override the default log path
                         ~/.claude/gateway-state.jsonl (useful for testing).

Citations / design references:
    - Schema documented inline in custom-statusline.sh (search for "L2
      STATISTICS SURFACE — JSONL append per render")
    - Failure values: official HTTP statuses verbatim (schema v2); pre-v2 letter codes
    - State-machine: Envoy outlier-detection + Resilience4j adapted to
      finite-N rotation pool
    - Time-window report style: Google SRE Workbook chapter on alerting on
      SLOs (multi-window, multi-burn-rate)

The CLI is intentionally read-only — never mutates the JSONL log. The log is
append-only and grows ~1 record per statusline render (~1 KB per line). A
companion --prune flag could be added later (task #7 follow-up); not in
scope for this initial implementation.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from time import time
from typing import Iterable


# Schema v3 (2026-09-04) renamed every field's `doorward_` prefix to
# `gateway_` and the log file itself. Records written before that rename are
# still perfectly good data, so this reader is deliberately tolerant of BOTH
# spellings rather than silently scoring old records as zeros — a rename that
# quietly zeroes history looks exactly like an outage that never happened.
LEGACY_SCHEMA_FIELD_PREFIX = "doorward_"
CURRENT_SCHEMA_FIELD_PREFIX = "gateway_"

# Fields whose SUFFIX also changed in v3, so the plain prefix swap above cannot
# reach them. Kept explicit (rather than clever) because a missed entry here
# fails silently as a default value, which reads as real data.
EXPLICIT_LEGACY_FIELD_ALIASES = {
    "gateway_local_client_version": "doorward_local_ccmax_claude_wrapper_version",
}


def _read_schema_field(parsed_object: dict, field_name: str, default):
    """Read a field, accepting the pre-v3 `doorward_*` spelling as a fallback."""
    if field_name in parsed_object:
        return parsed_object[field_name]
    explicit_alias = EXPLICIT_LEGACY_FIELD_ALIASES.get(field_name)
    if explicit_alias is not None and explicit_alias in parsed_object:
        return parsed_object[explicit_alias]
    if field_name.startswith(CURRENT_SCHEMA_FIELD_PREFIX):
        legacy_name = LEGACY_SCHEMA_FIELD_PREFIX + field_name[
            len(CURRENT_SCHEMA_FIELD_PREFIX):
        ]
        if legacy_name in parsed_object:
            return parsed_object[legacy_name]
    return default


def _resolve_default_state_log_path() -> Path:
    """Prefer the current log name; fall back to the pre-v3 name if only it exists."""
    current = Path.home() / ".claude" / "gateway-state.jsonl"
    if current.exists():
        return current
    legacy = Path.home() / ".claude" / "doorward-state.jsonl"
    if legacy.exists():
        return legacy
    return current


DEFAULT_GATEWAY_STATE_JSONL_LOG_PATH = _resolve_default_state_log_path()
DEFAULT_LOOKBACK_WINDOW_SPECIFIER = "24h"
SUPPORTED_METRIC_NAMES = (
    "uptime",
    "type-codes",
    "state-names",
    "state-transitions",
    "pre-warnings",
    "pool-health",
    "all",
)
TIME_WINDOW_SPECIFIER_REGEX_WITH_UNIT_SUFFIX = re.compile(
    r"^(?P<quantity>\d+)(?P<unit>[smhdw])$"
)
TIME_WINDOW_UNIT_TO_SECONDS_MULTIPLIER = {
    "s": 1,
    "m": 60,
    "h": 60 * 60,
    "d": 60 * 60 * 24,
    "w": 60 * 60 * 24 * 7,
}


@dataclass
class ParsedGatewayStateRecord:
    """One render's-worth of parsed gateway telemetry primitives."""

    wall_clock_unix_seconds: int
    gateway_gateway_legacy_binary_gate_status: str
    gateway_pool_schedulable_active_accounts_count: int
    gateway_pool_rotation_working_set_size: int
    gateway_pool_error_accounts_count: int
    gateway_pool_resilience_state_machine_label: str
    gateway_canary_consecutive_failures: int
    gateway_canary_classification_four_state: str
    gateway_canary_failure_type_code: str
    gateway_canary_failure_duration_humanized: str
    gateway_canary_real_traffic_damper_engaged: bool
    gateway_unified_state_name_for_render: str
    gateway_local_client_version: str
    gateway_minimum_supported_wrapper_version_floor: str
    gateway_wrapper_skew_present: bool
    gateway_wrapper_at_floor_pre_warn: bool
    gateway_pin_scope_active: str
    gateway_pin_mode_active: str
    gateway_bearer_mode_routing_active: bool


def parse_lookback_window_specifier_to_seconds_lower_bound(
    raw_window_specifier_with_unit_suffix: str,
) -> int:
    """Convert e.g. '24h' into 86400, '7d' into 604800. Raises on malformed."""
    match = TIME_WINDOW_SPECIFIER_REGEX_WITH_UNIT_SUFFIX.fullmatch(
        raw_window_specifier_with_unit_suffix.strip().lower()
    )
    if not match:
        raise ValueError(
            f"unrecognized time window specifier: "
            f"{raw_window_specifier_with_unit_suffix!r}; "
            f"expected forms like '15m', '1h', '24h', '7d', '4w'"
        )
    quantity = int(match.group("quantity"))
    unit = match.group("unit")
    return quantity * TIME_WINDOW_UNIT_TO_SECONDS_MULTIPLIER[unit]


def iterate_gateway_state_jsonl_records_from_file(
    gateway_state_jsonl_log_absolute_path: Path,
) -> Iterable[ParsedGatewayStateRecord]:
    """Stream-parse each JSONL line; skip lines that fail to parse."""
    if not gateway_state_jsonl_log_absolute_path.exists():
        return
    with gateway_state_jsonl_log_absolute_path.open(
        "r", encoding="utf-8", errors="replace"
    ) as f:
        for raw_line in f:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                parsed_object = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            try:
                yield ParsedGatewayStateRecord(
                    wall_clock_unix_seconds=int(
                        parsed_object["wall_clock_unix_seconds"]
                    ),
                    gateway_gateway_legacy_binary_gate_status=str(
                        _read_schema_field(parsed_object, 
                            "gateway_gateway_legacy_binary_gate_status", ""
                        )
                    ),
                    gateway_pool_schedulable_active_accounts_count=int(
                        _read_schema_field(parsed_object, 
                            "gateway_pool_schedulable_active_accounts_count", 0
                        )
                    ),
                    gateway_pool_rotation_working_set_size=int(
                        _read_schema_field(parsed_object, 
                            "gateway_pool_rotation_working_set_size", 0
                        )
                    ),
                    gateway_pool_error_accounts_count=int(
                        _read_schema_field(parsed_object, 
                            "gateway_pool_error_accounts_count", 0
                        )
                    ),
                    gateway_pool_resilience_state_machine_label=str(
                        _read_schema_field(parsed_object, 
                            "gateway_pool_resilience_state_machine_label", ""
                        )
                    ),
                    gateway_canary_consecutive_failures=int(
                        _read_schema_field(parsed_object, 
                            "gateway_canary_consecutive_failures", 0
                        )
                    ),
                    gateway_canary_classification_four_state=str(
                        _read_schema_field(parsed_object, 
                            "gateway_canary_classification_four_state", ""
                        )
                    ),
                    gateway_canary_failure_type_code=str(
                        _read_schema_field(parsed_object, "gateway_canary_failure_type_code", "")
                    ),
                    gateway_canary_failure_duration_humanized=str(
                        _read_schema_field(parsed_object, 
                            "gateway_canary_failure_duration_humanized", ""
                        )
                    ),
                    gateway_canary_real_traffic_damper_engaged=bool(
                        _read_schema_field(parsed_object, 
                            "gateway_canary_real_traffic_damper_engaged", False
                        )
                    ),
                    gateway_unified_state_name_for_render=str(
                        _read_schema_field(parsed_object, 
                            "gateway_unified_state_name_for_render", ""
                        )
                    ),
                    gateway_local_client_version=str(
                        _read_schema_field(parsed_object, 
                            "gateway_local_client_version", ""
                        )
                    ),
                    gateway_minimum_supported_wrapper_version_floor=str(
                        _read_schema_field(parsed_object, 
                            "gateway_minimum_supported_wrapper_version_floor", ""
                        )
                    ),
                    gateway_wrapper_skew_present=bool(
                        _read_schema_field(parsed_object, "gateway_wrapper_skew_present", False)
                    ),
                    gateway_wrapper_at_floor_pre_warn=bool(
                        _read_schema_field(parsed_object, 
                            "gateway_wrapper_at_floor_pre_warn", False
                        )
                    ),
                    gateway_pin_scope_active=str(
                        _read_schema_field(parsed_object, "gateway_pin_scope_active", "")
                    ),
                    gateway_pin_mode_active=str(
                        _read_schema_field(parsed_object, "gateway_pin_mode_active", "")
                    ),
                    gateway_bearer_mode_routing_active=bool(
                        _read_schema_field(parsed_object, 
                            "gateway_bearer_mode_routing_active", False
                        )
                    ),
                )
            except (KeyError, ValueError, TypeError):
                continue


def filter_records_within_lookback_window_from_now(
    parsed_records: Iterable[ParsedGatewayStateRecord],
    lookback_seconds: int,
) -> list[ParsedGatewayStateRecord]:
    """Keep only records whose wall_clock falls within the lookback window."""
    cutoff_unix_seconds = int(time()) - lookback_seconds
    return [
        record
        for record in parsed_records
        if record.wall_clock_unix_seconds >= cutoff_unix_seconds
    ]


def compute_uptime_reachability_percentage_by_gateway_status(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, tuple[int, float]]:
    """Counts each value of gateway_gateway_legacy_binary_gate_status plus %."""
    if not parsed_records_within_window:
        return {}
    gateway_status_counter = Counter(
        record.gateway_gateway_legacy_binary_gate_status
        for record in parsed_records_within_window
    )
    total_records_count = len(parsed_records_within_window)
    return {
        status_name: (count, 100.0 * count / total_records_count)
        for status_name, count in gateway_status_counter.most_common()
    }


def compute_failure_type_code_distribution_among_non_healthy_records(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, tuple[int, float]]:
    """Counts AU / QT / CF / UP / IN occurrences within non-healthy renders."""
    non_healthy_records = [
        record
        for record in parsed_records_within_window
        if record.gateway_canary_failure_type_code
    ]
    if not non_healthy_records:
        return {}
    type_code_counter = Counter(
        record.gateway_canary_failure_type_code for record in non_healthy_records
    )
    total_non_healthy_records_count = len(non_healthy_records)
    return {
        type_code: (count, 100.0 * count / total_non_healthy_records_count)
        for type_code, count in type_code_counter.most_common()
    }


def compute_unified_state_name_distribution_across_all_records(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, tuple[int, float]]:
    """Counts each unified-state-name value plus % of total records."""
    if not parsed_records_within_window:
        return {}
    unified_state_name_counter = Counter(
        record.gateway_unified_state_name_for_render
        for record in parsed_records_within_window
    )
    total_records_count = len(parsed_records_within_window)
    return {
        state_name: (count, 100.0 * count / total_records_count)
        for state_name, count in unified_state_name_counter.most_common()
    }


def count_unified_state_machine_transitions_between_consecutive_records(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, int]:
    """Count "from→to" transitions for the unified state name."""
    if len(parsed_records_within_window) < 2:
        return {}
    transitions_counter: Counter[str] = Counter()
    previous_state_name = parsed_records_within_window[0].gateway_unified_state_name_for_render
    for record in parsed_records_within_window[1:]:
        current_state_name = record.gateway_unified_state_name_for_render
        if current_state_name != previous_state_name:
            transition_key = f"{previous_state_name}→{current_state_name}"
            transitions_counter[transition_key] += 1
            previous_state_name = current_state_name
    return dict(transitions_counter.most_common())


def collect_pre_warning_event_timestamps_from_records(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, list[int]]:
    """Collect the unix timestamps where each pre-warning flag was true."""
    pre_warning_timestamps: dict[str, list[int]] = {
        "gateway_wrapper_skew_present": [],
        "gateway_wrapper_at_floor_pre_warn": [],
        "gateway_pool_resilience_partial_outage": [],
    }
    for record in parsed_records_within_window:
        if record.gateway_wrapper_skew_present:
            pre_warning_timestamps["gateway_wrapper_skew_present"].append(
                record.wall_clock_unix_seconds
            )
        if record.gateway_wrapper_at_floor_pre_warn:
            pre_warning_timestamps["gateway_wrapper_at_floor_pre_warn"].append(
                record.wall_clock_unix_seconds
            )
        if (
            record.gateway_pool_resilience_state_machine_label
            == "partial-outage"
        ):
            pre_warning_timestamps[
                "gateway_pool_resilience_partial_outage"
            ].append(record.wall_clock_unix_seconds)
    return pre_warning_timestamps


def compute_pool_resilience_state_distribution_across_all_records(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
) -> dict[str, tuple[int, float]]:
    """Counts each pool_resilience_state_machine_label plus % of total records."""
    if not parsed_records_within_window:
        return {}
    pool_state_counter = Counter(
        record.gateway_pool_resilience_state_machine_label
        for record in parsed_records_within_window
    )
    total_records_count = len(parsed_records_within_window)
    return {
        pool_state: (count, 100.0 * count / total_records_count)
        for pool_state, count in pool_state_counter.most_common()
    }


def format_unix_timestamp_as_iso_utc_short_form(unix_seconds: int) -> str:
    """ISO-style timestamp string. Avoids datetime import bloat for one helper."""
    import datetime as dt_module

    return (
        dt_module.datetime.fromtimestamp(unix_seconds, tz=dt_module.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ")
    )


def render_full_operator_report_to_stdout(
    parsed_records_within_window: list[ParsedGatewayStateRecord],
    lookback_window_specifier_raw_string: str,
    requested_metric_subset_name: str,
) -> None:
    """Print the human-readable text report. Sections gated by --metric."""
    sample_count = len(parsed_records_within_window)
    print(
        f"# Gateway telemetry analytics report",
        f"# window: last {lookback_window_specifier_raw_string} "
        f"({sample_count} render samples)",
        sep="\n",
    )
    if sample_count == 0:
        print(
            "# (no gateway-state.jsonl records found within the window — "
            "either the statusline hasn't rendered recently or the log path "
            "is empty)"
        )
        return

    earliest_timestamp = parsed_records_within_window[0].wall_clock_unix_seconds
    latest_timestamp = parsed_records_within_window[-1].wall_clock_unix_seconds
    print(
        f"# earliest sample: {format_unix_timestamp_as_iso_utc_short_form(earliest_timestamp)}",
        f"# latest sample:   {format_unix_timestamp_as_iso_utc_short_form(latest_timestamp)}",
        sep="\n",
    )

    should_render_metric = (
        lambda metric_name: requested_metric_subset_name == "all"
        or requested_metric_subset_name == metric_name
    )

    if should_render_metric("uptime"):
        print("\n## Gateway reachability (gateway_gateway_legacy_binary_gate_status)")
        for status_name, (
            count,
            percentage_of_total,
        ) in compute_uptime_reachability_percentage_by_gateway_status(
            parsed_records_within_window
        ).items():
            print(f"  {status_name:<15s}  {count:>6d}  {percentage_of_total:>6.2f}%")

    if should_render_metric("type-codes"):
        print(
            "\n## Failure status distribution among non-healthy renders "
            "(official HTTP statuses from schema v2; letter codes in pre-v2 records)"
        )
        type_distribution = (
            compute_failure_type_code_distribution_among_non_healthy_records(
                parsed_records_within_window
            )
        )
        if not type_distribution:
            print("  (no non-healthy renders in window)")
        else:
            for type_code, (count, percentage_of_non_healthy) in type_distribution.items():
                print(
                    f"  {type_code:<3s}  {count:>6d}  "
                    f"{percentage_of_non_healthy:>6.2f}%"
                )

    if should_render_metric("state-names"):
        print("\n## Unified state-name distribution (operator-facing label)")
        for state_name, (
            count,
            percentage_of_total,
        ) in compute_unified_state_name_distribution_across_all_records(
            parsed_records_within_window
        ).items():
            print(f"  {state_name:<18s}  {count:>6d}  {percentage_of_total:>6.2f}%")

    if should_render_metric("state-transitions"):
        print("\n## State-machine transitions between consecutive renders")
        transitions = count_unified_state_machine_transitions_between_consecutive_records(
            parsed_records_within_window
        )
        if not transitions:
            print("  (no transitions within window)")
        else:
            for transition_key, count in transitions.items():
                print(f"  {transition_key:<40s}  {count:>6d}")

    if should_render_metric("pre-warnings"):
        print("\n## Pre-warning event timestamps (unix seconds)")
        pre_warning_event_timestamps = (
            collect_pre_warning_event_timestamps_from_records(
                parsed_records_within_window
            )
        )
        for pre_warning_flag_name, timestamps in pre_warning_event_timestamps.items():
            if timestamps:
                first_ts = format_unix_timestamp_as_iso_utc_short_form(timestamps[0])
                last_ts = format_unix_timestamp_as_iso_utc_short_form(timestamps[-1])
                print(
                    f"  {pre_warning_flag_name:<45s}  fired={len(timestamps):>5d}  "
                    f"first={first_ts}  last={last_ts}"
                )
            else:
                print(f"  {pre_warning_flag_name:<45s}  (none in window)")

    if should_render_metric("pool-health"):
        print(
            "\n## Pool-resilience state distribution "
            "(Envoy outlier-detection + Resilience4j state machine)"
        )
        for pool_state_name, (
            count,
            percentage_of_total,
        ) in compute_pool_resilience_state_distribution_across_all_records(
            parsed_records_within_window
        ).items():
            print(
                f"  {pool_state_name:<18s}  {count:>6d}  {percentage_of_total:>6.2f}%"
            )


def parse_command_line_arguments_into_namespace() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Time-windowed operator report from "
            "~/.claude/gateway-state.jsonl (appended by the statusline-tools "
            "plugin on every statusline render). Read-only."
        )
    )
    parser.add_argument(
        "--since",
        default=DEFAULT_LOOKBACK_WINDOW_SPECIFIER,
        help=(
            "Lookback window from now. Forms: '15m', '1h', '24h', '7d', '4w'. "
            f"Default: {DEFAULT_LOOKBACK_WINDOW_SPECIFIER}."
        ),
    )
    parser.add_argument(
        "--metric",
        default="all",
        choices=SUPPORTED_METRIC_NAMES,
        help="Restrict the report to a single metric. Default: all.",
    )
    parser.add_argument(
        "--jsonl",
        default=str(DEFAULT_GATEWAY_STATE_JSONL_LOG_PATH),
        help=(
            "Override the JSONL log path (default: "
            f"{DEFAULT_GATEWAY_STATE_JSONL_LOG_PATH})."
        ),
    )
    return parser.parse_args()


def main() -> int:
    parsed_args = parse_command_line_arguments_into_namespace()
    try:
        lookback_seconds = (
            parse_lookback_window_specifier_to_seconds_lower_bound(
                parsed_args.since
            )
        )
    except ValueError as parse_error:
        print(f"error: {parse_error}", file=sys.stderr)
        return 2
    gateway_state_jsonl_log_path = Path(os.path.expanduser(parsed_args.jsonl))
    all_parsed_records = list(
        iterate_gateway_state_jsonl_records_from_file(
            gateway_state_jsonl_log_path
        )
    )
    parsed_records_within_window = filter_records_within_lookback_window_from_now(
        all_parsed_records, lookback_seconds
    )
    render_full_operator_report_to_stdout(
        parsed_records_within_window,
        lookback_window_specifier_raw_string=parsed_args.since,
        requested_metric_subset_name=parsed_args.metric,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
