#!/usr/bin/env bash
# Iter-161 semantic-release version-bump classifier shared library.
#
# WHY THIS EXISTS:
#
#   The iter-153 advisor classifies a proposed conventional-commit
#   subject through the iter-82 grammar (STANDARD-CONFORMANT vs
#   COMPOUND-PREFIX vs MISSING-TYPE), tells the operator about
#   readability via the iter-150 50/72 rule, and (in --strict mode)
#   blocks silent-fail-class commits. But it never tells the operator
#   the most consequential downstream effect:
#
#     "What version bump will semantic-release actually apply if I
#      land this commit?"
#
#   Operators routinely use the wrong type ("chore" for a feature,
#   "feat" for a docs-only edit) and ship unintended bumps. The
#   conventional-commits-ecosystem audit (commitlint / commitizen /
#   conventional-pre-commit) confirms NO mainstream advisor surfaces
#   this — they all stop at grammar conformance.
#
#   Iter-161 closes the preview gap by mapping the iter-153-extracted
#   {type, breaking_change_marker} pair to the actual MAJOR/MINOR/PATCH
#   bump cc-skills' .releaserc.yml will apply.
#
# DESIGN INVARIANTS:
#
#   - Bump rules are encoded as a static lookup mirroring cc-skills
#     .releaserc.yml (see top of repo). If .releaserc.yml ever changes
#     the bump table, update this file accordingly — it is the SSoT
#     for "what will semantic-release do?" answered from the advisor's
#     pre-commit perspective.
#
#   - The bump label is one of four canonical values per semver.org:
#       MAJOR  → ! breaking-change marker on any recognized type
#       MINOR  → feat without ! marker
#       PATCH  → fix, perf, revert, docs, chore, style, refactor,
#                test, build, ci (per cc-skills patch-everything
#                marketplace policy in .releaserc.yml releaseRules)
#       NONE   → unrecognized type or silent-fail-class (semantic-
#                release will skip this commit entirely)
#
#   - Pure-bash, no external dependencies. Sourceable by any
#     consumer. Output goes to two global variables for caller pickup:
#
#       ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES
#       ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN
#
#     (Global-output design mirrors iter-160's helper-globals refactor
#     after SC2154 — namespace-parameterized eval is harder for the
#     static-analysis linter to verify than explicit globals.)
#
# USAGE:
#
#   source scripts/lib/iter161-...sh
#   iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules \
#       "feat" "false"
#   echo "$ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES"
#   # → MINOR
#
# PRIOR ART:
#
#   - https://semver.org/ — canonical semantic versioning spec
#   - https://github.com/semantic-release/commit-analyzer — default
#     bump rules (feat=MINOR, fix=PATCH, perf=PATCH, revert=PATCH)
#   - cc-skills .releaserc.yml — releaseRules override patching
#     docs/chore/style/refactor/test/build/ci/revert as PATCH (the
#     marketplace-plugin "every change ships" policy)

# Module-load guard: this lib only DEFINES the classifier function and
# zero-initializes the output globals. Callers SOURCE it then invoke.
# No side effects at source-time.
#
# SC2034 suppression: the two output globals below are written by the
# classifier function and READ by the SOURCING caller (iter-153 advisor,
# future consumers). shellcheck cannot trace cross-file reads of
# sourced-library globals — the suppression is the standard idiom for
# shared-lib output variables, mirroring iter-155's sentinel pattern.
# shellcheck disable=SC2034
ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES=""
# shellcheck disable=SC2034
ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN=""

# Sentinel signaling successful library load, mirroring iter-155 pattern.
# Consumer scripts may check this before assuming the function exists.
export ITER161_SEMANTIC_RELEASE_VERSION_BUMP_CLASSIFIER_LIBRARY_LOADED_SENTINEL=1

# The set of conventional-commit types cc-skills .releaserc.yml maps to
# PATCH releases (default sem-rel set + cc-skills' override expanding
# the default no-release types to PATCH for marketplace-plugin policy).
# Kept here as a single-source-of-truth list to avoid scattering the
# rule encoding across the consumer scripts.
ITER161_CC_SKILLS_RELEASERC_PATCH_TRIGGERING_CONVENTIONAL_COMMIT_TYPES_ARRAY=(
    fix
    perf
    revert
    docs
    chore
    style
    refactor
    test
    build
    ci
)

iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules() {
    local extracted_conventional_commit_type="$1"
    local breaking_change_marker_present_boolean="$2"

    # Reset output globals on each invocation to avoid stale carry-over
    # from prior calls in the same shell session.
    ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES=""
    ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN=""

    # ─── Empty-type branch: silent-fail class (MISSING-TYPE, COMPOUND-PREFIX) ──
    if [[ -z "$extracted_conventional_commit_type" ]]; then
        ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES="NONE"
        ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="no conventional-commits type extracted — semantic-release will skip this commit entirely (silent-fail class: no release tagged)"
        return 0
    fi

    # ─── Breaking-change branch: ! marker forces MAJOR regardless of type ─────
    # Per https://www.conventionalcommits.org/en/v1.0.0/ §10 — the ! after
    # the type/scope (e.g. `feat!:` or `refactor(api)!:`) signals a
    # breaking change and triggers MAJOR. semantic-release/commit-analyzer
    # honors this for any recognized type.
    if [[ "$breaking_change_marker_present_boolean" == "true" ]]; then
        ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES="MAJOR"
        ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="! breaking-change marker present on type '${extracted_conventional_commit_type}' → MAJOR bump per conventional-commits §10 (overrides any type-based default)"
        return 0
    fi

    # ─── feat branch: MINOR per semantic-release default ──────────────────────
    if [[ "$extracted_conventional_commit_type" == "feat" ]]; then
        ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES="MINOR"
        ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="feat without ! marker → MINOR bump per semantic-release/commit-analyzer default rules"
        return 0
    fi

    # ─── PATCH-triggering type branch ─────────────────────────────────────────
    # Includes both sem-rel defaults (fix, perf, revert) AND cc-skills'
    # marketplace-plugin policy expansion (docs, chore, style, refactor,
    # test, build, ci) per .releaserc.yml releaseRules.
    local iter161_each_patch_triggering_type_candidate
    for iter161_each_patch_triggering_type_candidate in "${ITER161_CC_SKILLS_RELEASERC_PATCH_TRIGGERING_CONVENTIONAL_COMMIT_TYPES_ARRAY[@]}"; do
        if [[ "$extracted_conventional_commit_type" == "$iter161_each_patch_triggering_type_candidate" ]]; then
            ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES="PATCH"
            case "$extracted_conventional_commit_type" in
                fix|perf|revert)
                    ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="${extracted_conventional_commit_type} → PATCH bump per semantic-release/commit-analyzer default rules"
                    ;;
                *)
                    ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="${extracted_conventional_commit_type} → PATCH bump per cc-skills .releaserc.yml override (marketplace-plugin every-change-ships policy)"
                    ;;
            esac
            return 0
        fi
    done

    # ─── Unrecognized type branch: NONE ───────────────────────────────────────
    # Type extracted but not in cc-skills' release rule set (e.g. a typo
    # like "feet:" or "docs2:"). semantic-release will not match any
    # rule and will skip the commit.
    ITER161_CLASSIFIED_SEMVER_BUMP_LABEL_PER_RELEASERC_YML_BUMP_RULES="NONE"
    ITER161_CLASSIFIED_BUMP_RATIONALE_HUMAN_READABLE_EXPLAINING_WHY_THIS_BUMP_LABEL_WAS_CHOSEN="type '${extracted_conventional_commit_type}' not in cc-skills release rule set (.releaserc.yml releaseRules) — semantic-release will skip this commit (no version bump)"
}
