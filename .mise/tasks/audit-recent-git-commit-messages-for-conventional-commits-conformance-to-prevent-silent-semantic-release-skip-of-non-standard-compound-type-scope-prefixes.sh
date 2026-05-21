#!/usr/bin/env bash
#MISE description="Iter-82 preventive validator: scans the last N git commits (default 20) for conventional-commit conformance per the standard at https://www.conventionalcommits.org/. Detects the silent-failure class where compound type-scope prefixes like 'feat(scope)+docs:' or 'fix(scope)+feat(scope):' are skipped by semantic-release's commit-analyzer with NO diagnostic — the commit lands but produces no version-bump tag, requiring a subsequent properly-formatted commit to sweep it up. Iter-77, iter-80, and iter-81 each suffered this silent skip before discovery. Default mode reports non-conformance as INFORMATIONAL warnings; --strict mode exits non-zero on any non-conformance since the last release tag (release-gate use-case). Supports --range <git-revspec> override for arbitrary lookback windows."

# Iter-82 conventional-commits conformance validator.
#
# Background: silent-failure class observed iter-77 / iter-80 / iter-81
#
#   Three iters in a row (77, 80, 81) used commit messages of the form:
#
#     fix(link-tools)+feat(release-gate): iter-77...
#     perf(release-gate)+docs: iter-80...
#     feat(release-gate)+docs: iter-81...
#
#   The conventional-commits parser at @semantic-release/commit-analyzer
#   uses a regex roughly equivalent to:
#
#     ^(?<type>\w+)(\((?<scope>[^)]+)\))?(?<breaking>!)?:\s+
#
#   Compound prefixes like `feat(scope)+docs:` do NOT match because the
#   `+docs` segment falls AFTER the closing paren but BEFORE the colon
#   — outside the parser's grammar. The commit-analyzer reports "no
#   release type detected" and SILENTLY skips the commit. No tag fires.
#
#   The commit still lands on main (the git workflow proceeds). The
#   release skip is operator-invisible without dedicated investigation:
#   there is no "ERROR" line, no rejected-commit log entry, just an
#   absence of the expected tag.
#
#   This validator detects the silent-skip class BEFORE it lands by
#   scanning the recent commit history for non-conforming prefixes.
#
# What this validator checks:
#
#   For each commit in the configured range:
#     - Extract the subject line (first line of commit message)
#     - Apply the conventional-commits regex
#     - Classify:
#         CONFORMANT          → subject matches the canonical grammar
#         COMPOUND-PREFIX     → has `+type` or `;type` between scope and colon
#         MISSING-TYPE        → subject doesn't start with a recognized type
#         MERGE-COMMIT        → "Merge ..." (excluded by semantic-release anyway)
#         AUTO-RELEASE-COMMIT → "chore(release): X.Y.Z [skip ci]" (created by @semantic-release/git)
#
# Recognized conventional-commits types (default release configuration):
#
#   feat, fix, perf, revert, docs, chore, style, refactor, test, build, ci
#
# Modes:
#
#   default (informational):
#     - Scans last N=20 commits
#     - Prints classification per non-conformant commit
#     - Exits 0 regardless (gives operators visibility without blocking)
#
#   --strict:
#     - Scans commits since the last release tag
#     - Exits non-zero on ANY COMPOUND-PREFIX or MISSING-TYPE
#     - Suitable for release:preflight gating
#
#   --range <revspec>:
#     - Override the commit range (e.g., HEAD~50..HEAD)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# Defaults
COMMIT_HISTORY_LOOKBACK_WINDOW_COMMIT_COUNT_FOR_INFORMATIONAL_MODE=20
STRICT_MODE_GATE_RELEASE_PIPELINE_ON_NONCONFORMANCE=0
GIT_REVISION_SPEC_OVERRIDE_FOR_ARBITRARY_RANGE=""

# Recognized conventional-commits types, MATCHED against the
# .releaserc.yml commit-analyzer release-rules configuration.
# Update this set if .releaserc.yml's release-rules block changes.
RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES=(
    feat fix perf revert docs chore style refactor test build ci
)

# Auto-release commit message pattern produced by @semantic-release/git:
# "chore(release): X.Y.Z [skip ci]". Excluded from non-conformance
# reporting since these are bot-generated and always conformant by
# construction.
AUTO_RELEASE_COMMIT_MESSAGE_PATTERN_REGEX='^chore\(release\): [0-9]+\.[0-9]+\.[0-9]+ \[skip ci\]$'

# Compound-prefix anti-pattern: a recognized type followed by an
# optional scope, then ANYTHING other than ! or : before the colon.
# Examples that match (BAD):
#   feat(scope)+docs:
#   fix(scope);refactor:
#   perf(a)+chore(b):
# Examples that don't match (OK):
#   feat:
#   feat(scope):
#   feat!:
#   feat(scope)!:
COMPOUND_PREFIX_ANTI_PATTERN_REGEX='^[a-z]+(\([^)]+\))?[^!:](.*)?:'

# Standard conventional-commits header regex (exclusive of compound).
STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX='^[a-z]+(\([^)]+\))?!?: .+'

# Parse argv
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT_MODE_GATE_RELEASE_PIPELINE_ON_NONCONFORMANCE=1
            shift
            ;;
        --range)
            GIT_REVISION_SPEC_OVERRIDE_FOR_ARBITRARY_RANGE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--strict] [--range <git-revspec>]"
            echo ""
            echo "  --strict       Exit non-zero on any non-conformance (release-gate mode)."
            echo "                 Default range = (last-release-tag)..HEAD."
            echo "  --range REV    Override the commit range. Default = HEAD~${COMMIT_HISTORY_LOOKBACK_WINDOW_COMMIT_COUNT_FOR_INFORMATIONAL_MODE}..HEAD."
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--strict] [--range <git-revspec>]"
            exit 2
            ;;
    esac
done

# Resolve the effective commit range.
if [[ -n "$GIT_REVISION_SPEC_OVERRIDE_FOR_ARBITRARY_RANGE" ]]; then
    effective_git_revision_range="$GIT_REVISION_SPEC_OVERRIDE_FOR_ARBITRARY_RANGE"
elif [[ "$STRICT_MODE_GATE_RELEASE_PIPELINE_ON_NONCONFORMANCE" == "1" ]]; then
    last_release_tag_or_empty=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ -n "$last_release_tag_or_empty" ]]; then
        effective_git_revision_range="$last_release_tag_or_empty..HEAD"
    else
        effective_git_revision_range="HEAD~${COMMIT_HISTORY_LOOKBACK_WINDOW_COMMIT_COUNT_FOR_INFORMATIONAL_MODE}..HEAD"
    fi
else
    effective_git_revision_range="HEAD~${COMMIT_HISTORY_LOOKBACK_WINDOW_COMMIT_COUNT_FOR_INFORMATIONAL_MODE}..HEAD"
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Conventional-Commits Conformance Validator (iter-82)"
echo "═══════════════════════════════════════════════════════════════════════════"
printf "  Commit range:        %s\n" "$effective_git_revision_range"
if [[ "$STRICT_MODE_GATE_RELEASE_PIPELINE_ON_NONCONFORMANCE" == "1" ]]; then
    echo "  Mode:                STRICT (exits non-zero on non-conformance)"
else
    echo "  Mode:                informational (exits 0 regardless)"
fi
echo "  Recognized types:    ${RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES[*]}"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# Walk the commit range.
total_commits_scanned_in_configured_range=0
total_conformant_commits=0
total_auto_release_commits=0
total_merge_commits=0
total_compound_prefix_violations=0
total_missing_type_violations=0
declare -a compound_prefix_violation_diagnostic_lines=()
declare -a missing_type_violation_diagnostic_lines=()

while IFS=$'\t' read -r short_commit_sha commit_subject_line; do
    [[ -z "$short_commit_sha" ]] && continue
    total_commits_scanned_in_configured_range=$((total_commits_scanned_in_configured_range + 1))

    # Classify in priority order: merge, auto-release, compound-prefix,
    # standard-conformant, missing-type.

    # 1. Merge commit
    if [[ "$commit_subject_line" =~ ^Merge[[:space:]] ]]; then
        total_merge_commits=$((total_merge_commits + 1))
        continue
    fi

    # 2. Auto-release commit
    if [[ "$commit_subject_line" =~ $AUTO_RELEASE_COMMIT_MESSAGE_PATTERN_REGEX ]]; then
        total_auto_release_commits=$((total_auto_release_commits + 1))
        continue
    fi

    # 3. Compound-prefix violation (silent-fail class)
    if [[ "$commit_subject_line" =~ $COMPOUND_PREFIX_ANTI_PATTERN_REGEX ]] \
       && ! [[ "$commit_subject_line" =~ $STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX ]]; then
        total_compound_prefix_violations=$((total_compound_prefix_violations + 1))
        compound_prefix_violation_diagnostic_lines+=(
            "  - $short_commit_sha  $commit_subject_line"
        )
        continue
    fi

    # 4. Standard conformant — check type is in recognized list.
    if [[ "$commit_subject_line" =~ $STANDARD_CONVENTIONAL_COMMITS_HEADER_REGEX ]]; then
        extracted_commit_type_prefix="${commit_subject_line%%[(:]*}"
        type_recognized="no"
        for recognized_type in "${RECOGNIZED_CONVENTIONAL_COMMITS_RELEASE_TRIGGERING_TYPES[@]}"; do
            if [[ "$extracted_commit_type_prefix" == "$recognized_type" ]]; then
                type_recognized="yes"
                break
            fi
        done
        if [[ "$type_recognized" == "yes" ]]; then
            total_conformant_commits=$((total_conformant_commits + 1))
        else
            total_missing_type_violations=$((total_missing_type_violations + 1))
            missing_type_violation_diagnostic_lines+=(
                "  - $short_commit_sha  $commit_subject_line"
                "      (type '$extracted_commit_type_prefix' is not in recognized set)"
            )
        fi
        continue
    fi

    # 5. Doesn't match anything — missing-type violation.
    total_missing_type_violations=$((total_missing_type_violations + 1))
    missing_type_violation_diagnostic_lines+=(
        "  - $short_commit_sha  $commit_subject_line"
    )
done < <(
    git log --pretty='%h%x09%s' "$effective_git_revision_range" 2>/dev/null
)

# Render summary.
echo "  Total commits scanned:                        $total_commits_scanned_in_configured_range"
echo "  Standard-conformant:                          $total_conformant_commits"
echo "  Auto-release (chore(release) by sem-rel):     $total_auto_release_commits"
echo "  Merge commits:                                $total_merge_commits"
echo "  Compound-prefix violations (silent-fail):     $total_compound_prefix_violations"
echo "  Missing-type / unrecognized-type violations:  $total_missing_type_violations"

if [[ "$total_compound_prefix_violations" -gt 0 ]]; then
    echo ""
    echo "─── Compound-prefix violations (each silently rejected by semantic-release) ───"
    printf '%s\n' "${compound_prefix_violation_diagnostic_lines[@]}"
    echo ""
    echo "  These commits used a compound prefix like 'feat(scope)+docs:' which the"
    echo "  @semantic-release/commit-analyzer regex (^type(\(scope\))?!?:) does NOT"
    echo "  match. Each landed on main but produced NO version-bump tag."
    echo ""
    echo "  Fix going forward: use a single type per commit, e.g.:"
    echo "    feat(release-gate): description here"
    echo "  Mention secondary scopes (docs, refactor) in the BODY, not the prefix."
fi

if [[ "$total_missing_type_violations" -gt 0 ]]; then
    echo ""
    echo "─── Missing-type / unrecognized-type violations ───"
    printf '%s\n' "${missing_type_violation_diagnostic_lines[@]}"
fi

echo ""

# Exit code: strict mode gates on violations.
total_violations_blocking_strict_mode=$((
    total_compound_prefix_violations + total_missing_type_violations
))
if [[ "$STRICT_MODE_GATE_RELEASE_PIPELINE_ON_NONCONFORMANCE" == "1" ]] \
   && [[ "$total_violations_blocking_strict_mode" -gt 0 ]]; then
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  ✗ STRICT MODE: $total_violations_blocking_strict_mode non-conformant commit(s) since last tag"
    echo "═══════════════════════════════════════════════════════════════════════════"
    exit 1
fi

if [[ "$total_violations_blocking_strict_mode" -eq 0 ]]; then
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  ✓ All commits in range are conventional-commits-conformant"
    echo "═══════════════════════════════════════════════════════════════════════════"
else
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  ⚠ $total_violations_blocking_strict_mode non-conformant commit(s) detected (informational; not gating)"
    echo "═══════════════════════════════════════════════════════════════════════════"
fi
exit 0
