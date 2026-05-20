#!/usr/bin/env awk -f
# skill-md-self-evolution-sandwich-single-pass-awk-scanner.awk
#
# Iter-74 single-pass cross-file scanner that replaces the iter-73-baseline
# 217-file × ~8-fork-exec-per-file storm in `.mise/tasks/release/preflight`
# Check 4b (self-evolution sandwich). Reads every SKILL.md from the argv,
# emits one TSV record per file with the audit facts needed by the
# downstream bash post-processor in preflight:
#
#   <filename>\t<has_self_evolving_marker_in_top25_body_lines:0|1>\t<last_post_execution_reflection_line_number:0=missing>\t<total_line_count_for_file>
#
# Audit semantics — preserved bit-for-bit from the iter-73 baseline:
#
#   1. TOP CHECK (Self-Evolving reminder presence):
#      Among the first 25 BODY lines (defined as lines after the second
#      "---" YAML frontmatter separator, skipping the separator lines
#      themselves), the case-insensitive substring "self-evolv" MUST appear
#      at least once. Result: has_self_evolving_marker_in_top25_body_lines.
#
#   2. BOTTOM CHECK (Post-Execution Reflection placement):
#      The substring "## Post-Execution Reflection" MUST appear at least
#      once anywhere in the file. The LAST occurrence's line number MUST
#      fall within the last 15 lines (total_line_count_for_file -
#      last_post_execution_reflection_line_number <= 15). Result:
#      last_post_execution_reflection_line_number (0 = missing).
#
#   3. TOTAL LINE COUNT: equivalent to `wc -l` (newline-terminated record
#      count). Used by the downstream bottom-check distance calculation.
#
# Portability: written in POSIX-portable awk syntax — no gawk-specific
# extensions (no ENDFILE, no asort, no length(array)). Verified against
# macOS BWK awk version 20200816 (/usr/bin/awk).
#
# Iter-74 perf-win rationale: replaces ~1736 forks (8/file × 217 files) with
# a single awk process invocation. Estimated preflight Check 4b drop from
# ~2032ms to ~500ms (~1.5s saved per preflight run). See
# docs/RELEASE.md "Opt-In Per-Phase Wall-Clock Timing Instrumentation
# (iter-73)" for the baseline measurement and iter-74+ candidate
# documentation.

# File-boundary detection: at the FIRST line of each new input file,
# flush results for the PREVIOUS file (if any) and reset per-file state.
# This pattern is the portable alternative to gawk's ENDFILE.
FNR == 1 {
    if (filename_of_previous_file_being_processed != "") {
        emit_tsv_audit_record_for_completed_file()
    }
    # Reset per-file accumulator state for the new file.
    filename_of_previous_file_being_processed = FILENAME
    has_self_evolving_marker_in_top25_body_lines = 0
    last_post_execution_reflection_line_number = 0
    total_line_count_for_file = 0
    yaml_frontmatter_separator_count_seen_so_far = 0
    is_inside_body_after_closing_frontmatter_separator = 0
    body_line_index_after_closing_frontmatter_separator = 0
}

# Total line count: tracks `wc -l` semantics. Updated for every line
# (including the YAML --- separators), since the downstream distance check
# uses absolute-file-position arithmetic, not body-relative.
{
    total_line_count_for_file = FNR
}

# YAML frontmatter separator detection. The SKILL.md convention places
# "---" at column 1 to delimit YAML. The FIRST "---" opens frontmatter;
# the SECOND closes it. After the second, body processing begins. The
# `next` directive prevents the separator line itself from being treated
# as a body line (preserving `awk '/^---$/{n++; next} n>=2'` semantics).
/^---$/ {
    yaml_frontmatter_separator_count_seen_so_far++
    if (yaml_frontmatter_separator_count_seen_so_far == 2) {
        is_inside_body_after_closing_frontmatter_separator = 1
    }
    next
}

# Body-only processing: fires ONLY for lines AFTER the second "---".
is_inside_body_after_closing_frontmatter_separator == 1 {
    body_line_index_after_closing_frontmatter_separator++

    # TOP CHECK: case-insensitive search for "self-evolv" within the
    # first 25 body lines. `tolower($0)` is the portable lowercase
    # transform; `index(haystack, needle) > 0` is the portable substring
    # search (returns 1-indexed position or 0).
    if (body_line_index_after_closing_frontmatter_separator <= 25) {
        lowercase_line_for_case_insensitive_substring_match = tolower($0)
        if (index(lowercase_line_for_case_insensitive_substring_match, "self-evolv") > 0) {
            has_self_evolving_marker_in_top25_body_lines = 1
        }
    }

    # BOTTOM CHECK: track the LINE NUMBER of the LAST occurrence of
    # "## Post-Execution Reflection". The original `grep -n ... | tail -1`
    # took the last match; we achieve the same by overwriting on every
    # match — at END the variable holds the final match's line number.
    if (index($0, "## Post-Execution Reflection") > 0) {
        last_post_execution_reflection_line_number = FNR
    }
}

# Flush the LAST file's results — END fires once after all input is
# consumed. Without this, the final file in argv would be silently
# omitted from the TSV output (FNR==1 only fires at the START of files).
END {
    if (filename_of_previous_file_being_processed != "") {
        emit_tsv_audit_record_for_completed_file()
    }
}

# TSV-emission helper. Tab-separated for safe parsing by the downstream
# bash `while IFS=$'\t' read` loop in preflight Check 4b. Filenames in
# the cc-skills marketplace are constrained to `plugins/<slug>/skills/<slug>/SKILL.md`
# with slug = [a-z0-9-]+ — no tabs, no newlines, no special chars in
# the filename column. The other three columns are integers.
function emit_tsv_audit_record_for_completed_file() {
    printf "%s\t%d\t%d\t%d\n", \
        filename_of_previous_file_being_processed, \
        has_self_evolving_marker_in_top25_body_lines, \
        last_post_execution_reflection_line_number, \
        total_line_count_for_file
}
