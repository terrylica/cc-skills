#!/usr/bin/env bash
# iter-145: backfill canonical `{"channels":[null]}` semantic-release notes for
# the 5 historical tags (v4.9.0, v4.10.0, v5.1.0, v5.1.2, v5.1.4) that
# semantic-release's getTagsNotes scan finds with EMPTY notes content,
# producing 5 silent JSON.parse SyntaxError stack traces per release run
# (forensic finding surfaced by iter-144 debug-namespace stderr parser).
#
# Background (iter-144 forensic discovery + iter-145 root-cause analysis):
#
#   semantic-release scans all tags + all `refs/notes/semantic-release*` notes
#   refs by running:
#
#       git log --tags='*' --decorate-refs='refs/tags/*' --no-walk \
#               --format='%d%x09%N' --notes='refs/notes/semantic-release*'
#
#   For each tag, %d emits `(tag: vX.Y.Z)` and %N emits the note content
#   (empty string if no note exists for that commit). The output is then
#   processed by:
#
#       const [tagPart, notePart] = line.trim().split("\t");
#       const parsed = JSON.parse(notePart);  // FAILURE POINT
#
#   When a tag has NO note attached to its commit across any of the 877
#   sibling refs, the line has format `(tag: vX.Y.Z)\t` (tab present, empty
#   content). `line.trim()` strips the trailing tab. Splitting on '\t' then
#   yields a single-element array, destructuring assigns `notePart = undefined`,
#   and `JSON.parse(undefined)` is coerced to `JSON.parse("undefined")` →
#   throws `SyntaxError: "undefined" is not valid JSON`.
#
#   The catch block at semantic-release/lib/git.js:346 swallows the error via
#   `debug(error)` but the stack-trace generation cost is non-zero and the
#   error is pure forensic noise — these tags simply weren't notes-annotated
#   by a historical release.
#
# Fix:
#   For each of the 5 affected tags, ADD a canonical note via:
#
#       git notes --ref=refs/notes/semantic-release-<tag> add \
#                 -m '{"channels":[null]}' <tag>
#
#   This creates `refs/notes/semantic-release-vX.Y.Z` with content
#   `{"channels":[null]}` attached to the tag's commit, matching the
#   structure of all 877 existing sibling notes refs.
#
# Why `{"channels":[null]}`:
#   - All existing sibling notes refs carry exactly this content (verified by
#     `git show refs/notes/semantic-release-v21.58.4` etc.).
#   - The `null` in `channels` is semantic-release's encoding for
#     "default-channel-only release" (i.e., released to main with no
#     pre-release modifier).
#   - The 5 affected tags (v4.x, v5.1.x — old historical releases from
#     before semantic-release was fully wired up in this repo) were all
#     default-channel releases when originally cut.
#
# Idempotency:
#   - Detection logic: does `git log vX.Y.Z -1 --notes=refs/notes/
#     semantic-release* --format=%N` return non-empty content? If yes,
#     skip — the tag already has notes somewhere. If no, ADD.
#   - Re-running this script is safe; affected tags will already have notes
#     on the second run and will be skipped.
#
# Scope (local-only — does NOT push to remote):
#   - cc-skills's `.releaserc.yml` uses @semantic-release/git with explicit
#     asset list; notes refs are NOT pushed by semantic-release in this
#     configuration. The fix is per-developer; remote unaffected.
#   - To propagate the fix to other developers' clones: they re-run this
#     script. (Future iter could add notes-ref push — out of scope here.)
#
# Verification post-fix:
#   - The iter-144 parser, re-run against a fresh
#     `DEBUG=semantic-release:* npx semantic-release --dry-run` capture,
#     reports 0 silent JSON.parse SyntaxError stack traces.

set -euo pipefail

ITER145_KNOWN_TAGS_WITHOUT_SEMANTIC_RELEASE_NOTES_CAUSING_SILENT_JSON_PARSE_SYNTAX_ERROR_PER_ITER144_FORENSIC_DISCOVERY=(
    "v4.9.0"
    "v4.10.0"
    "v5.1.0"
    "v5.1.2"
    "v5.1.4"
)

ITER145_CANONICAL_SEMANTIC_RELEASE_NOTE_JSON_CONTENT_FOR_DEFAULT_CHANNEL_ONLY_RELEASES_MATCHING_872_SIBLING_REFS='{"channels":[null]}'

ITER145_TOTAL_NOTES_BACKFILLED_DURING_THIS_RUN=0
ITER145_TOTAL_TAGS_ALREADY_HAVE_NOTES_AND_SKIPPED_DURING_THIS_RUN=0
ITER145_TOTAL_TAGS_NOT_PRESENT_LOCALLY_DURING_THIS_RUN=0

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-145 SEMANTIC-RELEASE NOTES BACKFILL FOR 5 HISTORICAL TAGS"
echo "  Targeting tags discovered by iter-144 forensic finding to lack notes."
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

iter145_check_tag_has_any_semantic_release_note_attached_to_its_commit_across_all_sibling_notes_refs() {
    local tag_name_to_probe_for_existing_notes="$1"
    # `%N` with `--notes=refs/notes/semantic-release*` returns any note from
    # ANY sibling notes ref attached to the tag's target commit. Empty stdout
    # means no notes anywhere — the trigger for our backfill.
    local existing_notes_content_for_tag
    existing_notes_content_for_tag=$(
        git log "$tag_name_to_probe_for_existing_notes" -1 \
            --notes='refs/notes/semantic-release*' \
            --format='%N' 2>/dev/null \
            | tr -d '[:space:]' \
            || true
    )
    [[ -n "$existing_notes_content_for_tag" ]]
}

iter145_backfill_one_tag_with_canonical_note_if_currently_unattached_otherwise_skip() {
    local tag_name_to_backfill_canonical_note_for="$1"
    local target_notes_ref_full_path_for_this_specific_tag="refs/notes/semantic-release-$tag_name_to_backfill_canonical_note_for"

    # Sanity: tag must exist locally.
    if ! git rev-parse --verify --quiet "refs/tags/$tag_name_to_backfill_canonical_note_for" >/dev/null 2>&1; then
        echo "  ⊘ $tag_name_to_backfill_canonical_note_for: tag not present locally — skipping (cannot backfill notes for absent tag)"
        ITER145_TOTAL_TAGS_NOT_PRESENT_LOCALLY_DURING_THIS_RUN=$((ITER145_TOTAL_TAGS_NOT_PRESENT_LOCALLY_DURING_THIS_RUN + 1))
        return 0
    fi

    # Idempotent check: tag may already have notes from previous run.
    if iter145_check_tag_has_any_semantic_release_note_attached_to_its_commit_across_all_sibling_notes_refs "$tag_name_to_backfill_canonical_note_for"; then
        echo "  = $tag_name_to_backfill_canonical_note_for: already has semantic-release notes attached — skipping (idempotent)"
        ITER145_TOTAL_TAGS_ALREADY_HAVE_NOTES_AND_SKIPPED_DURING_THIS_RUN=$((ITER145_TOTAL_TAGS_ALREADY_HAVE_NOTES_AND_SKIPPED_DURING_THIS_RUN + 1))
        return 0
    fi

    # Backfill: create the canonical note for this tag.
    # CRITICAL: target the tag's COMMIT (`tag^{commit}` dereference), NOT the
    # tag object itself. Annotated tags (`git cat-file -t vX.Y.Z` returns
    # `tag`) resolve to a tag-object SHA, not a commit SHA. `git notes add
    # vX.Y.Z` would attach the note to the tag object, where `git log`
    # cannot find it (it walks commits, not tag objects). Lightweight tags
    # would work either way, but annotated tags (v4.9.0/v4.10.0/v5.1.x in
    # cc-skills history) require explicit `^{commit}` dereference. Iter-145
    # mid-development bug surfaced + fixed.
    local commit_sha_target_for_note_attachment_after_annotated_tag_dereferencing
    commit_sha_target_for_note_attachment_after_annotated_tag_dereferencing=$(
        git rev-parse "${tag_name_to_backfill_canonical_note_for}^{commit}"
    )
    echo "  → $tag_name_to_backfill_canonical_note_for: backfilling canonical note ($ITER145_CANONICAL_SEMANTIC_RELEASE_NOTE_JSON_CONTENT_FOR_DEFAULT_CHANNEL_ONLY_RELEASES_MATCHING_872_SIBLING_REFS) on commit $commit_sha_target_for_note_attachment_after_annotated_tag_dereferencing"
    git notes \
        --ref="$target_notes_ref_full_path_for_this_specific_tag" \
        add \
        -m "$ITER145_CANONICAL_SEMANTIC_RELEASE_NOTE_JSON_CONTENT_FOR_DEFAULT_CHANNEL_ONLY_RELEASES_MATCHING_872_SIBLING_REFS" \
        "$commit_sha_target_for_note_attachment_after_annotated_tag_dereferencing" \
        >/dev/null 2>&1

    # Verify the backfill landed.
    if iter145_check_tag_has_any_semantic_release_note_attached_to_its_commit_across_all_sibling_notes_refs "$tag_name_to_backfill_canonical_note_for"; then
        echo "    ✓ verified: $tag_name_to_backfill_canonical_note_for now has canonical notes attached"
        ITER145_TOTAL_NOTES_BACKFILLED_DURING_THIS_RUN=$((ITER145_TOTAL_NOTES_BACKFILLED_DURING_THIS_RUN + 1))
    else
        echo "    ✗ $tag_name_to_backfill_canonical_note_for: post-backfill verification FAILED — notes still not detected"
        return 1
    fi
}

for tag_to_backfill_canonical_note_for in "${ITER145_KNOWN_TAGS_WITHOUT_SEMANTIC_RELEASE_NOTES_CAUSING_SILENT_JSON_PARSE_SYNTAX_ERROR_PER_ITER144_FORENSIC_DISCOVERY[@]}"; do
    iter145_backfill_one_tag_with_canonical_note_if_currently_unattached_otherwise_skip "$tag_to_backfill_canonical_note_for"
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-145 BACKFILL SUMMARY"
echo "    Tags backfilled this run:           $ITER145_TOTAL_NOTES_BACKFILLED_DURING_THIS_RUN"
echo "    Tags already had notes (skipped):   $ITER145_TOTAL_TAGS_ALREADY_HAVE_NOTES_AND_SKIPPED_DURING_THIS_RUN"
echo "    Tags not present locally (no-op):   $ITER145_TOTAL_TAGS_NOT_PRESENT_LOCALLY_DURING_THIS_RUN"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Verify the fix by re-running iter-144 parser against a fresh capture:"
echo ""
echo "    DEBUG=semantic-release:* npx semantic-release --dry-run --no-ci 2> /tmp/post-iter145.log"
echo "    python3 scripts/iter144-...py /tmp/post-iter145.log | grep 'silent JSON.parse'"
echo ""
echo "  Expected post-fix forensic count: 0 silent JSON.parse SyntaxError stack traces."
echo ""
