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

iter153_print_usage_help_text_and_exit_with_code_two() {
    cat <<'EOF'
Usage: commits:advise [--json] [--strict] -- "<proposed subject>"
   or: echo "<subject>" | commits:advise [--json] [--strict] --

Pre-commit dry-run advisor. Classifies a proposed conventional-commit
subject through the iter-82/iter-151 grammar without committing.

Modes:
  --json     Emit machine-readable JSON for AI-agent automation.
  --strict   Exit non-zero on silent-fail-class violations (COMPOUND-
             PREFIX or MISSING-TYPE). Long-subject overlay remains
             informational even in --strict mode.

Examples:
  commits:advise -- "feat(release): iter-153 short subject"
  commits:advise --json -- "feat: foo" | jq .verdict
  commits:advise --strict -- "feat(scope)+docs: bad compound prefix"
EOF
    exit 2
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

if [[ -z "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY" ]]; then
    echo "Error: no proposed subject provided" >&2
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
    if [[ "$ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN" == "true" ]]; then
        printf "  breaking change:        ✓ yes (! suffix detected)\n"
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
    # stable schema documented at the bottom of this script.
    local json_escaped_subject_for_safe_embedding
    json_escaped_subject_for_safe_embedding=$(
        printf '%s' "$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY" \
            | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' 2>/dev/null \
            || printf '%s' "\"$ITER153_PROPOSED_COMMIT_SUBJECT_TO_CLASSIFY\""
    )

    cat <<EOF
{
  "iter153_schema_version": 1,
  "subject": ${json_escaped_subject_for_safe_embedding},
  "measured_length_chars": ${ITER153_CLASSIFIED_MEASURED_LENGTH_IN_CHARS},
  "classification": "${primary_classification_bucket}",
  "type": "${ITER153_CLASSIFIED_EXTRACTED_CONVENTIONAL_COMMIT_TYPE_OR_EMPTY}",
  "type_recognized": ${ITER153_CLASSIFIED_TYPE_RECOGNIZED_IN_SEMREL_CANONICAL_SET_BOOLEAN},
  "scope": "${ITER153_CLASSIFIED_EXTRACTED_OPTIONAL_SCOPE_OR_EMPTY}",
  "breaking": ${ITER153_CLASSIFIED_BREAKING_CHANGE_INDICATOR_BOOLEAN},
  "iter150_5072_rule_conformance": {
    "under_50_char_hard_target": ${ITER153_CLASSIFIED_UNDER_50_CHAR_HARD_TARGET_BOOLEAN},
    "under_72_char_hard_cap": ${ITER153_CLASSIFIED_UNDER_72_CHAR_HARD_CAP_BOOLEAN}
  },
  "silent_fail_class_violation_present": ${ITER153_CLASSIFIED_SILENT_FAIL_CLASS_VIOLATION_PRESENT_BOOLEAN},
  "verdict": "${verdict_label}",
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
