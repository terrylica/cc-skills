#!/usr/bin/env bash
# Iter-164 SemVer next-version resolver shared library.
#
# WHY THIS EXISTS:
#
#   Iter-161 surfaced the semver-bump LABEL (MAJOR/MINOR/PATCH/NONE)
#   the iter-153 advisor will trigger, but stopped one step short of
#   the operator's actual question: "what version number will land?"
#   The advisor user has to mentally compute current-version-plus-bump
#   = next-version. For a fast pre-commit-time answer, computing this
#   locally is much cheaper than invoking `semantic-release --dry-run`,
#   which per the 2026 semantic-release FAQ verifies push permissions,
#   requires fetch-depth=0 git history, and takes multiple seconds.
#
#   Iter-164 closes this gap with a pure-bash resolver: take the bump
#   label from iter-161, parse the current MAJOR.MINOR.PATCH from the
#   most recent git tag, apply the semver.org §2 increment rules, and
#   emit the concrete next-version string. The advisor then renders it
#   inline alongside the iter-161 preview, e.g.:
#
#     iter-161 semver-bump preview:
#       + MINOR bump — new feature release
#       next version: v21.71.0 → v21.72.0   ← iter-164 adds this line
#
# DESIGN INVARIANTS:
#
#   - Pure-bash, no external dependencies. Source-able shared lib
#     mirroring iter-155 / iter-161 / iter-162 pattern.
#
#   - semver.org §2 strict increment rules (https://semver.org/):
#       MAJOR (X.Y.Z → X+1.0.0): increment X, RESET Y and Z to 0
#       MINOR (X.Y.Z → X.Y+1.0): increment Y, RESET Z to 0
#       PATCH (X.Y.Z → X.Y.Z+1): increment Z only
#       NONE → no version change (output empty, semantic-release skips)
#
#   - Tag-prefix convention preservation: if input tag starts with
#     "v" (e.g. v21.71.0), the output preserves that prefix
#     (v21.72.0). If input has no prefix (e.g. 21.71.0), output has
#     none. This matches the existing cc-skills release pipeline's
#     "v"-prefix convention and avoids breaking downstream consumers.
#
#   - Pre-release suffix handling: per semver.org §11, a pre-release
#     version like v21.71.0-rc.1 has LOWER precedence than v21.71.0.
#     For the purposes of pre-commit preview, we strip the pre-release
#     suffix and compute against the base version — which matches
#     semantic-release's default behavior of computing the next stable
#     version from the highest stable base.
#
#   - Build-metadata suffix per semver.org §10 (e.g. v21.71.0+sha.123)
#     is stripped and ignored — semver §10 explicitly says build
#     metadata "MUST be ignored when determining version precedence".
#
# USAGE:
#
#   source scripts/lib/iter164-...sh
#   iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules \
#       "v21.71.0" "MINOR"
#   echo "$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG"
#   # → v21.72.0
#
# PRIOR ART:
#
#   - https://semver.org/ — canonical SemVer 2.0.0 specification
#   - https://semantic-release.gitbook.io/semantic-release/support/faq
#     — `--dry-run` is the industry-standard way to preview next
#     version, but heavy (push-perm verify, full git history,
#     multi-second runtime). iter-164 is the local-first
#     pure-bash alternative for pre-commit advisory use.

# Output globals — consumed by sourcing caller after function invocation.
# SC2034 suppression mirrors iter-161/iter-162 (lint cannot trace cross-
# file reads of sourced-library globals).
# shellcheck disable=SC2034
ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG=""
# shellcheck disable=SC2034
ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION=""

# Sentinel signaling successful library load (mirrors iter-155/161/162 pattern).
export ITER164_SEMVER_NEXT_VERSION_RESOLVER_LIBRARY_LOADED_SENTINEL=1

iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules() {
    local current_git_tag_or_version_string_possibly_with_v_prefix_or_prerelease_suffix="$1"
    local iter161_bump_label_major_minor_patch_or_none="$2"

    # Reset output globals on each invocation.
    ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG=""
    ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION=""

    # ─── NONE bump: no version change (semantic-release will skip) ───────────
    if [[ "$iter161_bump_label_major_minor_patch_or_none" == "NONE" ]]; then
        ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION="bump=NONE → no version change (semantic-release will skip this commit)"
        return 0
    fi

    # ─── Empty / missing current tag: cannot compute ─────────────────────────
    if [[ -z "$current_git_tag_or_version_string_possibly_with_v_prefix_or_prerelease_suffix" ]]; then
        ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION="current version unknown (no git tag found) — cannot compute concrete next version"
        return 0
    fi

    # ─── Strip optional "v" prefix and pre-release/build-metadata suffix ─────
    # Preserve whether the input had "v" prefix so the output matches
    # the operator's existing tag convention.
    local v_prefix_was_present_in_input_tag_boolean_for_output_format_preservation="false"
    local current_tag_with_v_prefix_stripped_for_parsing="$current_git_tag_or_version_string_possibly_with_v_prefix_or_prerelease_suffix"
    if [[ "$current_tag_with_v_prefix_stripped_for_parsing" =~ ^v ]]; then
        v_prefix_was_present_in_input_tag_boolean_for_output_format_preservation="true"
        current_tag_with_v_prefix_stripped_for_parsing="${current_tag_with_v_prefix_stripped_for_parsing#v}"
    fi
    # Strip pre-release suffix (semver §11) — everything from first "-".
    current_tag_with_v_prefix_stripped_for_parsing="${current_tag_with_v_prefix_stripped_for_parsing%%-*}"
    # Strip build-metadata suffix (semver §10) — everything from first "+".
    current_tag_with_v_prefix_stripped_for_parsing="${current_tag_with_v_prefix_stripped_for_parsing%%+*}"

    # ─── Parse MAJOR.MINOR.PATCH components (must be three integers) ─────────
    local parsed_semver_major_component_integer parsed_semver_minor_component_integer parsed_semver_patch_component_integer
    if [[ ! "$current_tag_with_v_prefix_stripped_for_parsing" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION="current tag '${current_git_tag_or_version_string_possibly_with_v_prefix_or_prerelease_suffix}' is not a parseable SemVer MAJOR.MINOR.PATCH string — cannot compute next"
        return 0
    fi
    parsed_semver_major_component_integer="${BASH_REMATCH[1]}"
    parsed_semver_minor_component_integer="${BASH_REMATCH[2]}"
    parsed_semver_patch_component_integer="${BASH_REMATCH[3]}"

    # ─── Apply semver.org §2 increment rules per bump label ──────────────────
    local resolved_next_major_component_integer="$parsed_semver_major_component_integer"
    local resolved_next_minor_component_integer="$parsed_semver_minor_component_integer"
    local resolved_next_patch_component_integer="$parsed_semver_patch_component_integer"
    case "$iter161_bump_label_major_minor_patch_or_none" in
        MAJOR)
            resolved_next_major_component_integer=$((parsed_semver_major_component_integer + 1))
            resolved_next_minor_component_integer=0
            resolved_next_patch_component_integer=0
            ;;
        MINOR)
            resolved_next_minor_component_integer=$((parsed_semver_minor_component_integer + 1))
            resolved_next_patch_component_integer=0
            ;;
        PATCH)
            resolved_next_patch_component_integer=$((parsed_semver_patch_component_integer + 1))
            ;;
        *)
            ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION="unknown bump label '${iter161_bump_label_major_minor_patch_or_none}' — must be MAJOR, MINOR, PATCH, or NONE"
            return 0
            ;;
    esac

    # ─── Assemble next-version string preserving operator's tag prefix ──────
    local assembled_next_semver_version_string_with_optional_v_prefix_matching_input_convention="${resolved_next_major_component_integer}.${resolved_next_minor_component_integer}.${resolved_next_patch_component_integer}"
    if [[ "$v_prefix_was_present_in_input_tag_boolean_for_output_format_preservation" == "true" ]]; then
        assembled_next_semver_version_string_with_optional_v_prefix_matching_input_convention="v${assembled_next_semver_version_string_with_optional_v_prefix_matching_input_convention}"
    fi

    ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG="$assembled_next_semver_version_string_with_optional_v_prefix_matching_input_convention"
    ITER164_NEXT_VERSION_RESOLUTION_RATIONALE_FOR_HUMAN_READABLE_DISPLAY_EXPLAINING_INPUT_TAG_AND_BUMP_APPLICATION="${current_git_tag_or_version_string_possibly_with_v_prefix_or_prerelease_suffix} + ${iter161_bump_label_major_minor_patch_or_none} bump → ${assembled_next_semver_version_string_with_optional_v_prefix_matching_input_convention} per semver.org §2"
}
