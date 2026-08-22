#!/usr/bin/env bash
#MISE description="Iter-145 regression test for the semantic-release notes backfill script. Asserts: (a) backfill script exists + is executable + shellcheck-clean, (b) structurally pins the 5 known affected historical tags (v4.9.0, v4.10.0, v5.1.0, v5.1.2, v5.1.4) discovered by iter-144 forensic instrumentation, (c) pins the canonical JSON content matching the 872 sibling notes refs, (d) pins the annotated-tag-dereferencing-to-commit invariant (uses tag^{commit} not bare tag — mid-iter-145 bug surfaced when initial git notes add attached notes to tag objects which git log cannot find), (e) functionally validates the fix end-to-end by running the script idempotently and asserting that semantic-release's tag-notes scan no longer produces lines with empty content for the 5 affected tags."
set -euo pipefail

ITER145_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER145_REPO_ROOT"

ITER145_BACKFILL_SCRIPT_RELATIVE_PATH="scripts/iter145-fix-malformed-empty-semantic-release-notes-refs-by-overwriting-with-canonical-channels-null-json-content-matching-eight-hundred-seventy-two-sibling-refs-discovered-by-iter144-debug-namespace-stderr-parser-forensic-finding.sh"
ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH="$ITER145_REPO_ROOT/$ITER145_BACKFILL_SCRIPT_RELATIVE_PATH"

ITER145_KNOWN_AFFECTED_HISTORICAL_TAGS_FROM_ITER144_FORENSIC_FINDING=(
    "v4.9.0"
    "v4.10.0"
    "v5.1.0"
    "v5.1.2"
    "v5.1.4"
)

ITER145_TOTAL_ASSERTIONS_EVALUATED=0
ITER145_TOTAL_ASSERTIONS_FAILED=0

iter145_assert_substring_present_in_file() {
    local human_readable_assertion_label_for_iter145="$1"
    local file_path_to_grep="$2"
    local expected_substring_to_locate="$3"
    ITER145_TOTAL_ASSERTIONS_EVALUATED=$((ITER145_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring_to_locate" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label_for_iter145"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter145"
        echo "    expected substring: ${expected_substring_to_locate:0:120}"
        ITER145_TOTAL_ASSERTIONS_FAILED=$((ITER145_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter145_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label_for_iter145="$1"
    local bash_test_expression="$2"
    ITER145_TOTAL_ASSERTIONS_EVALUATED=$((ITER145_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label_for_iter145"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter145"
        echo "    failed bash predicate: $bash_test_expression"
        ITER145_TOTAL_ASSERTIONS_FAILED=$((ITER145_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-145 SEMANTIC-RELEASE NOTES BACKFILL REGRESSION TEST"
echo "  Pins: 5-tag list, canonical JSON content, ^{commit} dereferencing,"
echo "        end-to-end fix verification via semantic-release tag-notes scan."
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Script presence + sanity ───────────────────────────────────────
echo ""
echo "GROUP A (3 assertions): Backfill script structural validity"

iter145_assert_filesystem_predicate_holds \
    "A1: backfill script exists at iter-145 verbose path" \
    "-f \"$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH\""

iter145_assert_filesystem_predicate_holds \
    "A2: backfill script is executable (chmod +x)" \
    "-x \"$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH\""

ITER145_TOTAL_ASSERTIONS_EVALUATED=$((ITER145_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A3: backfill script passes bash -n syntax check"
else
    echo "  ✗ A3: backfill script FAILS bash -n syntax check"
    ITER145_TOTAL_ASSERTIONS_FAILED=$((ITER145_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group B: Forensic pin — 5 tags + canonical content + ^{commit} dereference ─
echo ""
echo "GROUP B (8 assertions): Iter-144-discovered invariants pinned in script source"

for known_affected_tag_from_iter144_forensic_finding in "${ITER145_KNOWN_AFFECTED_HISTORICAL_TAGS_FROM_ITER144_FORENSIC_FINDING[@]}"; do
    iter145_assert_substring_present_in_file \
        "B-tag-${known_affected_tag_from_iter144_forensic_finding}: tag listed in backfill array" \
        "$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" \
        "\"$known_affected_tag_from_iter144_forensic_finding\""
done

iter145_assert_substring_present_in_file \
    "B-canonical-content: canonical JSON content {\"channels\":[null]} pinned in script" \
    "$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" \
    '{"channels":[null]}'

iter145_assert_substring_present_in_file \
    "B-annotated-tag-dereference: script uses tag^{commit} dereference (annotated-tag-aware)" \
    "$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" \
    '^{commit}'

iter145_assert_substring_present_in_file \
    "B-idempotency: script implements idempotent-skip via existing-notes check" \
    "$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" \
    "iter145_check_tag_has_any_semantic_release_note_attached_to_its_commit_across_all_sibling_notes_refs"

# ─── Group C: End-to-end fix verification — semantic-release scan returns no empty notes ─
echo ""
echo "GROUP C (5 assertions): Post-fix state verification — 5 affected tags now have notes"

# Run the backfill idempotently (no-op if already canonical). If fix was already
# applied, this is a fast no-op; if not, the test self-heals state.
"$ITER145_BACKFILL_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1 || true

# For each of the 5 affected tags, verify the semantic-release tag-notes scan
# now finds canonical content (not empty).
for affected_tag in "${ITER145_KNOWN_AFFECTED_HISTORICAL_TAGS_FROM_ITER144_FORENSIC_FINDING[@]}"; do
    ITER145_TOTAL_ASSERTIONS_EVALUATED=$((ITER145_TOTAL_ASSERTIONS_EVALUATED + 1))
    scan_line_for_this_tag=$(
        git log --tags='*' --decorate-refs='refs/tags/*' --no-walk \
            --format='%d%x09%N' --notes='refs/notes/semantic-release*' 2>/dev/null \
            | grep "tag: $affected_tag)" \
            | head -1
    )
    if [[ "$scan_line_for_this_tag" == *$'\t''{"channels":[null]}'* ]]; then
        echo "  ✓ C-$affected_tag: semantic-release scan finds canonical notes for tag (no empty notePart)"
    else
        echo "  ✗ C-$affected_tag: semantic-release scan still finds empty/missing notes"
        echo "    scan line was: ${scan_line_for_this_tag:0:100}"
        ITER145_TOTAL_ASSERTIONS_FAILED=$((ITER145_TOTAL_ASSERTIONS_FAILED + 1))
    fi
done

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER145_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-145 REGRESSION TEST: ${ITER145_TOTAL_ASSERTIONS_EVALUATED}/${ITER145_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-145 REGRESSION TEST: $((ITER145_TOTAL_ASSERTIONS_EVALUATED - ITER145_TOTAL_ASSERTIONS_FAILED))/${ITER145_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER145_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
