#!/usr/bin/env bash
# Iter-165 pending-release aggregator — what does the NEXT release contain?
#
# WHY THIS EXISTS:
#
#   The iter-150 → iter-164 arc answers progressively-richer single-commit
#   questions: is this subject grammatical (iter-82), readable (iter-150,
#   iter-151), what bump label does it trigger (iter-161), what concrete
#   next version does that bump label resolve to (iter-164)? Each tool
#   takes ONE subject (or one --message-file) as input.
#
#   But operators who run `mise run release:full` rarely care about
#   ONE commit. They care about the AGGREGATE of every commit since
#   the last tag — the actual release that will land. By the time
#   the operator is about to run release:full they have already made
#   3–10 commits over the past day/week and the actual question is:
#
#     "Across all unreleased commits since v21.72.0, what does the
#      next release look like? Which version number? Triggered by
#      which commit? Why?"
#
#   Industry prior art (commitlint, commitizen, conventional-pre-commit,
#   git-cliff, semantic-release --dry-run) either stops at single-commit
#   grammar OR is heavyweight: semantic-release --dry-run verifies push
#   permissions per the 2026 sem-rel FAQ, requires fetch-depth=0 git
#   history, spins up Node + 5+ plugins, and runs multi-second. git
#   cliff --bumped-version requires Rust + a config file.
#
#   Iter-165 closes the gap with a pure-bash aggregator:
#     1. Walk `git log <most-recent-tag>..HEAD` (oldest-first).
#     2. For each commit: extract type + bang marker from subject, run
#        the iter-162 footer-token detector on the body, OR the two
#        signals, classify via iter-161.
#     3. Aggregate via semver precedence MAJOR > MINOR > PATCH > NONE
#        (taking the MAXIMUM, which is exactly how
#        semantic-release/commit-analyzer computes the release bump).
#     4. Resolve the aggregate bump label to a concrete next version
#        via iter-164.
#
#   Result: in one mise task invocation the operator learns what their
#   pending release is, which commits drive which bumps, and the exact
#   next version that will tag — all under one second, no network, no
#   Node.
#
# DESIGN INVARIANTS:
#
#   - Pure-bash, no external dependencies beyond git (already required
#     for cc-skills). Sources four shared libs (iter-155 JSON-escape,
#     iter-161 classifier, iter-162 footer-detector, iter-164 resolver).
#
#   - Aggregate bump = MAX over commit bumps per SemVer precedence:
#       MAJOR=3 > MINOR=2 > PATCH=1 > NONE=0
#     This precisely mirrors semantic-release/commit-analyzer behavior
#     for a multi-commit release window.
#
#   - Commits not matching any conventional-commits type silently
#     classify as NONE (correct: semantic-release skips them too —
#     they do not block other commits in the window from triggering a
#     release).
#
#   - Both human-readable and --json output modes. --json emits a
#     stable schema with iter165_schema_version=1 for AI-agent
#     automation pipelines (CI dashboards, slack-bot release-notice
#     generators, pre-release sanity checks).
#
#   - Sub-second on typical release windows (<50 commits). One
#     `git log --reverse --format='%H'` + N `git log -1 --format=%s`
#     + N `git log -1 --format=%b` invocations. For N=50 that's
#     ~101 git-process forks but each is local-only and quick.
#
# OUTPUT FORMAT (human, default):
#
#   ═════════════════════════════════════════════════════════════════
#     COMMITS PENDING-RELEASE PREVIEW (iter-165 aggregate next-release)
#   ═════════════════════════════════════════════════════════════════
#     current git tag:       v21.72.0
#     commits since tag:     3
#
#     per-commit breakdown (oldest → newest):
#       9d3e2456  feat(release): iter-164 next-version preview     → MINOR
#       2f24404d  fix(release): iter-163 test parallel-safe        → PATCH
#       abc12345  docs: clarify autoloop semantics                  → PATCH
#
#     bump histogram:        MAJOR=0  MINOR=1  PATCH=2  NONE=0
#     aggregate bump:        MINOR (max precedence: MAJOR > MINOR > PATCH > NONE)
#     next release version:  v21.72.0 → v21.73.0
#
#     triggered by:          9d3e2456 feat(release): iter-164 next-version preview
#   ═════════════════════════════════════════════════════════════════
#
# OUTPUT FORMAT (--json):
#
#   {
#     "iter165_schema_version": 1,
#     "current_git_tag": "v21.72.0",
#     "commit_count_since_tag": 3,
#     "per_commit_bump_breakdown": [
#       { "short_sha": "...", "subject": "...", "bump_label": "MINOR", "rationale": "..." },
#       ...
#     ],
#     "bump_histogram": { "MAJOR": 0, "MINOR": 1, "PATCH": 2, "NONE": 0 },
#     "aggregate_bump_label_per_semver_precedence": "MINOR",
#     "aggregate_bump_rationale": "...",
#     "triggering_commit_short_sha_at_highest_precedence": "9d3e2456",
#     "iter164_next_version_preview": {
#       "iter164_schema_version": 1,
#       "current_git_tag": "v21.72.0",
#       "next_version": "v21.73.0",
#       "resolution_rationale": "..."
#     }
#   }
#
# USAGE:
#
#   mise run commits:pending-release
#   mise run commits:pending-release --json | jq .aggregate_bump_label_per_semver_precedence
#
# PRIOR ART:
#
#   - semantic-release --dry-run: industry-standard heavyweight pre-release
#     preview (https://semantic-release.gitbook.io/semantic-release/usage/configuration#dry-run-mode)
#   - git-cliff --bumped-version: Rust-based equivalent
#     (https://git-cliff.org/docs/usage/bumped-version)
#   - cc-skills iter-153 + iter-164: single-commit + single-subject preview
#
# AUTHORS / HISTORY:
#
#   - iter-165 first ship: this commit
#   - Future iter could add --since <tag> override, --until <ref>, etc.

set -euo pipefail

# Resolve target git repo (what to walk) and script home (where libs live).
# These are deliberately separate so iter-165 can run from any cwd while
# always sourcing the libs from its own cc-skills install location — which
# also makes it parallel-safe under regression tests that spin up synthetic
# git repos in /tmp via ITER165_REPO_ROOT_OVERRIDE.
ITER165_TARGET_GIT_REPO_TOPLEVEL_ABSOLUTE_PATH_TO_WALK_FOR_RELEASE_PREVIEW="${ITER165_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER165_TARGET_GIT_REPO_TOPLEVEL_ABSOLUTE_PATH_TO_WALK_FOR_RELEASE_PREVIEW"

ITER165_SCRIPT_HOME_DIRECTORY_ABSOLUTE_PATH_RESOLVED_FROM_BASH_SOURCE_FOR_SHARED_LIB_LOCATION_PINNING="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER165_SHARED_LIBRARY_ABSOLUTE_DIRECTORY_PATH="$ITER165_SCRIPT_HOME_DIRECTORY_ABSOLUTE_PATH_RESOLVED_FROM_BASH_SOURCE_FOR_SHARED_LIB_LOCATION_PINNING/lib"

# ─── Source four shared libraries: iter-155, iter-161, iter-162, iter-164 ────
# Pinned absolute paths discovered via globs at load-time to avoid hardcoding
# long filenames inline.
ITER165_RESOLVED_ITER155_LIBRARY_PATH=$(echo "$ITER165_SHARED_LIBRARY_ABSOLUTE_DIRECTORY_PATH"/iter155-*.sh | head -1)
ITER165_RESOLVED_ITER161_LIBRARY_PATH=$(echo "$ITER165_SHARED_LIBRARY_ABSOLUTE_DIRECTORY_PATH"/iter161-*.sh | head -1)
ITER165_RESOLVED_ITER162_LIBRARY_PATH=$(echo "$ITER165_SHARED_LIBRARY_ABSOLUTE_DIRECTORY_PATH"/iter162-*.sh | head -1)
ITER165_RESOLVED_ITER164_LIBRARY_PATH=$(echo "$ITER165_SHARED_LIBRARY_ABSOLUTE_DIRECTORY_PATH"/iter164-*.sh | head -1)

# shellcheck source=/dev/null
source "$ITER165_RESOLVED_ITER155_LIBRARY_PATH"
# shellcheck source=/dev/null
source "$ITER165_RESOLVED_ITER161_LIBRARY_PATH"
# shellcheck source=/dev/null
source "$ITER165_RESOLVED_ITER162_LIBRARY_PATH"
# shellcheck source=/dev/null
source "$ITER165_RESOLVED_ITER164_LIBRARY_PATH"

# ─── Parse command-line flags ────────────────────────────────────────────────
ITER165_OUTPUT_MODE_HUMAN_OR_JSON="human"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            ITER165_OUTPUT_MODE_HUMAN_OR_JSON="json"
            shift
            ;;
        -h|--help)
            cat <<'HELP_EOF'
Usage: commits:pending-release [--json]

Iter-165 pending-release aggregator. Walks every commit between the most
recent reachable git tag and HEAD, classifies each via iter-161
{type, breaking-marker} → bump-label rules, takes the maximum bump per
SemVer precedence (MAJOR > MINOR > PATCH > NONE), and resolves the
aggregate bump label to the concrete next version via iter-164.

Modes:
  (default)   Human-readable banner with per-commit breakdown
  --json      Machine-readable JSON for AI-agent automation pipelines

Pure-bash, sub-second alternative to `semantic-release --dry-run`. No
network access. No push-permission verification. No fetch-depth=0
requirement.
HELP_EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: commits:pending-release [--json]" >&2
            exit 64
            ;;
    esac
done

# ─── ANSI colors for human output (gracefully degrade if not a TTY) ──────────
if [[ "$ITER165_OUTPUT_MODE_HUMAN_OR_JSON" == "human" && -t 1 ]]; then
    ITER165_ANSI_BOLD=$'\033[1m'
    ITER165_ANSI_CYAN=$'\033[36m'
    ITER165_ANSI_GREEN=$'\033[32m'
    ITER165_ANSI_YELLOW=$'\033[33m'
    ITER165_ANSI_RED=$'\033[31m'
    ITER165_ANSI_DIM=$'\033[2m'
    ITER165_ANSI_RESET=$'\033[0m'
else
    ITER165_ANSI_BOLD=""
    ITER165_ANSI_CYAN=""
    ITER165_ANSI_GREEN=""
    ITER165_ANSI_YELLOW=""
    ITER165_ANSI_RED=""
    ITER165_ANSI_DIM=""
    ITER165_ANSI_RESET=""
fi

# ─── Step 1: discover current git tag (most recent reachable from HEAD) ──────
ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST="$(git describe --tags --abbrev=0 2>/dev/null || true)"

# ─── Step 2: collect SHAs of commits between current tag and HEAD ────────────
# Oldest-first ordering matches the natural "what will land next" reading.
# If no tag exists (fresh repo), fall back to walking all of HEAD's history.
if [[ -n "$ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST" ]]; then
    ITER165_GIT_LOG_RANGE_SPECIFIER_FROM_TAG_EXCLUSIVE_TO_HEAD_INCLUSIVE="${ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST}..HEAD"
else
    ITER165_GIT_LOG_RANGE_SPECIFIER_FROM_TAG_EXCLUSIVE_TO_HEAD_INCLUSIVE="HEAD"
fi

mapfile -t ITER165_COLLECTED_COMMIT_SHA_ARRAY_OLDEST_FIRST_BETWEEN_CURRENT_TAG_AND_HEAD < <(
    git log --reverse --format='%H' "$ITER165_GIT_LOG_RANGE_SPECIFIER_FROM_TAG_EXCLUSIVE_TO_HEAD_INCLUSIVE" 2>/dev/null || true
)
ITER165_TOTAL_COMMIT_COUNT_SINCE_MOST_RECENT_GIT_TAG=${#ITER165_COLLECTED_COMMIT_SHA_ARRAY_OLDEST_FIRST_BETWEEN_CURRENT_TAG_AND_HEAD[@]}

# ─── Step 3: classify each commit ────────────────────────────────────────────
# Aggregation state — track maximum bump per SemVer precedence.
declare -A ITER165_BUMP_LABEL_TO_SEMVER_PRECEDENCE_RANK_INTEGER_LOOKUP_TABLE=(
    [MAJOR]=3
    [MINOR]=2
    [PATCH]=1
    [NONE]=0
)
declare -A ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW=(
    [MAJOR]=0
    [MINOR]=0
    [PATCH]=0
    [NONE]=0
)
ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW="NONE"
ITER165_AGGREGATE_BUMP_RANK_INTEGER_HIGHEST_OBSERVED=0
ITER165_TRIGGERING_COMMIT_SHORT_SHA_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY_IF_ALL_NONE=""
ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY=""

# Per-commit human + JSON record accumulators.
ITER165_HUMAN_READABLE_PER_COMMIT_BREAKDOWN_LINE_ARRAY=()
ITER165_JSON_PER_COMMIT_RECORD_ARRAY=()

iter165_extract_conventional_commit_type_and_bang_marker_presence_from_subject_via_anchored_regex_capture_groups() {
    # Parses subject of the form "type[(scope)][!]: description" and
    # populates two output globals. Matches iter-82's grammar.
    local subject_to_parse="$1"
    ITER165_EXTRACTED_TYPE_FROM_SUBJECT_OR_EMPTY_IF_NON_CONVENTIONAL=""
    ITER165_EXTRACTED_BANG_MARKER_PRESENCE_BOOLEAN_FROM_SUBJECT="false"
    if [[ "$subject_to_parse" =~ ^([a-zA-Z]+)(\([^\)]*\))?(\!)?:\ .+ ]]; then
        ITER165_EXTRACTED_TYPE_FROM_SUBJECT_OR_EMPTY_IF_NON_CONVENTIONAL="${BASH_REMATCH[1]}"
        if [[ -n "${BASH_REMATCH[3]}" ]]; then
            ITER165_EXTRACTED_BANG_MARKER_PRESENCE_BOOLEAN_FROM_SUBJECT="true"
        fi
    fi
}

for iter165_each_commit_sha in "${ITER165_COLLECTED_COMMIT_SHA_ARRAY_OLDEST_FIRST_BETWEEN_CURRENT_TAG_AND_HEAD[@]}"; do
    iter165_each_short_sha="${iter165_each_commit_sha:0:8}"
    iter165_each_subject="$(git log -1 --format='%s' "$iter165_each_commit_sha")"
    iter165_each_body="$(git log -1 --format='%b' "$iter165_each_commit_sha")"

    iter165_extract_conventional_commit_type_and_bang_marker_presence_from_subject_via_anchored_regex_capture_groups "$iter165_each_subject"
    iter165_each_type="$ITER165_EXTRACTED_TYPE_FROM_SUBJECT_OR_EMPTY_IF_NON_CONVENTIONAL"
    iter165_each_bang_present_boolean="$ITER165_EXTRACTED_BANG_MARKER_PRESENCE_BOOLEAN_FROM_SUBJECT"

    # OR with iter-162 body footer detection (per Conventional Commits §13).
    iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance \
        "$iter165_each_body"
    if [[ "$ITER162_DETECTED_BREAKING_CHANGE_FOOTER_TOKEN_AT_START_OF_LINE_IN_BODY_BOOLEAN" == "true" ]]; then
        iter165_each_bang_present_boolean="true"
    fi

    # Classify via iter-161.
    iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules \
        "$iter165_each_type" "$iter165_each_bang_present_boolean"
    iter165_each_bump_label="$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES"
    iter165_each_bump_rationale="$ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN"

    # Update aggregate state.
    iter165_each_rank="${ITER165_BUMP_LABEL_TO_SEMVER_PRECEDENCE_RANK_INTEGER_LOOKUP_TABLE[$iter165_each_bump_label]:-0}"
    if (( iter165_each_rank > ITER165_AGGREGATE_BUMP_RANK_INTEGER_HIGHEST_OBSERVED )); then
        ITER165_AGGREGATE_BUMP_RANK_INTEGER_HIGHEST_OBSERVED="$iter165_each_rank"
        ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW="$iter165_each_bump_label"
        ITER165_TRIGGERING_COMMIT_SHORT_SHA_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY_IF_ALL_NONE="$iter165_each_short_sha"
        ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY="$iter165_each_subject"
    fi
    ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[$iter165_each_bump_label]=$((ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[$iter165_each_bump_label] + 1))

    # Build human-readable line — soft-truncate long subjects to 60 chars.
    if (( ${#iter165_each_subject} > 60 )); then
        iter165_each_subject_for_display="${iter165_each_subject:0:57}..."
    else
        iter165_each_subject_for_display="$iter165_each_subject"
    fi
    # Pad subject to 60 chars for column alignment.
    iter165_each_subject_padded=$(printf '%-60s' "$iter165_each_subject_for_display")

    # Colorize bump label per severity.
    case "$iter165_each_bump_label" in
        MAJOR) iter165_each_bump_color="$ITER165_ANSI_RED" ;;
        MINOR) iter165_each_bump_color="$ITER165_ANSI_GREEN" ;;
        PATCH) iter165_each_bump_color="$ITER165_ANSI_CYAN" ;;
        NONE)  iter165_each_bump_color="$ITER165_ANSI_DIM" ;;
        *)     iter165_each_bump_color="" ;;
    esac
    ITER165_HUMAN_READABLE_PER_COMMIT_BREAKDOWN_LINE_ARRAY+=(
        "  ${iter165_each_short_sha}  ${iter165_each_subject_padded}  → ${iter165_each_bump_color}${iter165_each_bump_label}${ITER165_ANSI_RESET}"
    )

    # Build JSON record — escape subject + rationale via iter-155.
    iter165_each_escaped_subject=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$iter165_each_subject")
    iter165_each_escaped_rationale=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$iter165_each_bump_rationale")
    ITER165_JSON_PER_COMMIT_RECORD_ARRAY+=("    {\"short_sha\": \"${iter165_each_short_sha}\", \"subject\": ${iter165_each_escaped_subject}, \"bump_label\": \"${iter165_each_bump_label}\", \"rationale\": ${iter165_each_escaped_rationale}}")
done

# ─── Step 4: resolve aggregate bump to concrete next-version via iter-164 ────
iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules \
    "$ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST" \
    "$ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW"
ITER165_RESOLVED_NEXT_VERSION_STRING_FROM_ITER164_OR_EMPTY="$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG"
ITER165_RESOLVED_NEXT_VERSION_RATIONALE_FROM_ITER164="$ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION"

# Build aggregate rationale describing why this bump won.
ITER165_AGGREGATE_BUMP_RATIONALE_EXPLAINING_PRECEDENCE_WIN="aggregate ${ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW} (MAJOR=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MAJOR]}, MINOR=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MINOR]}, PATCH=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[PATCH]}, NONE=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[NONE]}) — max precedence per SemVer: MAJOR > MINOR > PATCH > NONE"

# ─── Step 5: render output (human or JSON) ───────────────────────────────────
if [[ "$ITER165_OUTPUT_MODE_HUMAN_OR_JSON" == "json" ]]; then
    ITER165_JSON_CURRENT_TAG_ESCAPED=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST")
    ITER165_JSON_NEXT_VERSION_ESCAPED=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$ITER165_RESOLVED_NEXT_VERSION_STRING_FROM_ITER164_OR_EMPTY")
    ITER165_JSON_NEXT_VERSION_RATIONALE_ESCAPED=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$ITER165_RESOLVED_NEXT_VERSION_RATIONALE_FROM_ITER164")
    ITER165_JSON_AGGREGATE_RATIONALE_ESCAPED=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$ITER165_AGGREGATE_BUMP_RATIONALE_EXPLAINING_PRECEDENCE_WIN")
    ITER165_JSON_TRIGGERING_SUBJECT_ESCAPED=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY")

    # Assemble per-commit records as JSON-array body (comma-separated).
    # Build manually with "first record then comma-prefixed rest" to avoid
    # trailing-comma JSON parse errors (Python's json.loads rejects
    # `[a, b, c,]` even though some lenient parsers accept it).
    ITER165_JSON_PER_COMMIT_RECORDS_JOINED=""
    if (( ${#ITER165_JSON_PER_COMMIT_RECORD_ARRAY[@]} > 0 )); then
        ITER165_JSON_PER_COMMIT_RECORDS_JOINED="${ITER165_JSON_PER_COMMIT_RECORD_ARRAY[0]}"
        for iter165_each_record_idx in "${!ITER165_JSON_PER_COMMIT_RECORD_ARRAY[@]}"; do
            if (( iter165_each_record_idx == 0 )); then continue; fi
            ITER165_JSON_PER_COMMIT_RECORDS_JOINED+=",
${ITER165_JSON_PER_COMMIT_RECORD_ARRAY[$iter165_each_record_idx]}"
        done
    fi

    cat <<EOF
{
  "iter165_schema_version": 1,
  "current_git_tag": ${ITER165_JSON_CURRENT_TAG_ESCAPED},
  "commit_count_since_tag": ${ITER165_TOTAL_COMMIT_COUNT_SINCE_MOST_RECENT_GIT_TAG},
  "per_commit_bump_breakdown": [
${ITER165_JSON_PER_COMMIT_RECORDS_JOINED}
  ],
  "bump_histogram": {
    "MAJOR": ${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MAJOR]},
    "MINOR": ${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MINOR]},
    "PATCH": ${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[PATCH]},
    "NONE": ${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[NONE]}
  },
  "aggregate_bump_label_per_semver_precedence": "${ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW}",
  "aggregate_bump_rationale": ${ITER165_JSON_AGGREGATE_RATIONALE_ESCAPED},
  "triggering_commit_short_sha_at_highest_precedence": "${ITER165_TRIGGERING_COMMIT_SHORT_SHA_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY_IF_ALL_NONE}",
  "triggering_commit_subject_at_highest_precedence": ${ITER165_JSON_TRIGGERING_SUBJECT_ESCAPED},
  "iter164_next_version_preview": {
    "iter164_schema_version": 1,
    "current_git_tag": ${ITER165_JSON_CURRENT_TAG_ESCAPED},
    "next_version": ${ITER165_JSON_NEXT_VERSION_ESCAPED},
    "resolution_rationale": ${ITER165_JSON_NEXT_VERSION_RATIONALE_ESCAPED}
  }
}
EOF
    exit 0
fi

# ─── Human-readable output ───────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ${ITER165_ANSI_BOLD}COMMITS PENDING-RELEASE PREVIEW${ITER165_ANSI_RESET}  (iter-165 aggregate next-release)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
if [[ -n "$ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST" ]]; then
    echo "  current git tag:       ${ITER165_ANSI_CYAN}${ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST}${ITER165_ANSI_RESET}"
else
    echo "  current git tag:       ${ITER165_ANSI_YELLOW}(no tag found in repo)${ITER165_ANSI_RESET}"
fi
echo "  commits since tag:     ${ITER165_TOTAL_COMMIT_COUNT_SINCE_MOST_RECENT_GIT_TAG}"
echo ""

if (( ITER165_TOTAL_COMMIT_COUNT_SINCE_MOST_RECENT_GIT_TAG == 0 )); then
    echo "  ${ITER165_ANSI_DIM}(no pending commits — next release would be skipped by semantic-release)${ITER165_ANSI_RESET}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    exit 0
fi

echo "  per-commit breakdown (oldest → newest):"
for iter165_each_human_line in "${ITER165_HUMAN_READABLE_PER_COMMIT_BREAKDOWN_LINE_ARRAY[@]}"; do
    echo "$iter165_each_human_line"
done
echo ""
echo "  bump histogram:        MAJOR=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MAJOR]}  MINOR=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[MINOR]}  PATCH=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[PATCH]}  NONE=${ITER165_BUMP_LABEL_OCCURRENCE_COUNT_HISTOGRAM_ACROSS_ALL_COMMITS_IN_WINDOW[NONE]}"

case "$ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW" in
    MAJOR) iter165_aggregate_color="$ITER165_ANSI_RED" ;;
    MINOR) iter165_aggregate_color="$ITER165_ANSI_GREEN" ;;
    PATCH) iter165_aggregate_color="$ITER165_ANSI_CYAN" ;;
    NONE)  iter165_aggregate_color="$ITER165_ANSI_DIM" ;;
    *)     iter165_aggregate_color="" ;;
esac
echo "  aggregate bump:        ${iter165_aggregate_color}${ITER165_AGGREGATE_BUMP_LABEL_HIGHEST_PRECEDENCE_OBSERVED_ACROSS_ALL_COMMITS_IN_WINDOW}${ITER165_ANSI_RESET} (max precedence: MAJOR > MINOR > PATCH > NONE)"

if [[ -n "$ITER165_RESOLVED_NEXT_VERSION_STRING_FROM_ITER164_OR_EMPTY" ]]; then
    echo "  next release version:  ${ITER165_ANSI_BOLD}${ITER165_DETECTED_CURRENT_GIT_TAG_FROM_DESCRIBE_OR_EMPTY_WHEN_NO_TAGS_EXIST}${ITER165_ANSI_RESET} → ${ITER165_ANSI_BOLD}${ITER165_ANSI_GREEN}${ITER165_RESOLVED_NEXT_VERSION_STRING_FROM_ITER164_OR_EMPTY}${ITER165_ANSI_RESET}"
else
    echo "  next release version:  ${ITER165_ANSI_DIM}(none — semantic-release will skip)${ITER165_ANSI_RESET}"
fi

if [[ -n "$ITER165_TRIGGERING_COMMIT_SHORT_SHA_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY_IF_ALL_NONE" ]]; then
    if (( ${#ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY} > 60 )); then
        iter165_trigger_subj_display="${ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY:0:57}..."
    else
        iter165_trigger_subj_display="$ITER165_TRIGGERING_COMMIT_SUBJECT_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY"
    fi
    echo "  triggered by:          ${ITER165_TRIGGERING_COMMIT_SHORT_SHA_AT_HIGHEST_PRECEDENCE_BUMP_OR_EMPTY_IF_ALL_NONE} ${iter165_trigger_subj_display}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
