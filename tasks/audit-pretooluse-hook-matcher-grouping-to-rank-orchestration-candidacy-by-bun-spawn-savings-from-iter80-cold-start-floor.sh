#!/usr/bin/env bash
#MISE description="Iter-81 orchestration-candidacy ranker: scans every plugins/*/hooks/hooks.json for PreToolUse entries, groups them by matcher signature (e.g., Write|Edit, Bash, Bash|Write|Edit), and ranks each group by potential bun-spawn savings if N hooks in the group were combined into a single orchestrator process (iter-66 stop-orchestrator pattern applied to PreToolUse). Uses the iter-80 measured ~44ms bun-cold-start floor as the per-hook unit cost. Identifies which hook groupings are the highest-value targets for combining into a multi-subhook orchestrator. Sets up future iters with data-driven prioritization."
#
# audit-pretooluse-hook-matcher-grouping-to-rank-orchestration-candidacy-by-bun-spawn-savings-from-iter80-cold-start-floor
#
# Iter-81 audit — companion to iter-80's edit-time-hook-cold-start-cost-
# profiler. Background:
#
#   Iter-80 forensic measurement found that bun cold-start (~44 ms)
#   dominates edit-time hook overhead, NOT in-hook logic. Within-hook
#   "fastpath" optimizations save at most ~8ms per hook — marginal.
#   The high-leverage optimization is to REDUCE THE BUN SPAWN COUNT.
#
#   The iter-66 stop-orchestrator precedent (5 Stop subhooks → 1 bun
#   process) provides the architectural template. To apply the same
#   pattern to PreToolUse, we need to know:
#
#     1. Which matcher signatures have MULTIPLE hooks (the orchestration
#        candidates).
#     2. The bun-spawn savings if each multi-hook group were combined
#        (= group_size - 1 spawns saved).
#     3. The estimated wall-clock savings (= bun-spawn savings × 44 ms).
#
# This audit produces the ranked report.
#
# Methodology:
#
#   For each plugins/<plugin>/hooks/hooks.json:
#     - jq extract every PreToolUse hook's matcher signature.
#     - For each (plugin, matcher) tuple, count how many hooks share it.
#     - Compute spawn savings = max(0, count - 1).
#     - Compute estimated wall-clock savings = spawn savings × 44 ms.
#
#   Note on matcher overlap: Claude Code interprets matchers as
#   alternation regexes — `Write|Edit` matches BOTH Write and Edit
#   invocations. So a single Write invocation fires every hook whose
#   matcher includes "Write" (or is null/empty for wildcard). For this
#   audit we group by EXACT matcher signature (string equality), not
#   by tool-name overlap, because the orchestrator pattern requires
#   the combined hooks to share the SAME matcher signature.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Task lives at .mise/tasks/<task>.sh — repo root is two levels up.
REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

# Per-hook bun-spawn cost calibrated from iter-80's profiler. If the
# bun runtime changes materially (e.g., bun 2.x reduces cold-start),
# re-run iter-80's profiler and update this constant.
ITER80_MEASURED_BUN_COLD_START_FLOOR_MILLISECONDS_PER_HOOK_SPAWN=44

# Threshold for "high-value orchestration candidate": at least N hooks
# in the same matcher group. With 3+ hooks, savings = ≥(3-1) × 44 =
# ≥88 ms — meaningful relative to typical edit-time budgets.
HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD=3

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Iter-81 PreToolUse Orchestration-Candidacy Ranker"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Per-hook bun-spawn cost (iter-80 calibration):"
echo "    ${ITER80_MEASURED_BUN_COLD_START_FLOOR_MILLISECONDS_PER_HOOK_SPAWN} ms"
echo "  High-value group-size threshold (≥${HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD} hooks per matcher):"
echo "    ≥$(( (HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD - 1) \
       * ITER80_MEASURED_BUN_COLD_START_FLOOR_MILLISECONDS_PER_HOOK_SPAWN )) ms savings if combined"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Stage 1: Collect every (plugin, matcher, hook_basename) tuple.
# ---------------------------------------------------------------------------
plugin_matcher_hook_basename_tuples_for_grouping=()

while IFS= read -r single_hooks_json_path; do
    [[ -f "$single_hooks_json_path" ]] || continue
    plugin_directory_basename="$(basename "$(dirname "$(dirname "$single_hooks_json_path")")")"

    # jq emits one TSV row per PreToolUse hook entry:
    # <matcher>\t<first-command-basename>
    while IFS=$'\t' read -r matcher_signature hook_command_basename; do
        [[ -z "$matcher_signature" && -z "$hook_command_basename" ]] && continue
        plugin_matcher_hook_basename_tuples_for_grouping+=(
            "$plugin_directory_basename"$'\t'"$matcher_signature"$'\t'"$hook_command_basename"
        )
    done < <(
        jq -r '.hooks.PreToolUse // [] | .[] |
               (.matcher // "<wildcard>") as $m |
               .hooks[] |
               [$m, (.command | split("/")[-1])] | @tsv' \
            "$single_hooks_json_path" 2>/dev/null
    )
done < <(find "$REPO_ROOT/plugins" -maxdepth 3 -name 'hooks.json' -type f 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Stage 2: Group by (plugin, matcher) — count hooks per group.
# ---------------------------------------------------------------------------

# Build a deduplicated list of (plugin, matcher) pairs with their hook
# lists. Use a sorted intermediate file for grouping (bash arrays don't
# offer efficient group-by).
all_tuples_sorted_for_grouping=$(
    printf '%s\n' "${plugin_matcher_hook_basename_tuples_for_grouping[@]}" \
        | sort
)

# Format each group as: <count>\t<plugin>\t<matcher>\t<hook1,hook2,...>
declare -a per_group_records_with_count_plugin_matcher_hooklist=()

current_group_key_plugin_matcher=""
current_group_member_hook_basenames=()
current_group_hook_count=0

emit_completed_group_to_records_array() {
    if [[ -n "$current_group_key_plugin_matcher" ]]; then
        local hooklist_csv
        hooklist_csv=$(
            printf '%s,' "${current_group_member_hook_basenames[@]}" \
                | sed 's/,$//'
        )
        per_group_records_with_count_plugin_matcher_hooklist+=(
            "$current_group_hook_count"$'\t'"$current_group_key_plugin_matcher"$'\t'"$hooklist_csv"
        )
    fi
}

while IFS=$'\t' read -r tuple_plugin tuple_matcher tuple_hook_basename; do
    [[ -z "$tuple_plugin" ]] && continue
    candidate_group_key="$tuple_plugin"$'\t'"$tuple_matcher"
    if [[ "$candidate_group_key" != "$current_group_key_plugin_matcher" ]]; then
        emit_completed_group_to_records_array
        current_group_key_plugin_matcher="$candidate_group_key"
        current_group_member_hook_basenames=()
        current_group_hook_count=0
    fi
    current_group_member_hook_basenames+=("$tuple_hook_basename")
    current_group_hook_count=$((current_group_hook_count + 1))
done <<< "$all_tuples_sorted_for_grouping"
emit_completed_group_to_records_array

# ---------------------------------------------------------------------------
# Stage 3: Sort by group size descending and render the ranked report.
# ---------------------------------------------------------------------------

sorted_groups_descending_by_hook_count=$(
    printf '%s\n' "${per_group_records_with_count_plugin_matcher_hooklist[@]}" \
        | sort -t$'\t' -k1,1 -rn
)

echo "Ranked PreToolUse orchestration candidates (descending by bun-spawn savings):"
echo ""
printf "  %-5s | %-10s | %-30s | %-7s | %-7s | hooks\n" \
    "rank" "savings" "plugin" "matcher" "size"
printf "  %-5s-+-%-10s-+-%-30s-+-%-7s-+-%-7s-+-%s\n" \
    "-----" "----------" "------------------------------" "-------" "-------" "----"

total_high_value_orchestration_candidates=0
total_aggregate_estimated_wall_clock_savings_milliseconds_if_all_combined=0
current_rank_in_sorted_descending_report=0

while IFS=$'\t' read -r group_hook_count group_plugin_name group_matcher_signature group_hook_basename_csv; do
    [[ -z "$group_hook_count" ]] && continue
    current_rank_in_sorted_descending_report=$((current_rank_in_sorted_descending_report + 1))

    bun_spawns_saved_if_group_were_combined=$((group_hook_count - 1))
    if [[ "$bun_spawns_saved_if_group_were_combined" -lt 0 ]]; then
        bun_spawns_saved_if_group_were_combined=0
    fi
    estimated_wall_clock_savings_milliseconds_for_this_group=$((
        bun_spawns_saved_if_group_were_combined
        * ITER80_MEASURED_BUN_COLD_START_FLOOR_MILLISECONDS_PER_HOOK_SPAWN
    ))

    # Truncate hook list for column-width readability.
    truncated_hook_basename_list_for_display="$group_hook_basename_csv"
    if [[ "${#truncated_hook_basename_list_for_display}" -gt 60 ]]; then
        truncated_hook_basename_list_for_display="${truncated_hook_basename_list_for_display:0:57}..."
    fi

    printf "  %-5d | %5d ms  | %-30s | %-7s | %-7d | %s\n" \
        "$current_rank_in_sorted_descending_report" \
        "$estimated_wall_clock_savings_milliseconds_for_this_group" \
        "$group_plugin_name" \
        "$group_matcher_signature" \
        "$group_hook_count" \
        "$truncated_hook_basename_list_for_display"

    if [[ "$group_hook_count" -ge "$HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD" ]]; then
        total_high_value_orchestration_candidates=$((
            total_high_value_orchestration_candidates + 1
        ))
        total_aggregate_estimated_wall_clock_savings_milliseconds_if_all_combined=$((
            total_aggregate_estimated_wall_clock_savings_milliseconds_if_all_combined
            + estimated_wall_clock_savings_milliseconds_for_this_group
        ))
    fi
done <<< "$sorted_groups_descending_by_hook_count"

# ---------------------------------------------------------------------------
# Stage 4: Summary.
# ---------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
total_distinct_groups_analyzed=${#per_group_records_with_count_plugin_matcher_hooklist[@]}
printf "  Total distinct (plugin, matcher) groups analyzed:      %d\n" \
    "$total_distinct_groups_analyzed"
printf "  High-value orchestration candidates (≥%d hooks/group):  %d\n" \
    "$HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD" \
    "$total_high_value_orchestration_candidates"
printf "  Aggregate wall-clock savings if all combined:          %d ms\n" \
    "$total_aggregate_estimated_wall_clock_savings_milliseconds_if_all_combined"
echo ""

if [[ "$total_high_value_orchestration_candidates" -gt 0 ]]; then
    echo "  Recommendation:"
    echo "    The TOP-RANKED group above is the highest-leverage iter-66-style"
    echo "    orchestrator target. Each combined-hook orchestrator saves"
    echo "    (group_size - 1) × ${ITER80_MEASURED_BUN_COLD_START_FLOOR_MILLISECONDS_PER_HOOK_SPAWN} ms per matching tool invocation."
    echo ""
    echo "    Architectural precedent: plugins/itp-hooks/hooks/stop-orchestrator.ts"
    echo "    (iter-66 — combines 5 Stop subhooks into 1 bun process with"
    echo "    per-subhook timeout + crash isolation)."
    echo ""
    echo "    Risk-management checklist for migration:"
    echo "      1. Each combined subhook must preserve its existing"
    echo "         deny-semantics (first-deny-wins is the standard pattern)."
    echo "      2. Per-subhook regression tests must still pass — either"
    echo "         via direct import of the subhook's classifier function OR"
    echo "         via invocation of the orchestrator with a payload that"
    echo "         targets the specific subhook's branch."
    echo "      3. The orchestrator must implement per-subhook timeout +"
    echo "         crash isolation (one bad subhook can NOT take down the"
    echo "         entire decision chain)."
    echo "      4. Original subhook files SHOULD remain on disk (don't"
    echo "         delete) so future migration to native execution is"
    echo "         reversible."
else
    echo "  No high-value orchestration candidates found."
    echo "  All matcher groups have <${HIGH_VALUE_ORCHESTRATION_CANDIDATE_MINIMUM_GROUP_SIZE_THRESHOLD} hooks; bun-spawn savings from combining would be"
    echo "  marginal. Re-run after any future hook additions."
fi

echo ""
echo "  Forensic baseline source:"
echo "    iter-80 — Edit-Time PreToolUse Hook Cold-Start Cost Profiler"
echo "    Documented in: docs/HOOKS.md 'Edit-Time Hook Overhead Cost Model'"

exit 0
