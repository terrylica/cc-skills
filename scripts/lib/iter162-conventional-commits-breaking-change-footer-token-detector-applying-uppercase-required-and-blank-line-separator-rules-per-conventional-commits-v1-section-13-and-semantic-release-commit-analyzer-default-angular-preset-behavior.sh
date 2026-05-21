#!/usr/bin/env bash
# Iter-162 conventional-commits BREAKING-CHANGE footer-token detector.
#
# WHY THIS EXISTS:
#
#   Iter-161 shipped a semver-bump preview overlay that classified
#   subject + `!` marker into MAJOR/MINOR/PATCH/NONE. But adversarial
#   audit surfaced a correctness defect: the conventional-commits v1.0.0
#   specification §13 (and semantic-release/commit-analyzer's default
#   Angular preset) recognize TWO equivalent ways to signal a breaking
#   change:
#
#     (1) The `!` marker in the type/scope prefix
#         (e.g. `feat!: rename foo`, `refactor(api)!: ...`)
#         → iter-161 covers this.
#
#     (2) A BREAKING-CHANGE footer-token in the commit BODY
#         (e.g. `BREAKING CHANGE: API moved`)
#         → iter-161 does NOT see this — only the subject is passed in.
#
#   Operators who use the footer form (which the canonical spec
#   recommends "when migration steps need explanation" per
#   https://www.conventionalcommits.org/en/v1.0.0/) currently get a
#   WRONG MINOR preview from iter-161 when the actual semantic-release
#   bump will be MAJOR. This is a correctness defect, not a usability
#   gap.
#
#   Iter-162 closes this defect by providing a pure-bash detector for
#   the canonical breaking-change footer tokens, consumable by the
#   iter-153 advisor when full multi-line commit-message input is
#   available.
#
# RECOGNIZED TOKEN FORMS (per conventional-commits v1.0.0 + Angular preset):
#
#   - `BREAKING CHANGE: <description>`   (canonical spec form)
#   - `BREAKING-CHANGE: <description>`   (canonical spec synonym, §13)
#   - `BREAKING CHANGES: <description>`  (Angular plural variant —
#                                          semantic-release default
#                                          preset accepts this too)
#
#   All forms MUST be uppercase (per spec — "MUST NOT be treated as
#   case-sensitive by implementors, with the exception of BREAKING
#   CHANGE which MUST be uppercase"). The colon-space-text suffix
#   matches the git-trailer footer-token grammar.
#
# DESIGN INVARIANTS:
#
#   - Pure-bash, no external dependencies. Mirrors iter-155 / iter-161
#     shared-lib design pattern: sourceable, writes a single output
#     boolean to a global variable for caller pickup.
#
#   - Detection is line-anchored. The token MUST appear at the start
#     of a line (^pattern) — this prevents false positives like an
#     in-prose mention of "no BREAKING CHANGE: here" in a paragraph.
#     The spec says footers come "one blank line after the body" but
#     in practice many semantic-release configurations (including the
#     cc-skills .releaserc.yml default Angular preset) accept the
#     token anywhere it appears on its own line in the body, so we
#     follow the permissive-implementation contract rather than the
#     strict-spec contract.
#
#   - Token detection is CASE-SENSITIVE for the keyword itself (per
#     spec). The colon, space, and following description are not
#     checked for case.
#
# USAGE:
#
#   source scripts/lib/iter162-...sh
#   iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance \
#       "$multi_line_commit_message_body_string"
#   if [[ "$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN" == "true" ]]; then
#       echo "MAJOR bump"
#   fi
#
# PRIOR ART:
#
#   - https://www.conventionalcommits.org/en/v1.0.0/ §13
#   - https://github.com/semantic-release/commit-analyzer
#     (default Angular preset noteKeywords)
#   - https://www.pkgpulse.com/blog/semantic-versioning-guide-
#     breaking-changes-2026

# Output global — consumed by sourcing caller after function invocation.
# The SC2034 suppression idiom mirrors iter-161 (the lint-tool cannot
# trace cross-file reads of sourced-library globals).
# shellcheck disable=SC2034
ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN="false"

# shellcheck disable=SC2034
ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED=""

# Sentinel signaling successful library load, mirroring iter-155/iter-161 pattern.
export ITER162_CONVENTIONAL_COMMITS_BREAKING_CHANGE_FOOTER_TOKEN_DETECTOR_LIBRARY_LOADED_SENTINEL=1

iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance() {
    local multi_line_commit_message_body_input="$1"

    # Reset output globals on each invocation.
    ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN="false"
    ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED=""

    if [[ -z "$multi_line_commit_message_body_input" ]]; then
        return 0
    fi

    # Iterate line-by-line and check for any of the three canonical
    # breaking-change token forms at start-of-line. Bash `while read`
    # with IFS= preserves leading whitespace, but we explicitly trim
    # nothing — token MUST be flush-left per the conventional-commits
    # footer-token grammar (no indentation allowed for footer trailers).
    while IFS= read -r each_line_of_commit_message_body; do
        # Canonical Conventional Commits v1.0.0 spec form (singular).
        if [[ "$each_line_of_commit_message_body" =~ ^BREAKING\ CHANGE:[\ ].+ ]]; then
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN="true"
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED="BREAKING CHANGE:"
            return 0
        fi
        # Canonical Conventional Commits v1.0.0 hyphen synonym (§13).
        if [[ "$each_line_of_commit_message_body" =~ ^BREAKING-CHANGE:[\ ].+ ]]; then
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN="true"
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED="BREAKING-CHANGE:"
            return 0
        fi
        # Angular plural variant — accepted by semantic-release default preset.
        if [[ "$each_line_of_commit_message_body" =~ ^BREAKING\ CHANGES:[\ ].+ ]]; then
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN="true"
            ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_VARIANT_FOR_DIAGNOSTIC_RATIONALE_OR_EMPTY_IF_NOT_DETECTED="BREAKING CHANGES:"
            return 0
        fi
    done <<< "$multi_line_commit_message_body_input"
}
