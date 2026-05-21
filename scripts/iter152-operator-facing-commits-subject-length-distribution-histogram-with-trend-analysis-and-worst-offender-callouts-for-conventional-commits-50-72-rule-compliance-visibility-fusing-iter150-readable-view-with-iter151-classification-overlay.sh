#!/usr/bin/env bash
# iter-152 operator-facing commits-health dashboard.
#
# WHY THIS EXISTS:
#
#   The iter-150 / iter-151 arc surfaced the conventional-commits 50/72-rule
#   readability defect (iter-144-through-iter-149 produced 754-1078 char
#   subjects) and built two layers:
#
#     iter-150  → readable git-log VIEW (awk-based soft-wrap renderer)
#     iter-151  → preflight Check 4l DETECTOR (informational overlay)
#
#   But neither surface gives operators a consolidated DASHBOARD to answer
#   "how is my commit-subject health doing right now, and is it trending
#   in the right direction?". The audit task name is 138 chars long and
#   undiscoverable; the iter-150 renderer doesn't include classification
#   context; there is no trend signal showing whether the iter-150
#   convention adoption is actually working.
#
#   This iter-152 wrapper closes the usability arc by fusing iter-150 +
#   iter-151 + new aggregations (histogram, worst-offender callouts,
#   recent-vs-previous trend signal) into a single short-named command:
#
#     mise run commits:health
#
# WHAT IT DOES:
#
#   Renders five panels:
#
#     Panel 1: Readable view of last N commits (delegates to iter-150
#              renderer for the awk-based soft-wrap rendering)
#
#     Panel 2: Subject-length distribution histogram with bins anchored
#              on the conventional-commits 50/72 industry rule:
#                ≤50 chars     (industry hard target — GitHub UI safe)
#                51-72 chars   (industry hard cap — commitlint default)
#                73-100 chars  (mild over-cap)
#                101-200 chars (verbose-naming-era over-cap)
#                201-500 chars (heavy verbose)
#                501-1000 chars (extreme)
#                1000+ chars   (iter-144-149 cohort outlier territory)
#
#     Panel 3: Worst-offender callouts (top 3 by char count) so operators
#              can target their attention
#
#     Panel 4: Conventional-commits type distribution (feat/fix/perf/
#              chore/docs/refactor/test/build/ci/style/revert) — gives
#              operators visibility into release-cadence drivers
#
#     Panel 5: Recent-vs-previous trend signal — compares median subject
#              length and ≤72-conformance rate between the current N-commit
#              window and the previous N-commit window. Δ percentage point
#              shift + improving/regressing verdict.
#
# USAGE:
#
#   # Default: last 10 commits, compare to previous 10
#   mise run commits:health
#
#   # Custom window size
#   ITER152_COMMIT_COUNT_TO_ANALYZE=20 mise run commits:health
#
#   # Custom hard-cap threshold (operators on stricter projects)
#   ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS=50 mise run commits:health
#
# DESIGN NOTES:
#
#   - Histogram rendering uses simple block characters (██░░) with bar
#     widths capped at 20 columns for predictable terminal fit
#   - All counts derived from a single git-log invocation piped to awk
#     for performance (no per-commit subprocess fork)
#   - Trend comparison uses median (p50) rather than mean to be robust
#     against the iter-144-149 cohort outliers (1000+ chars) which would
#     otherwise dominate any mean-based signal
#   - "Improving" defined as: current-median < previous-median AND
#     current-conformance-rate > previous-conformance-rate. "Regressing"
#     is strict opposite. "Mixed" otherwise.
#
# PRIOR ART:
#
#   - https://www.conventionalcommits.org/en/v1.0.0/ — the canonical spec
#   - https://cbea.ms/git-commit/ — Seven Rules of git commit messages
#   - https://github.com/0x404/conventional-commit-classification —
#     community prior art validating the classification approach

set -euo pipefail

ITER152_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER152_REPO_ROOT"

# ─── Operator-tunable knobs ─────────────────────────────────────────────────
ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW="${ITER152_COMMIT_COUNT_TO_ANALYZE:-10}"
ITER152_DEFAULT_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE="${ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS:-72}"
ITER152_DEFAULT_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE="${ITER152_SUBJECT_HARD_TARGET_THRESHOLD_CHARS:-50}"
ITER152_DEFAULT_HISTOGRAM_BAR_MAX_WIDTH_IN_TERMINAL_COLUMNS="${ITER152_HISTOGRAM_BAR_WIDTH:-20}"
ITER152_DEFAULT_NUMBER_OF_WORST_OFFENDERS_TO_CALL_OUT_IN_PANEL_3="${ITER152_WORST_OFFENDER_CALLOUT_COUNT:-3}"

# ─── ANSI color codes (TTY-only gracefully degrade) ─────────────────────────
if [[ -t 1 ]]; then
    ITER152_ANSI_COLOR_BOLD="$(printf '\033[1m')"
    ITER152_ANSI_COLOR_GREEN_FOR_IMPROVING_SIGNAL="$(printf '\033[32m')"
    ITER152_ANSI_COLOR_RED_FOR_REGRESSING_SIGNAL="$(printf '\033[31m')"
    ITER152_ANSI_COLOR_YELLOW_FOR_MIXED_SIGNAL="$(printf '\033[33m')"
    ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS="$(printf '\033[36m')"
    ITER152_ANSI_COLOR_RESET="$(printf '\033[0m')"
else
    ITER152_ANSI_COLOR_BOLD=""
    ITER152_ANSI_COLOR_GREEN_FOR_IMPROVING_SIGNAL=""
    ITER152_ANSI_COLOR_RED_FOR_REGRESSING_SIGNAL=""
    ITER152_ANSI_COLOR_YELLOW_FOR_MIXED_SIGNAL=""
    ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS=""
    ITER152_ANSI_COLOR_RESET=""
fi

# ─── Panel renderers ────────────────────────────────────────────────────────

iter152_emit_dashboard_header_banner_with_window_and_threshold_metadata() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ${ITER152_ANSI_COLOR_BOLD}COMMITS HEALTH${ITER152_ANSI_COLOR_RESET} (iter-152: iter-150 view + iter-151 classification + iter-152 trend)"
    echo "  window=${ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW}commits  hard-target=${ITER152_DEFAULT_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE}chars  hard-cap=${ITER152_DEFAULT_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE}chars"
    echo "═══════════════════════════════════════════════════════════════════════════════"
}

iter152_render_panel_1_iter150_readable_view_by_delegating_to_iter150_renderer_for_consistency() {
    echo ""
    echo "${ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS}─── Panel 1: Readable view (iter-150 renderer) ───${ITER152_ANSI_COLOR_RESET}"
    local iter150_renderer_script_absolute_path
    iter150_renderer_script_absolute_path="$ITER152_REPO_ROOT/scripts/iter150-readable-git-log-renderer-with-awk-based-soft-wrap-of-verbose-conventional-commit-subjects-to-eighty-column-terminal-width-with-color-decorations-and-indentation-for-operator-readability.sh"
    if [[ -x "$iter150_renderer_script_absolute_path" ]]; then
        ITER150_COMMIT_COUNT_TO_DISPLAY="$ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW" \
            "$iter150_renderer_script_absolute_path" 2>/dev/null \
            | awk '/^═+$/ { count++; if (count >= 1 && count <= 2) next } count >= 1 && !/⧗ tune via/ && !/⧗ pass extra/ && !/^ITER-150/ { print }' \
            | sed -e '1,/^$/d' \
            | head -60 || true
    else
        echo "  ✗ iter-150 renderer not found (expected at $iter150_renderer_script_absolute_path)"
    fi
}

iter152_render_panel_2_subject_length_distribution_histogram_with_50_72_rule_anchored_bins() {
    echo ""
    echo "${ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS}─── Panel 2: Subject-length distribution histogram (bins per 50/72 rule) ───${ITER152_ANSI_COLOR_RESET}"

    # Single awk pass over git log subjects → bin counts → ASCII bars.
    git log -"$ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW" --pretty=format:'%s' 2>/dev/null \
        | awk \
            -v hard_target="$ITER152_DEFAULT_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE" \
            -v hard_cap="$ITER152_DEFAULT_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE" \
            -v bar_max_width="$ITER152_DEFAULT_HISTOGRAM_BAR_MAX_WIDTH_IN_TERMINAL_COLUMNS" '
            {
                total_subjects_observed_in_window++
                subject_length_in_chars = length($0)
                if (subject_length_in_chars <= hard_target) {
                    bin_count_le_hard_target++
                } else if (subject_length_in_chars <= hard_cap) {
                    bin_count_51_to_hard_cap++
                } else if (subject_length_in_chars <= 100) {
                    bin_count_73_to_100++
                } else if (subject_length_in_chars <= 200) {
                    bin_count_101_to_200++
                } else if (subject_length_in_chars <= 500) {
                    bin_count_201_to_500++
                } else if (subject_length_in_chars <= 1000) {
                    bin_count_501_to_1000++
                } else {
                    bin_count_1000_plus++
                }
            }
            function iter152_render_one_histogram_bar_row(bin_label, bin_count, bin_total, bar_max_chars,    bar_filled_chars_width, bar_filled_chars_padding_width, bar_filled_chars_buffer, bar_padding_chars_buffer, build_iter_i, percent_share) {
                if (bin_total > 0) {
                    bar_filled_chars_width = int((bin_count / bin_total) * bar_max_chars + 0.5)
                    percent_share = (bin_count / bin_total) * 100
                } else {
                    bar_filled_chars_width = 0
                    percent_share = 0
                }
                bar_filled_chars_buffer = ""
                for (build_iter_i = 0; build_iter_i < bar_filled_chars_width; build_iter_i++) {
                    bar_filled_chars_buffer = bar_filled_chars_buffer "█"
                }
                bar_filled_chars_padding_width = bar_max_chars - bar_filled_chars_width
                bar_padding_chars_buffer = ""
                for (build_iter_i = 0; build_iter_i < bar_filled_chars_padding_width; build_iter_i++) {
                    bar_padding_chars_buffer = bar_padding_chars_buffer "░"
                }
                printf "  %-46s  %4d  %s%s  %5.1f%%\n", bin_label, bin_count, bar_filled_chars_buffer, bar_padding_chars_buffer, percent_share
            }
            END {
                if (total_subjects_observed_in_window == 0) {
                    print "  (no commits in window)"
                    exit
                }
                iter152_render_one_histogram_bar_row(sprintf("≤%d chars (industry hard target)", hard_target),           bin_count_le_hard_target + 0,    total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row(sprintf("%d-%d chars (industry hard cap)", hard_target + 1, hard_cap), bin_count_51_to_hard_cap + 0,    total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row(sprintf("%d-100 chars (mild over-cap)", hard_cap + 1),                bin_count_73_to_100 + 0,         total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row("101-200 chars (verbose-naming-era)",                                  bin_count_101_to_200 + 0,        total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row("201-500 chars (heavy verbose)",                                       bin_count_201_to_500 + 0,        total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row("501-1000 chars (extreme)",                                            bin_count_501_to_1000 + 0,       total_subjects_observed_in_window, bar_max_width)
                iter152_render_one_histogram_bar_row("1000+ chars (iter-144-149 outliers)",                                 bin_count_1000_plus + 0,         total_subjects_observed_in_window, bar_max_width)
            }
        '
}

iter152_render_panel_3_worst_offender_callouts_top_n_by_char_count_so_operators_can_target_attention() {
    echo ""
    echo "${ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS}─── Panel 3: Worst offenders (top ${ITER152_DEFAULT_NUMBER_OF_WORST_OFFENDERS_TO_CALL_OUT_IN_PANEL_3} by char count) ───${ITER152_ANSI_COLOR_RESET}"

    git log -"$ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW" --pretty=format:'%h|%s' 2>/dev/null \
        | awk -F'|' '{ subject_text = $0; sub(/^[^|]*\|/, "", subject_text); printf "%d|%s|%s\n", length(subject_text), $1, subject_text }' \
        | sort -rn \
        | head -"$ITER152_DEFAULT_NUMBER_OF_WORST_OFFENDERS_TO_CALL_OUT_IN_PANEL_3" \
        | awk -F'|' '{
            subject_text = $0
            sub(/^[^|]*\|[^|]*\|/, "", subject_text)
            truncated_for_display = (length(subject_text) > 70) ? substr(subject_text, 1, 70) "…" : subject_text
            printf "  - %s  (%d chars)  %s\n", $2, $1, truncated_for_display
        }'
}

iter152_render_panel_4_conventional_commits_type_distribution_across_canonical_eleven_types() {
    echo ""
    echo "${ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS}─── Panel 4: Conventional-commits type distribution ───${ITER152_ANSI_COLOR_RESET}"

    git log -"$ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW" --pretty=format:'%s' 2>/dev/null \
        | awk -v bar_max_width="$ITER152_DEFAULT_HISTOGRAM_BAR_MAX_WIDTH_IN_TERMINAL_COLUMNS" '
            {
                total++
                if (match($0, /^[a-zA-Z]+/)) {
                    extracted_type = tolower(substr($0, RSTART, RLENGTH))
                    type_count_by_name[extracted_type]++
                } else {
                    type_count_by_name["(no-type)"]++
                }
            }
            function iter152_render_one_type_bar_row(label_text, count_value, total_value, bar_max,    bar_w, pad_w, bar_buf, pad_buf, i, pct) {
                if (total_value > 0) {
                    bar_w = int((count_value / total_value) * bar_max + 0.5)
                    pct = (count_value / total_value) * 100
                } else {
                    bar_w = 0
                    pct = 0
                }
                bar_buf = ""
                for (i = 0; i < bar_w; i++) bar_buf = bar_buf "█"
                pad_w = bar_max - bar_w
                pad_buf = ""
                for (i = 0; i < pad_w; i++) pad_buf = pad_buf "░"
                printf "  %-12s  %4d  %s%s  %5.1f%%\n", label_text, count_value, bar_buf, pad_buf, pct
            }
            END {
                if (total == 0) { print "  (no commits in window)"; exit }
                # Render canonical conventional-commits types in sem-rel priority order.
                split("feat fix perf chore docs refactor test build ci style revert (no-type)", canonical_type_order_array, " ")
                for (i = 1; i <= 12; i++) {
                    type_label = canonical_type_order_array[i]
                    type_count_value = (type_label in type_count_by_name) ? type_count_by_name[type_label] : 0
                    if (type_count_value > 0) {
                        iter152_render_one_type_bar_row(type_label, type_count_value, total, bar_max_width)
                    }
                }
                # Any non-canonical types that snuck in:
                for (encountered_type in type_count_by_name) {
                    is_canonical = 0
                    for (i = 1; i <= 12; i++) {
                        if (encountered_type == canonical_type_order_array[i]) { is_canonical = 1; break }
                    }
                    if (!is_canonical) {
                        iter152_render_one_type_bar_row(encountered_type, type_count_by_name[encountered_type], total, bar_max_width)
                    }
                }
            }
        '
}

iter152_render_panel_5_recent_vs_previous_window_trend_signal_with_improving_or_regressing_verdict() {
    echo ""
    echo "${ITER152_ANSI_COLOR_CYAN_FOR_PANEL_HEADERS}─── Panel 5: Trend (current ${ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW} commits vs previous ${ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW}) ───${ITER152_ANSI_COLOR_RESET}"

    # Pull 2x window: first N is current, next N is previous.
    local total_window_size_doubled=$((ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW * 2))

    git log -"$total_window_size_doubled" --pretty=format:'%s' 2>/dev/null \
        | awk \
            -v window_size="$ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW" \
            -v hard_cap="$ITER152_DEFAULT_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE" \
            -v ansi_green="$ITER152_ANSI_COLOR_GREEN_FOR_IMPROVING_SIGNAL" \
            -v ansi_red="$ITER152_ANSI_COLOR_RED_FOR_REGRESSING_SIGNAL" \
            -v ansi_yellow="$ITER152_ANSI_COLOR_YELLOW_FOR_MIXED_SIGNAL" \
            -v ansi_reset="$ITER152_ANSI_COLOR_RESET" '
            {
                subject_length_chars = length($0)
                if (NR <= window_size) {
                    current_window_subject_lengths_array[NR] = subject_length_chars
                    current_window_subject_count++
                    if (subject_length_chars <= hard_cap) current_window_conformant_count++
                } else if (NR <= window_size * 2) {
                    previous_window_subject_lengths_array[NR - window_size] = subject_length_chars
                    previous_window_subject_count++
                    if (subject_length_chars <= hard_cap) previous_window_conformant_count++
                }
            }
            function iter152_compute_p50_median_of_array(arr, n,    sorted_arr, i, j, temp_swap_val) {
                # Copy and bubble-sort (n is always small ≤20 in practice).
                for (i = 1; i <= n; i++) sorted_arr[i] = arr[i]
                for (i = 1; i < n; i++) {
                    for (j = 1; j < n; j++) {
                        if (sorted_arr[j] > sorted_arr[j+1]) {
                            temp_swap_val = sorted_arr[j]
                            sorted_arr[j] = sorted_arr[j+1]
                            sorted_arr[j+1] = temp_swap_val
                        }
                    }
                }
                if (n % 2 == 1) return sorted_arr[int(n/2) + 1]
                else return (sorted_arr[n/2] + sorted_arr[n/2 + 1]) / 2
            }
            END {
                if (current_window_subject_count == 0 || previous_window_subject_count == 0) {
                    print "  (insufficient history for trend signal — need at least 2× window-size commits)"
                    exit
                }
                current_p50 = iter152_compute_p50_median_of_array(current_window_subject_lengths_array, current_window_subject_count)
                previous_p50 = iter152_compute_p50_median_of_array(previous_window_subject_lengths_array, previous_window_subject_count)
                delta_p50 = current_p50 - previous_p50
                pct_change_p50 = (previous_p50 > 0) ? (delta_p50 / previous_p50) * 100 : 0
                current_conformance_rate_pct = (current_window_conformant_count / current_window_subject_count) * 100
                previous_conformance_rate_pct = (previous_window_conformant_count / previous_window_subject_count) * 100
                delta_conformance_rate_pp = current_conformance_rate_pct - previous_conformance_rate_pct
                printf "  median subject length:  previous=%d  current=%d  Δ=%+d  (%+.1f%%)\n", previous_p50, current_p50, delta_p50, pct_change_p50
                printf "  ≤%d-cap conformance:    previous=%.0f%%  current=%.0f%%  Δ=%+.0fpp\n", hard_cap, previous_conformance_rate_pct, current_conformance_rate_pct, delta_conformance_rate_pp
                printf "  "
                if (delta_p50 < 0 && delta_conformance_rate_pp >= 0) {
                    printf "%sverdict: IMPROVING%s (shorter subjects, higher conformance)\n", ansi_green, ansi_reset
                } else if (delta_p50 > 0 && delta_conformance_rate_pp <= 0) {
                    printf "%sverdict: REGRESSING%s (longer subjects, lower conformance)\n", ansi_red, ansi_reset
                } else if (delta_p50 == 0 && delta_conformance_rate_pp == 0) {
                    printf "%sverdict: STABLE%s (no change between windows)\n", ansi_yellow, ansi_reset
                } else {
                    printf "%sverdict: MIXED%s (one metric improved, the other did not)\n", ansi_yellow, ansi_reset
                }
            }
        '
}

iter152_emit_dashboard_footer_with_operator_tunable_knob_hints_and_iter150_iter151_cross_references() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ⧗ tune via ITER152_COMMIT_COUNT_TO_ANALYZE=N (default ${ITER152_DEFAULT_COMMIT_COUNT_TO_ANALYZE_IN_CURRENT_WINDOW})"
    echo "  ⧗ tune via ITER152_SUBJECT_HARD_CAP_THRESHOLD_CHARS=N (default ${ITER152_DEFAULT_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE})"
    echo "  ⧗ tune via ITER152_SUBJECT_HARD_TARGET_THRESHOLD_CHARS=N (default ${ITER152_DEFAULT_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE})"
    echo "  ⧗ iter-150 readable view alone:           mise run release:history"
    echo "  ⧗ iter-151 preflight classification:      runs automatically at release:preflight Check 4l"
    echo "  ⧗ iter-150 convention (50/72 rule):       https://www.conventionalcommits.org/"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

iter152_main_entry_point_orchestrates_five_panel_dashboard_render() {
    iter152_emit_dashboard_header_banner_with_window_and_threshold_metadata
    iter152_render_panel_1_iter150_readable_view_by_delegating_to_iter150_renderer_for_consistency
    iter152_render_panel_2_subject_length_distribution_histogram_with_50_72_rule_anchored_bins
    iter152_render_panel_3_worst_offender_callouts_top_n_by_char_count_so_operators_can_target_attention
    iter152_render_panel_4_conventional_commits_type_distribution_across_canonical_eleven_types
    iter152_render_panel_5_recent_vs_previous_window_trend_signal_with_improving_or_regressing_verdict
    iter152_emit_dashboard_footer_with_operator_tunable_knob_hints_and_iter150_iter151_cross_references
}

iter152_main_entry_point_orchestrates_five_panel_dashboard_render
