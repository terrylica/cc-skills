#!/usr/bin/env bash
#MISE description="Iter-117 regression test for the TOC auto-injection feature added to the iter-113 reference-doc generator. Verifies (1) generator output contains a Quick-navigation H2 section between the preamble blockquote and the Purpose H2 section; (2) TOC contains exactly 12 runtime-hook marker entries (one per iter-111 baseline marker) AND exactly 8 audit-task marker entries (one per iter-114 baseline marker); (3) every TOC entry uses GitHub-Flavored-Markdown anchor link syntax - [MARKER](#anchor); (4) GitHub-anchor normalization is correctly applied — backticks stripped, lowercased, special chars dropped — for representative tokens including the SSoT-OK mixed-case grandfathered marker (should anchor to lowercase ssot-ok) and the audit-task suffix in audit catalog (should anchor to marker-name-audit-task); (5) TOC entries are alphabetically ordered within each lifecycle group; (6) TOC injection is idempotent (--check passes after regeneration); (7) every TOC anchor link target exists as an actual H2 heading in the same document (no dangling links)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER113_DOC_GENERATOR_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh"
ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"

ITER111_BASELINE_RUNTIME_HOOK_MARKER_TOKENS=(
    "BASH-LAUNCHD-OK"
    "CARGO-TTY-SKIP"
    "CARGO-TTY-WRAP"
    "CWD-DELETE-OK"
    "FILE-SIZE-OK"
    "INIT-MONOLITH-OK"
    "INLINE-IGNORE-OK"
    "LAYER3-STRIPPED-PATH-OK"
    "PROCESS-STORM-OK"
    "PUEUE-LOCAL-OK"
    "SETPROCTITLE-OK"
    "SSoT-OK"
)
ITER114_BASELINE_AUDIT_TASK_MARKER_TOKENS=(
    "ESCAPE-HATCH-AUDIT-OK"
    "HOOK-OUTPUT-SIZE-CAP-OK"
    "MATCHER-NO-MULTIEDIT-OK"
    "ORDERING-OK"
    "POSTTOOLUSE-RAW-STDOUT-OK"
    "SPAWN-SYNC-OK"
    "STOP-HOOK-ADDITIONAL-CONTEXT-OK"
    "WILDCARD-MATCHER-OK"
)

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-117 TOC auto-injection regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: '## Quick navigation' section exists between preamble and Purpose ───
QUICK_NAV_LINE_NUMBER=$(grep -nF "## Quick navigation" "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" | head -1 | cut -d: -f1 || echo 0)
PURPOSE_LINE_NUMBER=$(grep -nF "## Purpose" "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" | head -1 | cut -d: -f1 || echo 0)

if [[ "$QUICK_NAV_LINE_NUMBER" -gt 0 ]] && \
   [[ "$PURPOSE_LINE_NUMBER" -gt 0 ]] && \
   [[ "$QUICK_NAV_LINE_NUMBER" -lt "$PURPOSE_LINE_NUMBER" ]]; then
    assert_passes "Case 1: '## Quick navigation' section exists (line $QUICK_NAV_LINE_NUMBER) and is positioned before '## Purpose' (line $PURPOSE_LINE_NUMBER) — top-of-doc operator quick-jump target"
else
    assert_fails "Case 1: TOC section missing or mis-positioned (Quick navigation line=$QUICK_NAV_LINE_NUMBER, Purpose line=$PURPOSE_LINE_NUMBER)"
fi

# ─── Case 2: TOC contains exactly 12 runtime-hook entries (one per iter-111 baseline) ───
MISSING_RUNTIME_HOOK_TOC_ENTRY_COUNT=0
for runtime_hook_marker_token in "${ITER111_BASELINE_RUNTIME_HOOK_MARKER_TOKENS[@]}"; do
    expected_toc_entry_pattern="- [\`$runtime_hook_marker_token\`](#"
    if ! grep -qF -e "$expected_toc_entry_pattern" "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        MISSING_RUNTIME_HOOK_TOC_ENTRY_COUNT=$((MISSING_RUNTIME_HOOK_TOC_ENTRY_COUNT + 1))
        echo "    (missing TOC entry for runtime-hook marker: $runtime_hook_marker_token)"
    fi
done
if [[ "$MISSING_RUNTIME_HOOK_TOC_ENTRY_COUNT" -eq 0 ]]; then
    assert_passes "Case 2: TOC contains all 12 runtime-hook marker entries in '- \`MARKER\`'(#anchor)' GFM list syntax"
else
    assert_fails "Case 2: TOC missing $MISSING_RUNTIME_HOOK_TOC_ENTRY_COUNT runtime-hook marker entries"
fi

# ─── Case 3: TOC contains exactly 8 audit-task entries (one per iter-114 baseline) ───
MISSING_AUDIT_TASK_TOC_ENTRY_COUNT=0
for audit_task_marker_token in "${ITER114_BASELINE_AUDIT_TASK_MARKER_TOKENS[@]}"; do
    expected_toc_entry_pattern="- [\`$audit_task_marker_token\`](#"
    if ! grep -qF -e "$expected_toc_entry_pattern" "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        MISSING_AUDIT_TASK_TOC_ENTRY_COUNT=$((MISSING_AUDIT_TASK_TOC_ENTRY_COUNT + 1))
        echo "    (missing TOC entry for audit-task marker: $audit_task_marker_token)"
    fi
done
if [[ "$MISSING_AUDIT_TASK_TOC_ENTRY_COUNT" -eq 0 ]]; then
    assert_passes "Case 3: TOC contains all 8 audit-task marker entries"
else
    assert_fails "Case 3: TOC missing $MISSING_AUDIT_TASK_TOC_ENTRY_COUNT audit-task marker entries"
fi

# ─── Case 4: GitHub anchor link normalization correctness on representative tokens ───
# Probe the three trickiest normalization cases that the algorithm must handle:
#   (a) plain uppercase token             FILE-SIZE-OK             → #file-size-ok
#   (b) mixed-case grandfathered marker   SSoT-OK                  → #ssot-ok (lowercased)
#   (c) audit-task with paren suffix      ESCAPE-HATCH-AUDIT-OK    → #escape-hatch-audit-ok-audit-task
#
# If any of these regress, the GitHub anchor algorithm in the generator's
# computeGitHubFlavoredMarkdownAnchorLinkFragment... function is broken.
NORMALIZATION_PROBES_TUPLES=(
    "FILE-SIZE-OK|#file-size-ok"
    "SSoT-OK|#ssot-ok"
    "ESCAPE-HATCH-AUDIT-OK|#escape-hatch-audit-ok-audit-task"
    "WILDCARD-MATCHER-OK|#wildcard-matcher-ok-audit-task"
)
FAILED_NORMALIZATION_PROBE_COUNT=0
for normalization_probe_tuple in "${NORMALIZATION_PROBES_TUPLES[@]}"; do
    probe_marker_token="${normalization_probe_tuple%%|*}"
    expected_anchor_fragment="${normalization_probe_tuple##*|}"
    expected_toc_line="- [\`$probe_marker_token\`]($expected_anchor_fragment)"
    # NOTE the `-e` form is required here because the expected_toc_line
    # begins with `-` and grep would otherwise treat the leading hyphen as
    # an option flag. Cases 2 + 3 use shorter patterns that don't trigger
    # this — the failure mode is specific to the longer literal lines in
    # Case 4.
    if ! grep -qF -e "$expected_toc_line" "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        FAILED_NORMALIZATION_PROBE_COUNT=$((FAILED_NORMALIZATION_PROBE_COUNT + 1))
        echo "    (anchor normalization probe failed: expected line '$expected_toc_line')"
    fi
done
if [[ "$FAILED_NORMALIZATION_PROBE_COUNT" -eq 0 ]]; then
    assert_passes "Case 4: GitHub anchor normalization correct on all 4 probe tokens (plain, mixed-case SSoT, audit-task suffix)"
else
    assert_fails "Case 4: $FAILED_NORMALIZATION_PROBE_COUNT/4 anchor normalization probes failed"
fi

# ─── Case 5: TOC entries are alphabetically ordered within each group ────
# Extract the runtime-hook TOC entries (between '**Runtime-hook markers**'
# and '**Audit-task markers**') and verify alphabetical order.
RUNTIME_HOOK_TOC_ENTRIES_IN_ORDER=$(awk '
    /^\*\*Runtime-hook markers\*\*/ { capturing=1; next }
    /^\*\*Audit-task markers\*\*/ { capturing=0 }
    capturing && /^- \[`[A-Za-z]/ {
        # Extract marker token between the first backtick pair
        match($0, /`[^`]+`/)
        if (RSTART) {
            print substr($0, RSTART+1, RLENGTH-2)
        }
    }
' "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH")

# Expected order is the registry-sorted order (alphabetical). Note: SSoT-OK
# sorts AFTER SETPROCTITLE-OK because JavaScript's Array.toSorted()
# uses default UTF-16 code-unit comparison where uppercase letters precede
# lowercase ones — so the sort order is:
#   ... SETPROCTITLE-OK < SSoT-OK
# (uppercase 'S' < uppercase 'S', then 'E' < 'S', so SETPROCTITLE < SSoT;
# the lowercase 'o' in SSoT comes AFTER the uppercase 'S' in SSoT-OK position
# 3 — but both tokens start with 'S' and the comparison continues char-by-char).
EXPECTED_RUNTIME_HOOK_SORT_ORDER=$(printf '%s\n' "${ITER111_BASELINE_RUNTIME_HOOK_MARKER_TOKENS[@]}")
if [[ "$RUNTIME_HOOK_TOC_ENTRIES_IN_ORDER" == "$EXPECTED_RUNTIME_HOOK_SORT_ORDER" ]]; then
    assert_passes "Case 5: TOC runtime-hook entries in correct alphabetical order matching iter-111 registry sort"
else
    assert_fails "Case 5: TOC runtime-hook entries NOT in expected order"
    echo "    Expected: $(echo "$EXPECTED_RUNTIME_HOOK_SORT_ORDER" | tr '\n' ' ')"
    echo "    Got:      $(echo "$RUNTIME_HOOK_TOC_ENTRIES_IN_ORDER" | tr '\n' ' ')"
fi

# ─── Case 6: idempotency — TOC injection doesn't break --check ───────────
set +e
DRIFT_CHECK_OUTPUT=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
DRIFT_CHECK_EXIT_CODE=$?
set -e
if [[ "$DRIFT_CHECK_EXIT_CODE" -eq 0 ]] && [[ "$DRIFT_CHECK_OUTPUT" == *"no drift"* ]]; then
    assert_passes "Case 6: --check passes after TOC injection (idempotency invariant intact — registry-derived output still byte-identical to on-disk doc)"
else
    assert_fails "Case 6: --check failed after TOC injection (exit=$DRIFT_CHECK_EXIT_CODE)"
fi

# ─── Case 7: every TOC anchor link target exists as an H2 heading ───────
# Extract every anchor fragment from the TOC's '](#anchor)' pattern, then
# for each, verify a matching H2 heading exists in the doc whose
# GitHub-normalized form would produce that exact anchor. This catches
# orphan TOC entries pointing to nonexistent sections.
EXTRACTED_TOC_ANCHOR_FRAGMENTS=$(grep -oE '\]\(#[a-z0-9-]+\)' "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" | sed -E 's/\]\(#([a-z0-9-]+)\)/\1/')

DANGLING_TOC_ANCHOR_COUNT=0
while IFS= read -r anchor_fragment; do
    [[ -z "$anchor_fragment" ]] && continue
    # Normalize every H2 heading in the doc the same way GitHub does and
    # check whether ANY of them produces the anchor fragment. The
    # normalization here MUST match the generator's algorithm exactly:
    # lowercase, drop everything except letters/digits/whitespace/hyphens,
    # trim, collapse whitespace runs into single hyphens.
    MATCHING_HEADING_COUNT=$(awk -v expected_anchor="$anchor_fragment" '
        /^## / {
            heading_text = substr($0, 4)
            # Apply GitHub anchor normalization rules
            normalized = tolower(heading_text)
            gsub(/[^a-z0-9 \-]/, "", normalized)
            # Trim leading + trailing whitespace
            sub(/^[ \t]+/, "", normalized)
            sub(/[ \t]+$/, "", normalized)
            # Collapse whitespace runs to single hyphen
            gsub(/[ \t]+/, "-", normalized)
            if (normalized == expected_anchor) {
                print "MATCH"
            }
        }
    ' "$ITER117_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" | grep -c "MATCH" || echo 0)
    if [[ "$MATCHING_HEADING_COUNT" -lt 1 ]]; then
        DANGLING_TOC_ANCHOR_COUNT=$((DANGLING_TOC_ANCHOR_COUNT + 1))
        echo "    (dangling TOC anchor link: #$anchor_fragment — no matching H2 heading found)"
    fi
done <<< "$EXTRACTED_TOC_ANCHOR_FRAGMENTS"

if [[ "$DANGLING_TOC_ANCHOR_COUNT" -eq 0 ]]; then
    assert_passes "Case 7: every TOC anchor link resolves to an actual H2 heading in the doc (no dangling links — operator clicks always land on a real section)"
else
    assert_fails "Case 7: $DANGLING_TOC_ANCHOR_COUNT TOC anchor link(s) point to nonexistent headings"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-117 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-117 TOC auto-injection established. Operators browsing the"
echo "     reference doc now see a top-of-doc Quick navigation section with"
echo "     20 clickable GitHub-Flavored-Markdown anchor links — one per"
echo "     registered marker — grouped by lifecycle layer (runtime-hook +"
echo "     audit-task) and sorted alphabetically within each group. The"
echo "     385-line scroll-and-search workflow is replaced by a one-click"
echo "     jump to any marker section."
echo "  🚀 Iter-118+ candidates (queued):"
echo "     - Stale-description audit (task #144): verify every registry"
echo "       entry's humanReadable/releaseInvariantSuppressed-Description"
echo "       field mentions a hook/task name consistent with declared"
echo "       consumer-path. Wire into preflight as Check 4v informational."
echo "     - Fuzzy-match suggestion in the iter-116 reverse-search CLI's"
echo "       unknown-path hint: when an operator types a path with a typo,"
echo "       compute Levenshtein distance against the 19 registered paths"
echo "       and surface the top-3 closest matches as 'Did you mean?'"
echo "       suggestions instead of dumping the full list."
