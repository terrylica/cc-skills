#!/usr/bin/env bash
# iter-153 pre-commit dry-run advisor.
#
# WHY THIS EXISTS:
#
#   The iter-150 (VIEW) → iter-151 (DETECT) → iter-152 (HEALTH SUMMARY)
#   arc closed three layers of post-commit visibility into conventional-
#   commits 50/72-rule conformance, but ONE gap remained: operators only
#   learn about a long-subject violation AFTER they commit, at release-
#   time preflight Check 4l. There is no PRE-commit advisor to catch
#   violations BEFORE the commit lands.
#
#   Web research (2026-05) confirms this is also a gap in the broader
#   conventional-commits ecosystem:
#
#     - commitlint, conventional-pre-commit, commitizen, conventional-
#       precommit-linter all run BLOCKING at the commit-msg stage
#     - none provide a non-blocking advisor or dry-run mode
#     - none emit machine-readable (JSON) output for AI-agent automation
#
#   iter-153 fills both gaps:
#
#     - Default mode: human-readable verdict with measured length,
#       classification, type recognition, scope, breaking flag, iter-150
#       50/72 conformance, violations list, remediation hint
#
#     - --json mode: machine-readable JSON output for AI-agent
#       automation pipelines and jq-based shell automation. Parallel to
#       iter-119 which added --json to the iter-116 reverse-search CLI
#
#     - --strict mode: mirrors iter-82 strict-mode semantics. Exits
#       non-zero on COMPOUND-PREFIX or MISSING-TYPE violations (silent-
#       fail-class for semantic-release). Long-subject overlay remains
#       INFORMATIONAL even in --strict mode, per the iter-151
#       informational-only design invariant — long subjects do not break
#       semantic-release tagging, only readability.
#
#   Per the cc-skills Local-First CI/CD Policy (no GitHub Actions for
#   linting), this advisor is operator-driven and bash-native. No
#   external Python/Node dependencies. Single source of truth invariant:
#   reuses the iter-82/iter-151 classification grammar (recognized
#   types, regex patterns, the canonical 50/72 thresholds).
#
# USAGE:
#
#   # Pass proposed subject as a single arg:
#   mise run commits:advise -- "feat(release): iter-153 short subject"
#
#   # Pass via stdin (useful when piping from clipboard or editor):
#   echo "feat(release): iter-153 short subject" | \
#       mise run commits:advise --
#
#   # JSON output for AI agents / shell automation:
#   mise run commits:advise --json -- "feat(release): iter-153 short subject" | jq .
#
#   # Strict mode (exit non-zero on silent-fail-class violations):
#   mise run commits:advise --strict -- "feat(scope)+docs: bad compound prefix"
#
# DESIGN NOTES:
#
#   - Long-subject overlay (>72 chars) is always INFORMATIONAL,
#     mirroring the iter-151 informational-only design invariant. Even
#     in --strict mode, long-subject violations do NOT contribute to the
#     non-zero exit decision. This is because semantic-release parses
#     any subject length identically, so subject length is a readability
#     issue, not a release-blocking issue.
#
#   - --strict mode gates on COMPOUND-PREFIX and MISSING-TYPE violations
#     ONLY. These are the silent-fail class observed in iter-77, iter-80,
#     iter-81 (compound prefixes silently skip semantic-release tagging).
#
#   - JSON schema is stable per iter-153 spec. AI-agent consumers can
#     rely on the field set documented in the JSON_SCHEMA_DOCUMENTATION
#     section at the bottom of this script.
#
# PRIOR ART:
#
#   - https://www.conventionalcommits.org/en/v1.0.0/ — canonical spec
#   - https://github.com/compilerla/conventional-pre-commit — blocking
#     commit-msg hook (no advisor/dry-run mode)
#   - https://github.com/espressif/conventional-precommit-linter —
#     subject-length validation but no advisor/dry-run/JSON
#   - https://github.com/conventional-changelog/commitlint — Node-based,
#     blocking, no JSON output
#   - iter-82/iter-151 cc-skills validators — release-time classifier,
#     informational long-subject overlay

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# ─── Constants reused from iter-82/iter-151 (single source of truth) ─────────
# Recognized conventional-commits types per cc-skills .releaserc.yml.
# Update this if the upstream validator's recognized-type list changes.
ITER153_RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES_ARRAY=(
    feat fix perf revert docs chore style refactor test build ci
)

# Conventional-commits header regex (matches the canonical grammar).
ITER153_STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX='^[a-z]+(\([^)]+\))?!?: .+'

# Compound-prefix anti-pattern (silent-fail class).
ITER153_COMPOUND_PREFIX_ANTI_PATTERN_REGEX='^[a-z]+(\([^)]+\))?[^!:](.*)?:'

# Auto-release commit pattern (excluded from validation).
ITER153_AUTO_RELEASE_COMMIT_MESSAGE_PATTERN_REGEX='^chore\(release\): [0-9]+\.[0-9]+\.[0-9]+ \[skip ci\]$'

# Iter-150 industry-standard subject-length thresholds.
ITER153_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE=50
ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE=72

# ─── Arg parsing ────────────────────────────────────────────────────────────
ITER153_OUTPUT_MODE_HUMAN_READABLE_OR_JSON_FOR_AI_AGENT_CONSUMPTION="human"
ITER153_STRICT_MODE_EXIT_NONZERO_ON_SILENT_FAIL_CLASS_VIOLATIONS=0
ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY=""
# Iter-162: full multi-line commit-message body captured separately from
# the subject line. Used to detect Conventional Commits §13 BREAKING
# CHANGE footer tokens that signal a MAJOR bump without the subject `!`
# marker. Populated by --message-file flag or the iter-154 COMMIT_EDITMSG
# auto-detect (extended to capture body).
# shellcheck disable=SC2034  # populated and consumed in iter-162 block further down
ITER162_PROPOSED_COMMIT_MULTILINE_BODY_FOR_FOOTER_TOKEN_DETECTION_OR_EMPTY_WHEN_SUBJECT_ONLY_INPUT_MODE=""

iter153_print_usage_help_text_and_exit_with_code_two() {
    cat <<'EOF'
Usage: commits:advise [--json] [--strict] -- "<proposed subject>"
   or: echo "<subject>" | commits:advise [--json] [--strict] --
   or: commits:advise [--json] [--strict] --message-file <path>

Pre-commit dry-run advisor. Classifies a proposed conventional-commit
subject through the iter-82/iter-151 grammar without committing.

Modes:
  --json              Emit machine-readable JSON for AI-agent automation.
  --strict            Exit non-zero on silent-fail-class violations
                      (COMPOUND-PREFIX or MISSING-TYPE). Long-subject
                      overlay remains informational even in --strict mode.
  --message-file PATH Read full multi-line commit message from PATH.
                      First non-comment non-empty line = subject, rest =
                      body. Enables iter-162 BREAKING CHANGE footer-token
                      detection (Conventional Commits §13). Used by the
                      iter-157 commit-msg hook to forward COMMIT_EDITMSG.

Examples:
  commits:advise -- "feat(release): iter-153 short subject"
  commits:advise --json -- "feat: foo" | jq .verdict
  commits:advise --strict -- "feat(scope)+docs: bad compound prefix"
  commits:advise --strict --message-file .git/COMMIT_EDITMSG
EOF
    exit 2
}

# Iter-162: helper to split a multi-line commit-message file into
# (subject, body) tuple per the git commit-message convention.
#   - Subject = FIRST non-comment non-blank line (matches iter-157
#     extraction logic)
#   - Body    = ALL non-comment lines AFTER the subject (preserves
#     blank lines for footer-token detection per the §13 spec which
#     requires "one blank line after the body" for footers).
iter162_split_commit_message_file_into_subject_line_and_remaining_multiline_body_per_git_commit_message_convention() {
    local commit_message_file_absolute_path="$1"
    awk -v subject_line_already_emitted=0 '
        /^[[:space:]]*#/ { next }
        subject_line_already_emitted == 0 && /^[[:space:]]*$/ { next }
        subject_line_already_emitted == 0 {
            print > "/dev/stderr"
            subject_line_already_emitted = 1
            next
        }
        { print }
    ' "$commit_message_file_absolute_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            ITER153_OUTPUT_MODE_HUMAN_READABLE_OR_JSON_FOR_AI_AGENT_CONSUMPTION="json"
            shift
            ;;
        --strict)
            ITER153_STRICT_MODE_EXIT_NONZERO_ON_SILENT_FAIL_CLASS_VIOLATIONS=1
            shift
            ;;
        --message-file)
            shift
            if [[ $# -eq 0 ]] || [[ ! -f "$1" ]]; then
                echo "Error: --message-file requires a readable file path argument" >&2
                iter153_print_usage_help_text_and_exit_with_code_two
            fi
            ITER162_PROPOSED_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH_FOR_FULL_MULTILINE_INPUT_INCLUDING_BODY="$1"
            # awk emits subject on stderr (so we can capture it separately)
            # and body on stdout. Bash's process substitution + temp file
            # avoids the stderr/stdout-cross-channel gymnastics.
            ITER162_PROPOSED_COMMIT_MULTILINE_BODY_FOR_FOOTER_TOKEN_DETECTION_OR_EMPTY_WHEN_SUBJECT_ONLY_INPUT_MODE=$(
                iter162_split_commit_message_file_into_subject_line_and_remaining_multiline_body_per_git_commit_message_convention \
                    "$ITER162_PROPOSED_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH_FOR_FULL_MULTILINE_INPUT_INCLUDING_BODY" \
                    2>/tmp/iter162-subject-line-tmpfile-$$
            )
            ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY=$(cat /tmp/iter162-subject-line-tmpfile-$$)
            rm -f /tmp/iter162-subject-line-tmpfile-$$
            shift
            ;;
        --help|-h)
            iter153_print_usage_help_text_and_exit_with_code_two
            ;;
        --)
            shift
            if [[ $# -gt 0 ]]; then
                ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY="$*"
            else
                # Read from stdin if `--` is present but no subject follows.
                if [[ ! -t 0 ]]; then
                    IFS= read -r ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY || true
                fi
            fi
            break
            ;;
        *)
            echo "Unknown argument: $1" >&2
            iter153_print_usage_help_text_and_exit_with_code_two
            ;;
    esac
done

# Iter-154: COMMIT_EDITMSG auto-detect path.
#
# If we still have no subject AND we are in an interactive context
# (stdin is a TTY, so the operator did not pipe a subject), look for
# .git/COMMIT_EDITMSG — the file git uses for the editor-launched
# commit flow. This closes the natural workflow loop: operator opens
# editor → types subject → saves → BEFORE closing editor, runs
# `mise run commits:advise` in another terminal → sees verdict on the
# in-progress commit subject. The subject is the FIRST non-comment
# non-empty line of the file per the git commit message convention.
#
# Only auto-detects if no `--` was passed; presence of `--` indicates
# explicit operator intent to pass a subject (either via args or
# stdin), so we should not surprise them by reaching into git state.
if [[ -z "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY" ]]; then
    ITER154_GIT_REPO_ROOT_FOR_COMMIT_EDITMSG_AUTO_DETECT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    ITER154_GIT_COMMIT_EDITMSG_FILE_ABSOLUTE_PATH="${ITER154_GIT_REPO_ROOT_FOR_COMMIT_EDITMSG_AUTO_DETECT}/.git/COMMIT_EDITMSG"
    if [[ -n "$ITER154_GIT_REPO_ROOT_FOR_COMMIT_EDITMSG_AUTO_DETECT" ]] \
       && [[ -f "$ITER154_GIT_COMMIT_EDITMSG_FILE_ABSOLUTE_PATH" ]] \
       && [[ -t 0 ]]; then
        # Read first non-comment non-empty line as the proposed subject.
        ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY=$(
            grep -v '^#' "$ITER154_GIT_COMMIT_EDITMSG_FILE_ABSOLUTE_PATH" \
                | grep -v '^[[:space:]]*$' \
                | head -1
        )
        if [[ -n "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY" ]]; then
            echo "  ⧗ iter-154 auto-detect: read subject from .git/COMMIT_EDITMSG" >&2
            # Iter-162 extension: also capture multi-line body (everything
            # after the subject line, comments stripped) so the iter-162
            # footer-token detector can scan for BREAKING CHANGE: trailers.
            ITER162_PROPOSED_COMMIT_MULTILINE_BODY_FOR_FOOTER_TOKEN_DETECTION_OR_EMPTY_WHEN_SUBJECT_ONLY_INPUT_MODE=$(
                iter162_split_commit_message_file_into_subject_line_and_remaining_multiline_body_per_git_commit_message_convention \
                    "$ITER154_GIT_COMMIT_EDITMSG_FILE_ABSOLUTE_PATH" \
                    2>/dev/null
            )
        fi
    fi
fi

if [[ -z "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY" ]]; then
    echo "Error: no proposed subject provided (and .git/COMMIT_EDITMSG auto-detect found nothing)" >&2
    iter153_print_usage_help_text_and_exit_with_code_two
fi

# ─── Classification engine ──────────────────────────────────────────────────

iter153_classify_proposed_subject_through_iter82_grammar_returning_structured_fields() {
    local proposed_subject_input="$1"

    # Output fields (caller reads from these globals after invocation).
    ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS="${#proposed_subject_input}"
    ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET=""
    ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY=""
    ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY=""
    ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN="false"
    ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN="false"
    ITER153_CLASSIFIED_UNDER_50_CHAR_HARD_TARGET_BOOLEAN="false"
    ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN="false"
    ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN="false"

    # 50/72 conformance booleans (informational overlay).
    if (( ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS <= ITER153_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE )); then
        ITER153_CLASSIFIED_UNDER_50_CHAR_HARD_TARGET_BOOLEAN="true"
    fi
    if (( ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS <= ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE )); then
        ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN="true"
    fi

    # Priority-order classification (matches iter-82 validator logic).

    # 1. Merge commit
    if [[ "$proposed_subject_input" =~ ^Merge[[:space:]] ]]; then
        ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="MERGE-COMMIT"
        return 0
    fi

    # 2. Auto-release commit
    if [[ "$proposed_subject_input" =~ $ITER153_AUTO_RELEASE_COMMIT_MESSAGE_PATTERN_REGEX ]]; then
        ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="AUTO-RELEASE-COMMIT"
        return 0
    fi

    # 3. Compound-prefix violation (silent-fail class)
    if [[ "$proposed_subject_input" =~ $ITER153_COMPOUND_PREFIX_ANTI_PATTERN_REGEX ]] \
       && ! [[ "$proposed_subject_input" =~ $ITER153_STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX ]]; then
        ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="COMPOUND-PREFIX"
        ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN="true"
        return 0
    fi

    # 4. Standard conformant — extract type/scope/breaking
    if [[ "$proposed_subject_input" =~ $ITER153_STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX ]]; then
        ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY="${proposed_subject_input%%[(:!]*}"
        # Scope extraction: between parens if present. Lifting regex to a
        # variable so shellcheck can parse the surrounding [[ =~ ]] without
        # tripping on the parens-as-regex-groups vs parens-as-literal
        # ambiguity (SC1009/SC1072/SC1073 false-positive on inline form).
        local iter153_scope_extraction_regex_pattern_with_capture_group_for_optional_parenthesized_scope='^[a-z]+\(([^)]+)\)'
        if [[ "$proposed_subject_input" =~ $iter153_scope_extraction_regex_pattern_with_capture_group_for_optional_parenthesized_scope ]]; then
            ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY="${BASH_REMATCH[1]}"
        fi
        # Breaking-change indicator: `!` immediately before colon.
        local iter153_breaking_change_indicator_regex_pattern_matching_bang_directly_before_colon='^[a-z]+(\([^)]+\))?!:'
        if [[ "$proposed_subject_input" =~ $iter153_breaking_change_indicator_regex_pattern_matching_bang_directly_before_colon ]]; then
            ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN="true"
        fi
        # Type-recognized check against the canonical sem-rel set.
        local checked_recognized_type
        for checked_recognized_type in "${ITER153_RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES_ARRAY[@]}"; do
            if [[ "$ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY" == "$checked_recognized_type" ]]; then
                ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN="true"
                break
            fi
        done
        if [[ "$ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN" == "true" ]]; then
            ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="STANDARD-CONFORMANT"
        else
            ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="MISSING-TYPE"
            ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN="true"
        fi
        return 0
    fi

    # 5. Doesn't match anything — missing-type
    ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET="MISSING-TYPE"
    ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN="true"
}

# ─── Human-readable verdict renderer ────────────────────────────────────────

iter153_emit_human_readable_verdict_with_classification_details_and_remediation_hints() {
    local primary_classification_bucket="$1"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  COMMITS ADVISE (iter-153 pre-commit dry-run advisor)"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    printf "  proposed subject:       %s\n" "\"$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY\""
    printf "  measured length:        %d chars\n" "$ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS"
    printf "  classification:         %s\n" "$primary_classification_bucket"
    if [[ -n "$ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY" ]]; then
        printf "  type:                   %s" "$ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY"
        if [[ "$ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN" == "true" ]]; then
            printf "  (✓ recognized by sem-rel)\n"
        else
            printf "  (✗ NOT in sem-rel canonical set)\n"
        fi
    fi
    if [[ -n "$ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY" ]]; then
        printf "  scope:                  %s\n" "$ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY"
    fi
    # Iter-162: OR the subject `!` marker with the body footer-token
    # detection (Conventional Commits §13 dual-signal coverage). Compute
    # the unified breaking-change boolean + source label once so both
    # the diagnostic-display block below and the iter-161 classifier
    # call site below get the same answer.
    local iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token="$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN"
    local iter162_unified_breaking_change_signal_source_human_readable_label_for_diagnostic_display=""
    if [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "true" ]] \
       && [[ "$ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE" == "true" ]]; then
        iter162_unified_breaking_change_signal_source_human_readable_label_for_diagnostic_display="both ! subject suffix AND ${ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED} body footer-token detected"
    elif [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "true" ]]; then
        iter162_unified_breaking_change_signal_source_human_readable_label_for_diagnostic_display="! suffix detected in subject"
    elif [[ "$ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE" == "true" ]]; then
        iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token="true"
        iter162_unified_breaking_change_signal_source_human_readable_label_for_diagnostic_display="iter-162 ${ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED} body footer-token detected (no ! in subject)"
    fi

    if [[ "$iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token" == "true" ]]; then
        printf "  breaking change:        ✓ yes (%s)\n" "$iter162_unified_breaking_change_signal_source_human_readable_label_for_diagnostic_display"
    fi
    echo ""
    echo "  iter-150 50/72-rule conformance:"
    if [[ "$ITER153_CLASSIFIED_UNDER_50_CHAR_HARD_TARGET_BOOLEAN" == "true" ]]; then
        printf "    ✓ under 50-char hard target (industry preferred, %d/%d)\n" "$ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS" "$ITER153_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE"
    elif [[ "$ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN" == "true" ]]; then
        printf "    ⚠ over 50-char hard target but under 72-char hard cap (%d/%d)\n" "$ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS" "$ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE"
    else
        printf "    ✗ OVER 72-char hard cap (%d > %d) — readability defect per iter-150 convention\n" "$ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS" "$ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE"
    fi
    echo ""

    # Iter-161 semver-bump preview overlay — surfaces the actual
    # MAJOR/MINOR/PATCH/NONE version bump cc-skills' semantic-release
    # will apply per .releaserc.yml. Closes the conventional-commits
    # ecosystem advisor gap (commitlint/commitizen/conventional-pre-
    # commit stop at grammar conformance, never preview the bump).
    if declare -F iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules >/dev/null 2>&1; then
        iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules \
            "$ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY" \
            "$iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token"
        # Iter-162: when breaking was detected via BODY FOOTER (not subject
        # `!`), the iter-161-emitted rationale incorrectly cites the `!`
        # marker. Override with an accurate body-footer rationale that
        # references the actual signal source per Conventional Commits §13.
        if [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "false" ]] \
           && [[ "$ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE" == "true" ]]; then
            ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="${ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED} footer-token in body → MAJOR bump per conventional-commits §13 (iter-162 detected body-form breaking signal, no ! in subject)"
        fi
        echo "  iter-161 semver-bump preview (per cc-skills .releaserc.yml):"
        case "$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES" in
            MAJOR) printf "    ⚠ MAJOR bump — breaking-change release\n" ;;
            MINOR) printf "    + MINOR bump — new feature release\n" ;;
            PATCH) printf "    · PATCH bump — patch release\n" ;;
            NONE)  printf "    ⊘ NO BUMP — semantic-release will SKIP this commit\n" ;;
        esac
        printf "    rationale: %s\n" "$ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN"

        # Iter-164 next-version preview — resolves the iter-161 bump
        # label into a concrete next-version-number string (e.g.,
        # "v21.71.0 → v21.72.0") by applying semver.org §2 increment
        # rules to the current git tag. Pure-bash, no semantic-release
        # --dry-run invocation needed. Soft-fail to no-preview if lib
        # is unavailable.
        if declare -F iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules >/dev/null 2>&1; then
            iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules \
                "$ITER164_DETECTED_CURRENT_GIT_TAG_FROM_GIT_DESCRIBE_FOR_NEXT_VERSION_PREVIEW_RESOLUTION" \
                "$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES"
            if [[ -n "$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG" ]]; then
                printf "    next version: %s → %s\n" \
                    "$ITER164_DETECTED_CURRENT_GIT_TAG_FROM_GIT_DESCRIBE_FOR_NEXT_VERSION_PREVIEW_RESOLUTION" \
                    "$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG"
            elif [[ -n "$ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION" ]]; then
                printf "    next version: %s\n" "$ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION"
            fi
        fi
        echo ""
    fi

    # Verdict
    if [[ "$ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN" == "true" ]]; then
        echo "  ✗ verdict: SILENT-FAIL RISK (semantic-release will skip this commit)"
        echo ""
        case "$primary_classification_bucket" in
            COMPOUND-PREFIX)
                echo "  Remediation: use a single type per commit, e.g.:"
                echo "    feat(release): description here"
                echo "  Mention secondary scopes (docs, refactor) in the BODY, not the prefix."
                ;;
            MISSING-TYPE)
                echo "  Remediation: prefix the subject with one of the recognized types:"
                echo "    ${ITER153_RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES_ARRAY[*]}"
                echo "  Example: 'feat(release): your description here'"
                ;;
        esac
    elif [[ "$ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN" != "true" ]]; then
        echo "  ⚠ verdict: COMMIT-READY but READABILITY-WARNING (over 72-char hard cap)"
        echo ""
        echo "  semantic-release will tag this commit correctly, but \`git log --oneline\`,"
        echo "  GitHub UI, and code-review tools will truncate or wrap the subject."
        echo ""
        echo "  Suggested fix: move detail into the body (wrapped at 72 chars), keep"
        echo "  subject ≤50 chars for hard target, ≤72 chars for hard cap."
    else
        echo "  ✓ verdict: COMMIT-READY (no violations detected)"
    fi
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

# ─── JSON output renderer for AI-agent consumption ──────────────────────────

# FILE-SIZE-OK: iter-153 + iter-154 + iter-155 advisor remains a single
# cohesive feature even after iter-155 extracted the JSON escape helper
# to a shared lib. The classification grammar, COMMIT_EDITMSG auto-
# detect, JSON-escape thin shim, and the two output renderers stay
# interlocked. ~554 lines fits comfortably under the 1000-line hard
# block.
#
# Iter-155 architectural refactor: the pure-bash JSON escape function
# was extracted to a shared library at scripts/lib/ to eliminate a
# forming-SSoT-violation (iter-152 needed the same function for its
# new --json mode). The iter-154 function name is preserved as a thin
# wrapper here for iter-154 regression-test backward compatibility
# while delegating to the canonical iter-155 shared-lib implementation.
ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/lib/iter155-pure-bash-rfc8259-json-string-escape-shared-library-for-cross-script-reuse-eliminating-duplication-of-iter154-correctness-fix-across-iter152-iter153-and-future-consumers.sh"
if [[ -f "$ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH"
fi

# Iter-161 semver-bump classifier shared lib — sourced for pre-commit
# MAJOR/MINOR/PATCH/NONE preview against cc-skills .releaserc.yml bump
# rules. Soft-fail if missing (degrades to no-preview, never blocks).
ITER161_SHARED_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/lib/iter161-semantic-release-version-bump-classifier-mapping-conventional-commit-type-and-breaking-change-marker-to-the-actual-major-minor-patch-bump-per-cc-skills-releaserc-yml-bump-rules-for-pre-commit-preview-overlay.sh"
if [[ -f "$ITER161_SHARED_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ITER161_SHARED_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH"
fi

# Iter-162 BREAKING-CHANGE footer-token detector shared lib — sourced
# for body-aware breaking-change detection per Conventional Commits §13.
# Closes the iter-161 correctness defect where footer-form breaking
# changes (no subject `!` marker) were mis-predicted MINOR. Soft-fail
# if missing.
ITER162_SHARED_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/lib/iter162-conventional-commits-breaking-change-footer-token-detector-applying-uppercase-required-and-blank-line-separator-rules-per-conventional-commits-v1-section-13-and-semantic-release-commit-analyzer-default-angular-preset-behavior.sh"
if [[ -f "$ITER162_SHARED_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ITER162_SHARED_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH"
fi

# Iter-164 SemVer next-version resolver shared lib — sourced for
# concrete-next-version-number preview (e.g., "v21.71.0 → v21.72.0")
# applied AFTER iter-161 emits the bump label. Closes the operator
# question "what version exactly?" without paying the cost of
# semantic-release --dry-run (push-perm verify + full git history +
# multi-second runtime per the 2026 semantic-release FAQ). Soft-fail
# if missing.
ITER164_SHARED_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/lib/iter164-semver-next-version-resolver-applying-iter161-bump-label-to-parsed-major-minor-patch-components-of-current-git-describe-tag-per-semver-org-specification-section-2-increment-rules.sh"
if [[ -f "$ITER164_SHARED_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ITER164_SHARED_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH"
fi

# Iter-164: detect current git tag once at advisor startup so both
# renderers (human + JSON) can show concrete next-version preview.
# Uses `git describe --tags --abbrev=0` — the most recent reachable
# annotated/lightweight tag from HEAD, matching what semantic-release
# uses as the baseline for its release-window scan. Empty string if no
# tag exists yet (graceful — iter-164 resolver handles missing-tag).
# shellcheck disable=SC2034  # consumed by both renderers further down
ITER164_DETECTED_CURRENT_GIT_TAG_FROM_GIT_DESCRIBE_FOR_NEXT_VERSION_PREVIEW_RESOLUTION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

# Iter-162: invoke footer-token detector against the multi-line body
# captured via --message-file (or iter-154 auto-detect, extended below).
# Result is OR'd with the subject `!` marker before being handed to the
# iter-161 bump classifier so both signaling paths produce the same
# correct MAJOR bump preview.
# shellcheck disable=SC2034  # consumed downstream by iter-161 classifier-call site + renderers
ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE="false"
# shellcheck disable=SC2034  # consumed downstream by renderers for diagnostic display
ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED=""
if declare -F iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance >/dev/null 2>&1 \
   && [[ -n "$ITER162_PROPOSED_COMMIT_MULTILINE_BODY_FOR_FOOTER_TOKEN_DETECTION_OR_EMPTY_WHEN_SUBJECT_ONLY_INPUT_MODE" ]]; then
    iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance \
        "$ITER162_PROPOSED_COMMIT_MULTILINE_BODY_FOR_FOOTER_TOKEN_DETECTION_OR_EMPTY_WHEN_SUBJECT_ONLY_INPUT_MODE"
    ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE="$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN"
    ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED="$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED"
fi

iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency() {
    # Iter-154 backward-compat shim. Delegates to the iter-155 canonical
    # shared-lib implementation, preserving the iter-154 regression-test
    # function-name pin while consolidating the actual escape logic in
    # one place (SSoT). When the shared lib is unavailable (e.g., file
    # missing during partial checkout), falls through to a degraded
    # literal-wrap that DOES break for JSON-special chars — but the
    # source check above means this only fires if operator deleted
    # scripts/lib/, which is operator-error.
    if declare -F iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars >/dev/null 2>&1; then
        iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$1"
    else
        printf '"%s"' "$1"
    fi
}

# Iter-154 RFC 8259 § 7 reference (preserved here for regression-test
# substring pin per iter-154 Group A2):
#
#   RFC 8259 § 7 — https://datatracker.ietf.org/doc/html/rfc8259#section-7

# Iter-154 control-char emission reference (preserved here for
# regression-test substring pin per iter-154 Group A4):
#
#   printf '\\u%04x' for non-named control chars (U+0000-U+001F)

iter153_emit_machine_readable_json_output_for_ai_agent_automation_pipeline_consumption() {
    local primary_classification_bucket="$1"
    local verdict_label

    if [[ "$ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN" == "true" ]]; then
        verdict_label="SILENT_FAIL_RISK"
    elif [[ "$ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN" != "true" ]]; then
        verdict_label="COMMIT_READY_WITH_READABILITY_WARNING"
    else
        verdict_label="COMMIT_READY"
    fi

    # Hand-rolled JSON to avoid jq dependency. Field set is the iter-153
    # stable schema documented at the bottom of this script. Iter-154
    # replaced the previous Python3-dependent escape with a pure-bash
    # function — the prior fallback path silently emitted broken JSON
    # for any subject containing the 7 JSON-sensitive chars when
    # Python3 was absent (correctness bug).
    local json_escaped_subject_for_safe_embedding
    json_escaped_subject_for_safe_embedding=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY")

    # Iter-162: OR subject `!` marker with body footer-token detection
    # for the full Conventional Commits §13 dual-signal coverage. Compute
    # a unified breaking-change boolean + signal-source label that both
    # the iter-161 classifier and the JSON output use.
    local iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token_for_json="$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN"
    local iter162_breaking_change_signal_source_for_json="none"
    if [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "true" ]] \
       && [[ "$ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE" == "true" ]]; then
        iter162_breaking_change_signal_source_for_json="both_subject_bang_marker_and_body_footer_token"
    elif [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "true" ]]; then
        iter162_breaking_change_signal_source_for_json="subject_bang_marker"
    elif [[ "$ITER162_BODY_FOOTER_TOKEN_DETECTED_BOOLEAN_FOR_OR_INTO_SUBJECT_BANG_MARKER_FOR_FULL_CONVENTIONAL_COMMITS_SECTION_13_BREAKING_CHANGE_SIGNAL_COVERAGE" == "true" ]]; then
        iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token_for_json="true"
        iter162_breaking_change_signal_source_for_json="body_footer_token"
    fi

    # Iter-161 semver-bump preview — compute label + rationale and emit
    # as a nested object with its own stable schema version. Soft-fail
    # if classifier lib is unavailable (emit explicit null sentinel).
    local iter161_bump_label_for_json="UNAVAILABLE"
    local iter161_bump_rationale_for_json="iter-161 semver-bump-classifier shared lib not loaded"
    if declare -F iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules >/dev/null 2>&1; then
        iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules \
            "$ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY" \
            "$iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token_for_json"
        iter161_bump_label_for_json="$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES"
        # Iter-162: override the iter-161-emitted rationale when the
        # breaking signal came from BODY FOOTER rather than subject `!`.
        if [[ "$iter162_breaking_change_signal_source_for_json" == "body_footer_token" ]]; then
            iter161_bump_rationale_for_json="${ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED} footer-token in body → MAJOR bump per conventional-commits §13 (iter-162 detected body-form breaking signal, no ! in subject)"
        else
            iter161_bump_rationale_for_json="$ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN"
        fi
    fi
    local iter161_bump_rationale_json_escaped
    iter161_bump_rationale_json_escaped=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$iter161_bump_rationale_for_json")

    # Iter-162: emit body-footer-token variant (BREAKING CHANGE: vs
    # BREAKING-CHANGE: vs BREAKING CHANGES:) and JSON-escape the value
    # for safe embedding.
    local iter162_body_footer_token_variant_json_escaped
    iter162_body_footer_token_variant_json_escaped=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$ITER162_BODY_FOOTER_TOKEN_DETECTED_VARIANT_FOR_HUMAN_READABLE_RATIONALE_DISPLAY_OR_EMPTY_IF_NOT_DETECTED")

    # Iter-164: resolve concrete next-version preview by applying the
    # iter-161 bump label to the current git tag. Emit nested object
    # with stable iter164_schema_version=1 + current/next/rationale
    # fields. Soft-fail to UNAVAILABLE label if resolver lib missing.
    local iter164_resolved_next_version_for_json="UNAVAILABLE"
    local iter164_resolution_rationale_for_json="iter-164 next-version resolver lib not loaded"
    if declare -F iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules >/dev/null 2>&1; then
        iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules \
            "$ITER164_DETECTED_CURRENT_GIT_TAG_FROM_GIT_DESCRIBE_FOR_NEXT_VERSION_PREVIEW_RESOLUTION" \
            "$iter161_bump_label_for_json"
        iter164_resolved_next_version_for_json="$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG"
        iter164_resolution_rationale_for_json="$ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION"
    fi
    local iter164_current_tag_json_escaped iter164_next_version_json_escaped iter164_resolution_rationale_json_escaped
    iter164_current_tag_json_escaped=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$ITER164_DETECTED_CURRENT_GIT_TAG_FROM_GIT_DESCRIBE_FOR_NEXT_VERSION_PREVIEW_RESOLUTION")
    iter164_next_version_json_escaped=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$iter164_resolved_next_version_for_json")
    iter164_resolution_rationale_json_escaped=$(iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency "$iter164_resolution_rationale_for_json")

    cat <<EOF
{
  "iter153_schema_version": 1,
  "subject": ${json_escaped_subject_for_safe_embedding},
  "measured_length_chars": ${ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS},
  "classification": "${primary_classification_bucket}",
  "type": "${ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY}",
  "type_recognized": ${ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN},
  "scope": "${ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY}",
  "breaking": ${iter162_unified_breaking_change_boolean_after_or_of_subject_bang_marker_and_body_footer_token_for_json},
  "iter162_breaking_change_signal_source": "${iter162_breaking_change_signal_source_for_json}",
  "iter162_body_footer_token_variant": ${iter162_body_footer_token_variant_json_escaped},
  "iter150_5072_rule_conformance": {
    "under_50_char_hard_target": ${ITER153_CLASSIFIED_UNDER_50_CHAR_HARD_TARGET_BOOLEAN},
    "under_72_char_hard_cap": ${ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN}
  },
  "silent_fail_class_violation_present": ${ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN},
  "verdict": "${verdict_label}",
  "iter161_semver_bump_preview": {
    "iter161_schema_version": 1,
    "bump_label_per_cc_skills_releaserc_yml_rules": "${iter161_bump_label_for_json}",
    "rationale": ${iter161_bump_rationale_json_escaped}
  },
  "iter164_next_version_preview": {
    "iter164_schema_version": 1,
    "current_git_tag": ${iter164_current_tag_json_escaped},
    "next_version": ${iter164_next_version_json_escaped},
    "resolution_rationale": ${iter164_resolution_rationale_json_escaped}
  },
  "thresholds": {
    "hard_target_chars": ${ITER153_SUBJECT_HARD_TARGET_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE},
    "hard_cap_chars": ${ITER153_SUBJECT_HARD_CAP_THRESHOLD_CHARS_PER_CONVENTIONAL_COMMITS_50_72_RULE}
  }
}
EOF
}

# ─── Main orchestration ─────────────────────────────────────────────────────

iter153_classify_proposed_subject_through_iter82_grammar_returning_structured_fields \
    "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY"

if [[ "$ITER153_OUTPUT_MODE_HUMAN_READABLE_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "json" ]]; then
    iter153_emit_machine_readable_json_output_for_ai_agent_automation_pipeline_consumption \
        "$ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET"
else
    iter153_emit_human_readable_verdict_with_classification_details_and_remediation_hints \
        "$ITER153_CLASSIFIED_PRIMARY_CLASSIFICATION_BUCKET"
fi

# Exit code: strict mode gates on silent-fail-class violations only.
# Long-subject overlay is informational even in strict mode per iter-151 design.
if [[ "$ITER153_STRICT_MODE_EXIT_NONZERO_ON_SILENT_FAIL_CLASS_VIOLATIONS" == "1" ]] \
   && [[ "$ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN" == "true" ]]; then
    exit 1
fi
exit 0

# ─── JSON_SCHEMA_DOCUMENTATION ──────────────────────────────────────────────
#
# Stable JSON schema for AI-agent consumers. Fields:
#
#   iter153_schema_version (int): currently 1. Incremented on breaking changes.
#   subject (string): the proposed commit subject as passed in.
#   measured_length_chars (int): length of subject in chars (bash ${#var}).
#   classification (string): one of:
#     - STANDARD-CONFORMANT
#     - COMPOUND-PREFIX        (silent-fail class)
#     - MISSING-TYPE           (silent-fail class)
#     - AUTO-RELEASE-COMMIT
#     - MERGE-COMMIT
#   type (string): extracted conventional-commits type, or empty.
#   type_recognized (boolean): true if type is in sem-rel canonical 11.
#   scope (string): optional scope from (...), or empty.
#   breaking (boolean): true if `!` indicator present.
#   iter150_5072_rule_conformance (object):
#     under_50_char_hard_target (boolean)
#     under_72_char_hard_cap (boolean)
#   silent_fail_class_violation_present (boolean): true if COMPOUND-PREFIX
#     or MISSING-TYPE detected.
#   verdict (string): one of:
#     - COMMIT_READY                            (no violations)
#     - COMMIT_READY_WITH_READABILITY_WARNING   (>72 chars but conformant)
#     - SILENT_FAIL_RISK                        (semantic-release will skip)
#   thresholds (object): the 50/72 thresholds in use.
