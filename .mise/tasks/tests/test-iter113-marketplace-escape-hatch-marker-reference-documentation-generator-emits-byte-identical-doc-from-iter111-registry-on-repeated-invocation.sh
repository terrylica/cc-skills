#!/usr/bin/env bash
#MISE description="Iter-113 regression test for the registry-to-docs generator. Verifies (1) generator task exists and is executable; (2) generator's --check mode passes against the on-disk committed doc; (3) generator's --stdout mode emits a non-empty doc with all 12 baseline marker sections; (4) regenerating the doc twice in a row produces byte-identical output (idempotency invariant — required for the drift-detection check to be meaningful); (5) the on-disk doc renders all 12 baseline markers and is in alphabetical order; (6) doc contains expected sections (preamble + marker catalog + invariants + add-new-marker instructions); (7) drift-detection correctly fails when the doc is mutated."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER113_DOC_GENERATOR_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh"
ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"

ITER111_BASELINE_MARKER_TOKENS=(
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

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-113 registry-to-docs generator regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: generator task exists and is executable ─────────────────────
if [[ -x "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: iter-113 doc generator task exists and is executable"
else
    assert_fails "Case 1: iter-113 doc generator task missing or not executable"
fi

# ─── Case 2: --check mode passes against the on-disk committed doc ───────
set +e
check_mode_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
check_mode_exit_code=$?
set -e
if [[ "$check_mode_exit_code" == "0" ]] && [[ "$check_mode_output" == *"no drift"* ]]; then
    assert_passes "Case 2: generator --check mode reports no drift (on-disk doc matches registry-derived output)"
else
    assert_fails "Case 2: generator --check mode failed (exit=$check_mode_exit_code, output=$check_mode_output)"
fi

# ─── Case 3: --stdout mode emits non-empty doc with all baseline markers ─
set +e
stdout_mode_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --stdout 2>/dev/null)
stdout_mode_exit_code=$?
set -e

MISSING_FROM_STDOUT_COUNT=0
for baseline_marker_token in "${ITER111_BASELINE_MARKER_TOKENS[@]}"; do
    if [[ "$stdout_mode_output" != *"## \`$baseline_marker_token\`"* ]]; then
        MISSING_FROM_STDOUT_COUNT=$((MISSING_FROM_STDOUT_COUNT + 1))
    fi
done

if [[ "$stdout_mode_exit_code" == "0" ]] && [[ "${#stdout_mode_output}" -gt 1000 ]] && [[ "$MISSING_FROM_STDOUT_COUNT" -eq 0 ]]; then
    assert_passes "Case 3: generator --stdout mode emits non-empty doc (${#stdout_mode_output} chars) with all 12 baseline marker sections"
else
    assert_fails "Case 3: --stdout missing markers ($MISSING_FROM_STDOUT_COUNT) or empty output (exit=$stdout_mode_exit_code, ${#stdout_mode_output} chars)"
fi

# ─── Case 4: idempotency — two consecutive runs produce byte-identical output ─
FIRST_RUN_OUTPUT_FILE=$(mktemp -t iter113-first-XXXXXX.md)
SECOND_RUN_OUTPUT_FILE=$(mktemp -t iter113-second-XXXXXX.md)
trap 'rm -f "$FIRST_RUN_OUTPUT_FILE" "$SECOND_RUN_OUTPUT_FILE"' EXIT

bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --stdout > "$FIRST_RUN_OUTPUT_FILE" 2>/dev/null
bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --stdout > "$SECOND_RUN_OUTPUT_FILE" 2>/dev/null

if diff -q "$FIRST_RUN_OUTPUT_FILE" "$SECOND_RUN_OUTPUT_FILE" >/dev/null 2>&1; then
    assert_passes "Case 4: idempotency — two consecutive generator runs produce byte-identical output (required for meaningful drift detection)"
else
    assert_fails "Case 4: idempotency broken — consecutive runs differ"
fi

# ─── Case 5: on-disk doc renders all baseline RUNTIME markers in alphabetical order ─
# Extraction strategy: use awk with backtick as field separator to pull
# marker names from headings of the form `## ${BACKTICK}MARKER${BACKTICK}`.
# This is cleaner than a grep|sed combo with nested backticks (which the
# shell-lint tool's SC2016 check mis-parses as containing shell-expansion
# expressions). awk's field-split semantics treat the backtick as a
# delimiter character, so the marker name lands in $2 and we don't need
# to write the backtick anywhere a static lint tool can misinterpret.
# (Note: the comment is intentionally phrased to avoid a leading-word
# `# shellcheck ...` shape, which would otherwise trip SC1072/SC1073 on
# the line below as a malformed directive.)
#
# Iter-114 amendment: the doc now contains TWO catalogs (runtime-hook
# markers + audit-task markers). Runtime headings have form
# `## ${BACKTICK}MARKER${BACKTICK}` while audit headings have form
# `## ${BACKTICK}MARKER${BACKTICK} (audit-task)`. The awk pattern below
# anchors to a trailing backtick at end-of-line to match RUNTIME headings
# only — audit headings have the ` (audit-task)` suffix and are filtered
# out. This isolates the iter-113-scope alphabetical-order check to the
# runtime registry; iter-114's regression test independently validates
# the audit-task catalog's alphabetical order.
ON_DISK_MARKER_HEADING_ORDER=$(awk -F '`' '/^## `[^`]+`$/ {print $2}' "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH")
EXPECTED_ALPHABETICAL_ORDER=$(printf '%s\n' "${ITER111_BASELINE_MARKER_TOKENS[@]}" | sort)

if [[ "$ON_DISK_MARKER_HEADING_ORDER" == "$EXPECTED_ALPHABETICAL_ORDER" ]]; then
    assert_passes "Case 5: on-disk doc renders all 12 baseline markers in alphabetical order"
else
    assert_fails "Case 5: marker order in on-disk doc does NOT match alphabetical expectation"
    echo "    Expected: $EXPECTED_ALPHABETICAL_ORDER" | tr '\n' ' '
    echo "    Got:      $ON_DISK_MARKER_HEADING_ORDER" | tr '\n' ' '
fi

# ─── Case 6: doc contains expected non-catalog sections ──────────────────
EXPECTED_HEADER_SECTIONS=(
    "# Marketplace Escape-Hatch Marker Reference"
    "## Purpose"
    "## How to use this reference"
    "## Marketplace invariants (audit-enforced)"
    # Iter-114 amendment: the single "## Marker catalog" header was split into
    # two distinct catalogs — runtime-hook markers (iter-111) and audit-task
    # markers (iter-114). Test now expects both section headers.
    "## Runtime-hook marker catalog"
    "## Audit-task marker catalog"
    "## Marketplace UPPER-KEBAB-CASE convention"
    "## Adding a new marker"
    "## Related documentation"
)

MISSING_SECTION_COUNT=0
for expected_section_header in "${EXPECTED_HEADER_SECTIONS[@]}"; do
    if ! grep -qF "$expected_section_header" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        MISSING_SECTION_COUNT=$((MISSING_SECTION_COUNT + 1))
        echo "    (missing section: '$expected_section_header')"
    fi
done

if [[ "$MISSING_SECTION_COUNT" -eq 0 ]]; then
    assert_passes "Case 6: on-disk doc contains all 8 expected non-catalog sections (preamble + purpose + how-to + invariants + catalog + convention + add-new + related)"
else
    assert_fails "Case 6: on-disk doc missing $MISSING_SECTION_COUNT expected section(s)"
fi

# ─── Case 7: drift-detection correctly fails when doc is mutated ─────────
# Inject a deliberate mutation into a temp copy of the on-disk doc, swap it
# in, run --check, verify it fails, then restore. Uses a temp file alias to
# avoid risk of leaving the on-disk doc mutated if the test errors midway.
ORIGINAL_DOC_BACKUP_FILE=$(mktemp -t iter113-original-doc-XXXXXX.md)
trap 'cp -f "$ORIGINAL_DOC_BACKUP_FILE" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" 2>/dev/null; rm -f "$FIRST_RUN_OUTPUT_FILE" "$SECOND_RUN_OUTPUT_FILE" "$ORIGINAL_DOC_BACKUP_FILE"' EXIT

# Iter-126 fix: acquire shared mutation-window flock before mutating the
# canonical on-disk doc. Without this, the iter-117 Case 6 --check (which
# reads the same canonical doc to verify the no-drift idempotency invariant)
# fires concurrently under xargs -P parallelism (iter-75 parallel-suite
# runner) and observes the synthetic mutation as spurious DRIFT exit=1.
# Lock-file path is shared with test-iter115*.sh and test-iter117*.sh. See
# iter-126 commit for full forensic analysis.
ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE="/tmp/cc-skills-iter113-on-disk-doc-mutation-window-serialization-flock"
touch "$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
exec 9<>"$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
python3 -c '
import fcntl, sys
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX)
' 9 <&9

cp "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" "$ORIGINAL_DOC_BACKUP_FILE"
echo "" >> "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"
echo "SYNTHETIC DRIFT MUTATION INJECTED BY ITER113 REGRESSION TEST CASE 7 — SHOULD BE RESTORED BY TRAP" >> "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"

set +e
drift_check_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
drift_check_exit_code=$?
set -e

# Restore the original doc immediately so subsequent test cases see clean state
cp -f "$ORIGINAL_DOC_BACKUP_FILE" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"

# Iter-126 release the mutation-window flock now that on-disk doc is back to canonical state.
exec 9<&-

if [[ "$drift_check_exit_code" != "0" ]] && [[ "$drift_check_output" == *"DRIFT"* ]]; then
    assert_passes "Case 7: drift-detection correctly fails (exit=$drift_check_exit_code, reports DRIFT) when on-disk doc is mutated"
else
    assert_fails "Case 7: drift-detection FAILED to detect synthetic mutation (exit=$drift_check_exit_code)"
fi

# Verify restoration succeeded — running --check on the restored doc should pass
set +e
post_restore_check_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
post_restore_check_exit_code=$?
set -e
if [[ "$post_restore_check_exit_code" != "0" ]]; then
    echo "  ✗ POST-CASE-7 RESTORATION FAILED — on-disk doc may be in a corrupt state. Output: $post_restore_check_output"
    exit 1
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-113 regression — Summary"
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
echo "  🚀 Iter-113 registry-to-docs generator established. Operators now have"
echo "     a single discoverable artifact at docs/marketplace-escape-hatch-marker-"
echo "     reference.md that catalogs every legitimate marker with consumer hook,"
echo "     case/window/reason policies, and example usage."
echo "  🚀 Idempotency invariant verified: regenerating on an unchanged registry"
echo "     produces byte-identical output, making the drift-detection check"
echo "     meaningful (any diff means SSoT divergence between source and doc)."
echo "  🚀 Iter-114+ candidates documented inline:"
echo "     - Extend iter-111 registry to cover the AUDIT-marker family (~10"
echo "       markers consumed by .mise/ audit tasks rather than runtime hooks)"
echo "     - Promote iter-111 audit Check 4t + iter-113 drift check Check 4u"
echo "       from informational to STRICT-BLOCK"
