#!/usr/bin/env bash
# iter-150 readable git-log renderer for cc-skills release history.
#
# WHY THIS EXISTS:
#
#   The cc-skills release-iter cohort (iter-144 through iter-149) follows
#   the /loop user directive to "use verbose, specific, searchable file
#   names, function names, class names, variable names, constants, test
#   names, and benchmark names" — and that verbose-self-explanatory style
#   has been (mis)applied to git commit SUBJECTS too. Recent subject lengths:
#
#     iter-148: 754 chars
#     iter-149: 1078 chars
#
#   This violates the industry-standard conventional-commits 50/72 rule:
#     - subject ≤ 50 chars (hard cap), ≤ 72 chars (soft cap)
#     - body wrapped at 72 chars per line
#   See: https://www.conventionalcommits.org/en/v1.0.0/
#        https://cbea.ms/git-commit/
#
#   Consequence: `git log --oneline`, GitHub UI commit lists, code-review
#   tools, and bisect output all truncate or wrap unreadably. Operators
#   trying to scan release history see walls of text instead of a readable
#   timeline.
#
#   The /loop directive's verbose-naming rule explicitly enumerates
#   identifiers (file/function/class/var/constant/test/benchmark names) —
#   it does NOT mandate verbose git commit SUBJECTS. The going-forward
#   convention should be: short subject + verbose body. But for the
#   existing iter-144-through-iter-149 history, we don't rewrite commits.
#   Instead, this iter-150 wrapper provides a READABLE rendering at view
#   time.
#
# WHAT IT DOES:
#
#   Renders `git log` output where each commit is shown as:
#
#     <SHORT_SHA>  <YYYY-MM-DD HH:MM>  <REF_DECORATIONS>
#         <conventional-commit-type-prefix>: <description...
#         ...wrapped at terminal width on word boundaries
#         ...with hanging indent for visual continuation>
#         <blank line between commits for scanability>
#
#   The wrapping uses awk per the cc-skills root CLAUDE.md "Terminal text
#   unwrapping: awk only" principle — par/fmt/fold/pandoc/textwrap/pysbd
#   are documented to fail on this shape.
#
# USAGE:
#
#   # Default: last 10 commits, 80-column wrap width
#   scripts/iter150-readable-git-log-renderer-...sh
#
#   # Show last N commits
#   ITER150_COMMIT_COUNT_TO_DISPLAY=5 scripts/iter150-...sh
#
#   # Custom wrap width
#   ITER150_SOFT_WRAP_COLUMN_WIDTH=100 scripts/iter150-...sh
#
#   # Pass arbitrary git-log refs/options after `--`
#   scripts/iter150-...sh -- main~20..HEAD
#
# OPERATOR USE-CASE EXAMPLES:
#
#   # Quick scan of recent releases
#   mise run release:history
#
#   # Wider view for screens > 120 cols
#   ITER150_SOFT_WRAP_COLUMN_WIDTH=140 mise run release:history
#
#   # Investigate a specific commit's full subject
#   scripts/iter150-...sh -- -1 <sha>

set -euo pipefail

# ─── ITER-171 UTF-8 LOCALE INVARIANT GUARD FOR CHARACTER-COUNTING CORRECTNESS ─
# Empirically verified iter-171 audit probe finding: bash ${#var} returns
# CHARACTER count under UTF-8 locales (en_*.UTF-8, C.UTF-8) but BYTE count
# under C/POSIX locale. Without this guard, bash-level character counting
# would be locale-dependent and silently incorrect on CI runners with
# LC_ALL=C inherited from systemd defaults.
#
# Force UTF-8 locale at script entry. Override empty/unset/C/POSIX
# explicitly (Conventional Commits §5 specifies CHARACTER-counting
# semantics for subject length). Operator can opt INTO any other UTF-8
# locale (en_CA.UTF-8, C.UTF-8, zh_CN.UTF-8, etc.) which we respect verbatim.
case "${LC_ALL:-}" in
    ""|C|POSIX) export LC_ALL=en_US.UTF-8 ;;
esac
# ─── ITER-173 AWK SOFT-WRAP-BOUNDARY UTF-8 CORRECTNESS (iter-172 follow-up) ──
# iter-171's bash guard above does not fix awk length() byte-counting
# inside this renderer's soft-wrap-boundary detection. Without iter-173,
# a CJK commit subject like "feat: 修复编码问题XYZ" (15 visible characters,
# 27 UTF-8 bytes) would wrap aggressively at byte 80 ≈ character 30 for
# typical CJK density (3 bytes per char), much earlier than the operator
# expects under the 80-column terminal width contract.
#
# Iter-173 closes this gap by applying the iter-172 pattern (LC_ALL=C
# envelope on the awk invocation + inline RFC 3629 char-count function)
# to the 3 subject-text-related length() call sites inside the soft-wrap
# boundary algorithm. Result: soft-wrap boundary is now measured in
# VISIBLE CHARACTERS rather than bytes, matching operator intuition for
# CJK / emoji / Latin diaeresis subjects.
#
# After iter-173 the iter-150 → iter-152 → iter-153 conventional-commits
# operator toolkit is fully UTF-8-correct end-to-end.

ITER150_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER150_REPO_ROOT"

ITER150_DEFAULT_NUMBER_OF_RECENT_COMMITS_TO_DISPLAY_IN_HISTORY_VIEW="${ITER150_COMMIT_COUNT_TO_DISPLAY:-10}"
ITER150_DEFAULT_SOFT_WRAP_COLUMN_WIDTH_FOR_TERMINAL_READABILITY="${ITER150_SOFT_WRAP_COLUMN_WIDTH:-80}"
ITER150_DEFAULT_CONTINUATION_LINE_HANGING_INDENT_CHARACTERS_FOR_VISUAL_WRAP_AFFORDANCE="${ITER150_CONTINUATION_INDENT:-8}"

# ANSI color codes — gracefully degrade to plain text when stdout is not a TTY.
if [[ -t 1 ]]; then
    ITER150_ANSI_COLOR_YELLOW_FOR_SHORT_COMMIT_SHA_RENDERING="$(printf '\033[33m')"
    ITER150_ANSI_COLOR_GREEN_FOR_AUTHOR_DATE_RENDERING="$(printf '\033[32m')"
    ITER150_ANSI_COLOR_CYAN_FOR_REF_DECORATIONS_RENDERING="$(printf '\033[36m')"
    ITER150_ANSI_COLOR_BLUE_FOR_CONVENTIONAL_COMMIT_TYPE_PREFIX_RENDERING="$(printf '\033[1;34m')"
    ITER150_ANSI_COLOR_RESET="$(printf '\033[0m')"
else
    ITER150_ANSI_COLOR_YELLOW_FOR_SHORT_COMMIT_SHA_RENDERING=""
    ITER150_ANSI_COLOR_GREEN_FOR_AUTHOR_DATE_RENDERING=""
    ITER150_ANSI_COLOR_CYAN_FOR_REF_DECORATIONS_RENDERING=""
    ITER150_ANSI_COLOR_BLUE_FOR_CONVENTIONAL_COMMIT_TYPE_PREFIX_RENDERING=""
    ITER150_ANSI_COLOR_RESET=""
fi

# Parse args: anything before `--` is reserved for future flag use; anything
# after `--` is passed verbatim to `git log` as extra args (e.g., refs).
# Currently no flags pre-`--` are defined — extending pattern remains open
# for iter-151+ if needed.
declare -a iter150_extra_git_log_args_passed_through_verbatim_to_git=()
iter150_in_passthrough_mode=0
for iter150_arg_for_dispatch_parsing in "$@"; do
    if [[ "$iter150_in_passthrough_mode" == "1" ]]; then
        iter150_extra_git_log_args_passed_through_verbatim_to_git+=("$iter150_arg_for_dispatch_parsing")
    elif [[ "$iter150_arg_for_dispatch_parsing" == "--" ]]; then
        iter150_in_passthrough_mode=1
    fi
done

# If no extra args passed, default to "-N commits from HEAD".
if [[ "${#iter150_extra_git_log_args_passed_through_verbatim_to_git[@]}" -eq 0 ]]; then
    iter150_extra_git_log_args_passed_through_verbatim_to_git=(
        "-${ITER150_DEFAULT_NUMBER_OF_RECENT_COMMITS_TO_DISPLAY_IN_HISTORY_VIEW}"
    )
fi

iter150_emit_render_header_banner_with_wrap_width_and_commit_count_metadata() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-150 READABLE GIT LOG (cc-skills release history)"
    echo "  wrap=${ITER150_DEFAULT_SOFT_WRAP_COLUMN_WIDTH_FOR_TERMINAL_READABILITY}cols  indent=${ITER150_DEFAULT_CONTINUATION_LINE_HANGING_INDENT_CHARACTERS_FOR_VISUAL_WRAP_AFFORDANCE}sp  default-count=${ITER150_DEFAULT_NUMBER_OF_RECENT_COMMITS_TO_DISPLAY_IN_HISTORY_VIEW}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

iter150_emit_render_footer_with_operator_tunable_knob_hints() {
    echo ""
    echo "  ⧗ tune via ITER150_COMMIT_COUNT_TO_DISPLAY=N (default ${ITER150_DEFAULT_NUMBER_OF_RECENT_COMMITS_TO_DISPLAY_IN_HISTORY_VIEW})"
    echo "  ⧗ tune via ITER150_SOFT_WRAP_COLUMN_WIDTH=N (default ${ITER150_DEFAULT_SOFT_WRAP_COLUMN_WIDTH_FOR_TERMINAL_READABILITY})"
    echo "  ⧗ tune via ITER150_CONTINUATION_INDENT=N (default ${ITER150_DEFAULT_CONTINUATION_LINE_HANGING_INDENT_CHARACTERS_FOR_VISUAL_WRAP_AFFORDANCE})"
    echo "  ⧗ pass extra git-log args after '--', e.g.: $0 -- main~20..HEAD"
    echo ""
}

iter150_render_git_log_with_awk_based_soft_wrap_of_long_conventional_commit_subjects_for_terminal_readability() {
    # Emit raw git log with a known field separator that's extremely unlikely
    # to appear in any commit subject/decoration. U+241F INFORMATION SEPARATOR
    # ONE is a control character intentionally reserved for in-band field
    # delimiting and never appears in human-authored text.
    local iter150_inband_field_separator_unicode_information_separator_one=$'\x1f'

    # iter-173 LC_ALL=C envelope: scopes awk back to byte-level locale so
    # the inline iter172 RFC 3629 char-count function's [\200-\277] byte
    # range regex matches UTF-8 continuation bytes by byte value.
    git log \
        --pretty=format:"%h${iter150_inband_field_separator_unicode_information_separator_one}%ai${iter150_inband_field_separator_unicode_information_separator_one}%D${iter150_inband_field_separator_unicode_information_separator_one}%s" \
        "${iter150_extra_git_log_args_passed_through_verbatim_to_git[@]}" \
        | LC_ALL=C awk \
            -F"$iter150_inband_field_separator_unicode_information_separator_one" \
            -v soft_wrap_column_width="$ITER150_DEFAULT_SOFT_WRAP_COLUMN_WIDTH_FOR_TERMINAL_READABILITY" \
            -v continuation_indent_chars="$ITER150_DEFAULT_CONTINUATION_LINE_HANGING_INDENT_CHARACTERS_FOR_VISUAL_WRAP_AFFORDANCE" \
            -v ansi_yellow="$ITER150_ANSI_COLOR_YELLOW_FOR_SHORT_COMMIT_SHA_RENDERING" \
            -v ansi_green="$ITER150_ANSI_COLOR_GREEN_FOR_AUTHOR_DATE_RENDERING" \
            -v ansi_cyan="$ITER150_ANSI_COLOR_CYAN_FOR_REF_DECORATIONS_RENDERING" \
            -v ansi_blue="$ITER150_ANSI_COLOR_BLUE_FOR_CONVENTIONAL_COMMIT_TYPE_PREFIX_RENDERING" \
            -v ansi_reset="$ITER150_ANSI_COLOR_RESET" '
            BEGIN {
                # The continuation indent is a string of `continuation_indent_chars` spaces.
                continuation_indent_string = ""
                for (build_indent_string_iter_i = 0; build_indent_string_iter_i < continuation_indent_chars; build_indent_string_iter_i++) {
                    continuation_indent_string = continuation_indent_string " "
                }
                # The available width for subject text on continuation lines is
                # the terminal width minus the indent.
                continuation_line_text_width = soft_wrap_column_width - continuation_indent_chars
                if (continuation_line_text_width < 20) {
                    continuation_line_text_width = 20
                }
            }
            function iter150_split_subject_into_conventional_commit_type_prefix_and_remaining_description(subject, parts_arr) {
                # Conventional-commit grammar: <type>(<scope>)?(!)?:<space><description>
                # Match the type-scope-colon-space prefix and isolate the
                # remaining description for wrapping. RLENGTH includes both
                # the trailing colon and space, so subtract 2 to keep only
                # `<type>(<scope>)?(!)?` in the prefix slot.
                if (match(subject, /^[a-zA-Z]+(\([^)]+\))?!?:[[:space:]]/)) {
                    parts_arr["type_prefix"] = substr(subject, 1, RLENGTH - 2)
                    parts_arr["description"] = substr(subject, RLENGTH + 1)
                } else {
                    # Non-conventional commit — emit the whole thing as description.
                    parts_arr["type_prefix"] = ""
                    parts_arr["description"] = subject
                }
            }
            function iter150_replace_hyphens_with_spaces_so_verbose_kebab_case_descriptions_can_soft_wrap_on_word_boundaries(input_string) {
                # Verbose conventional commit subjects use hyphens as word
                # separators (example: pre-warm-the-openssh-controlmaster-session).
                # Without this transform, awk treats the entire kebab-cased blob
                # as ONE WORD with no break-points and emits a single unbroken
                # 1000+ char line. Replacing hyphens with spaces gives the
                # word-boundary wrapper the break-points it needs. Transform is
                # non-destructive: this view does not modify the underlying
                # commit, and readability gain dramatically outweighs the
                # lost-hyphen cosmetic.
                gsub(/-/, " ", input_string)
                return input_string
            }
            function iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(text,    byte_length_of_text_in_locale_native_units, copy_of_text_for_gsub_mutation, count_of_utf8_continuation_bytes_found) {
                # iter-173 reuse of the iter-172 RFC 3629 byte-pattern char-count
                # function: returns byte_length(text) minus count of UTF-8
                # continuation bytes (regex [\200-\277] matches byte range
                # 0x80-0xBF under LC_ALL=C). Per RFC 3629, only continuation
                # bytes (10xxxxxx pattern) cannot start a Unicode character;
                # subtracting their count yields visible character count for
                # any valid UTF-8 input (CJK 3-byte, emoji 4-byte, etc).
                byte_length_of_text_in_locale_native_units = length(text)
                copy_of_text_for_gsub_mutation = text
                count_of_utf8_continuation_bytes_found = gsub(/[\200-\277]/, "", copy_of_text_for_gsub_mutation)
                return byte_length_of_text_in_locale_native_units - count_of_utf8_continuation_bytes_found
            }
            function iter150_soft_wrap_long_string_on_word_boundaries_to_target_width(input_string, target_wrap_width, emit_continuation_indent_flag,    word_array, word_count_in_array, accumulated_line_being_built_buffer, word_position_in_array_walker, candidate_next_word_to_append, accumulated_plus_next_word_string) {
                word_count_in_array = split(input_string, word_array, " ")
                accumulated_line_being_built_buffer = ""
                for (word_position_in_array_walker = 1; word_position_in_array_walker <= word_count_in_array; word_position_in_array_walker++) {
                    candidate_next_word_to_append = word_array[word_position_in_array_walker]
                    if (iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(accumulated_line_being_built_buffer) == 0) {
                        accumulated_plus_next_word_string = candidate_next_word_to_append
                    } else {
                        accumulated_plus_next_word_string = accumulated_line_being_built_buffer " " candidate_next_word_to_append
                    }
                    if (iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(accumulated_plus_next_word_string) <= target_wrap_width) {
                        accumulated_line_being_built_buffer = accumulated_plus_next_word_string
                    } else {
                        # Flush the current accumulated line and start a new one
                        # with the candidate word.
                        if (emit_continuation_indent_flag && NR_continuation_line_already_emitted_for_this_commit) {
                            printf "%s%s\n", continuation_indent_string, accumulated_line_being_built_buffer
                        } else if (emit_continuation_indent_flag) {
                            printf "%s%s\n", continuation_indent_string, accumulated_line_being_built_buffer
                            NR_continuation_line_already_emitted_for_this_commit = 1
                        } else {
                            print accumulated_line_being_built_buffer
                        }
                        accumulated_line_being_built_buffer = candidate_next_word_to_append
                    }
                }
                # Final line.
                if (iter172_count_visible_chars_by_subtracting_rfc3629_continuation_bytes(accumulated_line_being_built_buffer) > 0) {
                    if (emit_continuation_indent_flag) {
                        printf "%s%s\n", continuation_indent_string, accumulated_line_being_built_buffer
                    } else {
                        print accumulated_line_being_built_buffer
                    }
                }
            }
            {
                short_sha = $1
                author_iso8601_date = $2
                ref_decorations = $3
                full_subject = $4

                # Compact the timestamp: keep YYYY-MM-DD HH:MM, drop seconds + tz.
                if (length(author_iso8601_date) >= 16) {
                    author_date_compact_for_display = substr(author_iso8601_date, 1, 16)
                } else {
                    author_date_compact_for_display = author_iso8601_date
                }

                # Render header line: SHA, date, decorations.
                if (length(ref_decorations) > 0) {
                    printf "%s%s%s  %s%s%s  %s%s%s\n",
                        ansi_yellow, short_sha, ansi_reset,
                        ansi_green, author_date_compact_for_display, ansi_reset,
                        ansi_cyan, ref_decorations, ansi_reset
                } else {
                    printf "%s%s%s  %s%s%s\n",
                        ansi_yellow, short_sha, ansi_reset,
                        ansi_green, author_date_compact_for_display, ansi_reset
                }

                # Split subject into conventional-commit type prefix + description.
                iter150_split_subject_into_conventional_commit_type_prefix_and_remaining_description(full_subject, conventional_commit_parts)

                # Render type prefix on its own line if present, then wrap description.
                if (length(conventional_commit_parts["type_prefix"]) > 0) {
                    printf "%s%s%s:\n", ansi_blue, conventional_commit_parts["type_prefix"], ansi_reset
                }

                # Replace hyphens with spaces in the description so the
                # word-boundary wrapper can find break-points in kebab-cased
                # verbose subjects (the iter-144-through-iter-149 cohort).
                hyphen_replaced_description_for_wrap = iter150_replace_hyphens_with_spaces_so_verbose_kebab_case_descriptions_can_soft_wrap_on_word_boundaries(conventional_commit_parts["description"])
                # Wrap the description body with continuation indent.
                NR_continuation_line_already_emitted_for_this_commit = 0
                iter150_soft_wrap_long_string_on_word_boundaries_to_target_width(hyphen_replaced_description_for_wrap, continuation_line_text_width, 1)

                # Blank line between commits for visual scanning.
                print ""
            }
        '
}

iter150_main_entry_point_orchestrates_header_then_render_then_footer_for_operator_readable_history_view() {
    iter150_emit_render_header_banner_with_wrap_width_and_commit_count_metadata
    iter150_render_git_log_with_awk_based_soft_wrap_of_long_conventional_commit_subjects_for_terminal_readability
    iter150_emit_render_footer_with_operator_tunable_knob_hints
}

iter150_main_entry_point_orchestrates_header_then_render_then_footer_for_operator_readable_history_view
