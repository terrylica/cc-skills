#!/usr/bin/env bash
#MISE description="Iter-113 regression test for the registry-to-docs generator. Verifies (1) generator task exists and is executable; (2) generator's --check mode passes against the on-disk committed doc; (3) generator's --stdout mode emits a non-empty doc with every registry baseline marker section (count derived from the iter-111 registry); (4) regenerating the doc twice in a row produces byte-identical output (idempotency invariant — required for the drift-detection check to be meaningful); (5) the on-disk doc renders every registry baseline marker and is in alphabetical order; (6) doc contains expected sections (preamble + marker catalog + invariants + add-new-marker instructions); (7) drift-detection correctly fails when the doc is mutated."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER113_DOC_GENERATOR_ABSOLUTE_PATH="$REPO_ROOT/tasks/generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh"
ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"

# Baseline marker tokens DERIVED from the iter-111 registry (the official
# source) instead of hard-coded — the pinned 12-token array broke when the
# 13th legitimate marker (INVENTED-FALLBACK-OK, 2026-06-11) was registered,
# even though the generator emitted it correctly. One quoted
# markerNameTokenIncludingSuffix field per entry, in registry order.
ITER111_RUNTIME_HOOK_REGISTRY_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"
ITER111_BASELINE_MARKER_TOKENS=()
while IFS= read -r _iter111_marker_token_line; do
    ITER111_BASELINE_MARKER_TOKENS+=("$_iter111_marker_token_line")
done < <(grep -E '^\s*markerNameTokenIncludingSuffix: "' "$ITER111_RUNTIME_HOOK_REGISTRY_ABSOLUTE_PATH" | sed -E 's/.*: "([^"]+)".*/\1/')

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-113 registry-to-docs generator regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE="/tmp/cc-skills-iter113-on-disk-doc-mutation-window-serialization-flock"

# Iter-187: replace the shared canonical doc ATOMICALLY.
#
# Every previous write to this file went through `cp -f`, which opens the
# destination O_TRUNC — so the canonical doc is momentarily ZERO BYTES and any
# concurrent reader in the suite (iter-113 itself, iter-114, iter-115,
# iter-117) can read an empty file. Measured with a tight-loop reader across 6
# suite runs: 453 zero-byte observations out of 6,353,768 reads. That is the
# root cause of the "iter-117 red ~2 runs in 11, green standalone" flake —
# reproduced 3/3 by running iter-117 against a bare `cp -f backup doc` loop.
#
# `mv` within the SAME directory is rename(2), which is atomic: a reader sees
# either the whole old file or the whole new one, never a truncated prefix.
# The staging file must live in docs/ (same filesystem) or mv degrades to a
# copy and the atomicity is lost. chmod 644 because mktemp creates 0600 and
# the committed doc is 0644.
__iter113_atomically_replace_canonical_on_disk_doc_via_same_directory_rename() {
    local content_source_file_absolute_path="$1"
    local staging_file_absolute_path
    staging_file_absolute_path=$(mktemp "$(dirname "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH")/.iter113-atomic-doc-replace-XXXXXX")
    if ! cp -f "$content_source_file_absolute_path" "$staging_file_absolute_path" ||
        ! chmod 644 "$staging_file_absolute_path" ||
        ! mv -f "$staging_file_absolute_path" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        rm -f "$staging_file_absolute_path"
        return 1
    fi
}

# Iter-187: acquire the SHARED half of the iter-126 mutation-window lock.
#
# Every read of the shared canonical on-disk doc in this file must be inside
# one of these regions. Case 2 runs the generator's `--check` against that
# doc; iter-115 Case 5 transiently replaces the doc with a synthetic-drift
# copy under the EXCLUSIVE lock, so an UNLOCKED --check here reads the mutated
# doc and reports a spurious DRIFT — the same cross-test race iter-126 fixed
# for iter-117 Case 6 but never applied to this site.
#
# LOCK_SH, not LOCK_EX, so the readers (iter-113, iter-114, iter-117) do not
# serialize against each other — only against the two mutation windows. Each
# region is opened and fully CLOSED around the reads it protects: the lock is
# never upgraded in place, because two processes both holding LOCK_SH and both
# requesting LOCK_EX would deadlock. Regions are also kept as narrow as the
# reads themselves — Cases 3 and 4 use `--stdout` and never touch the on-disk
# doc, so holding the lock across them would only add ~1 s of needless
# serialization to the parallel suite.
__iter113_acquire_shared_on_disk_doc_read_lock() {
    touch "$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
    exec 9<>"$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
    # Python's fcntl.flock is the portable primitive (macOS ships no GNU
    # `flock` CLI). The lock lives on the open file DESCRIPTION, which this
    # shell owns via fd 9, so it survives the helper process exiting and is
    # released only by `exec 9<&-` (or process exit).
    python3 -c '
import fcntl, sys
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_SH)
' 9 <&9
}

# ─── Case 1: generator task exists and is executable ─────────────────────
if [[ -x "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: iter-113 doc generator task exists and is executable"
else
    assert_fails "Case 1: iter-113 doc generator task missing or not executable"
fi

# ─── Case 2: --check mode passes against the on-disk committed doc ───────
__iter113_acquire_shared_on_disk_doc_read_lock
set +e
check_mode_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
check_mode_exit_code=$?
set -e
exec 9<&-
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
    assert_passes "Case 3: generator --stdout mode emits non-empty doc (${#stdout_mode_output} chars) with all ${#ITER111_BASELINE_MARKER_TOKENS[@]} baseline marker sections"
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
#
# Iter-187: Cases 5 and 6 both read the shared on-disk doc — one shared-lock
# region spans both, released after Case 6.
__iter113_acquire_shared_on_disk_doc_read_lock
ON_DISK_MARKER_HEADING_ORDER=$(awk -F '`' '/^## `[^`]+`$/ {print $2}' "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH")
EXPECTED_ALPHABETICAL_ORDER=$(printf '%s\n' "${ITER111_BASELINE_MARKER_TOKENS[@]}" | sort)

if [[ "$ON_DISK_MARKER_HEADING_ORDER" == "$EXPECTED_ALPHABETICAL_ORDER" ]]; then
    assert_passes "Case 5: on-disk doc renders all ${#ITER111_BASELINE_MARKER_TOKENS[@]} baseline markers in alphabetical order"
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
# Iter-187: end of the Case 5 + Case 6 shared-read region.
exec 9<&-

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

# The synthetic line Case 7 appends. The cleanup below keys off it so the trap
# can tell "my mutation is still on disk" from "someone else legitimately
# rewrote this file".
ITER113_SYNTHETIC_MUTATION_SENTINEL="SYNTHETIC DRIFT MUTATION INJECTED BY ITER113 REGRESSION TEST CASE 7"

# Iter-186: restore ONLY what this test broke, and only if it is still broken.
#
# The previous trap was an unconditional `cp -f "$backup" "$doc"` on EXIT. The
# flock below is released the moment Case 7 restores the doc inline, but the
# TRAP fires much later, at process exit — outside the lock. So any legitimate
# rewrite of the doc that landed in between (a `--write` regeneration, or
# another test's restore) was silently clobbered back to this test's stale
# snapshot, taking iter-113/114/115/117 down together and making the suite
# report anywhere from 94 to 109 passing. Observed twice on 2026-08-31.
#
# Restoring a snapshot is the wrong verb for a cleanup handler: it asserts
# authority over a file this test does not own. Undoing its own mutation is the
# right one, and it is inherently race-free — no lock needed, idempotent, and a
# no-op when Case 7 already restored or never ran.
__iter113_cleanup_restoring_only_our_own_synthetic_mutation() {
    if [[ -s "$ORIGINAL_DOC_BACKUP_FILE" ]] &&
        grep -qF "$ITER113_SYNTHETIC_MUTATION_SENTINEL" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" 2>/dev/null; then
        # Iter-187: atomic rename, not cp -f — see the helper's header. The
        # trap fires at process exit, OUTSIDE the lock, so a torn write here
        # is visible to every other test still running.
        __iter113_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
            "$ORIGINAL_DOC_BACKUP_FILE"
    fi
    rm -f "$FIRST_RUN_OUTPUT_FILE" "$SECOND_RUN_OUTPUT_FILE" "$ORIGINAL_DOC_BACKUP_FILE"
}
trap __iter113_cleanup_restoring_only_our_own_synthetic_mutation EXIT

# Iter-126 fix: acquire the shared mutation-window flock before mutating the
# canonical on-disk doc. Without this, the iter-117 Case 6 --check (which
# reads the same canonical doc to verify the no-drift idempotency invariant)
# fires concurrently under xargs -P parallelism (iter-75 parallel-suite
# runner) and observes the synthetic mutation as spurious DRIFT exit=1.
# Lock-file path is shared with test-iter115*.sh and test-iter117*.sh. See
# iter-126 commit for full forensic analysis.
#
# Iter-187: this is an EXCLUSIVE acquisition, and it starts from a CLOSED
# fd 9 — the Case 5/6 shared-read region already released it, and the belt-
# and-braces close below is a no-op on an unopened fd in bash. flock must
# never upgrade LOCK_SH to LOCK_EX in place: two processes both holding
# LOCK_SH and both requesting LOCK_EX would deadlock on each other.
exec 9<&-
exec 9<>"$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
python3 -c '
import fcntl, sys
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX)
' 9 <&9

cp "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" "$ORIGINAL_DOC_BACKUP_FILE"
# Iter-187: stage the mutated doc, then rename it into place, so the doc is
# only ever observable as fully-canonical or fully-mutated. The previous
# `>>` pair also left an intermediate "canonical + blank line" state.
ITER113_MUTATED_DOC_STAGING_FILE=$(mktemp -t iter113-mutated-doc-XXXXXX.md)
{
    cat "$ORIGINAL_DOC_BACKUP_FILE"
    echo ""
    echo "$ITER113_SYNTHETIC_MUTATION_SENTINEL — SHOULD BE RESTORED BY TRAP"
} > "$ITER113_MUTATED_DOC_STAGING_FILE"
__iter113_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
    "$ITER113_MUTATED_DOC_STAGING_FILE"
rm -f "$ITER113_MUTATED_DOC_STAGING_FILE"

set +e
drift_check_output=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
drift_check_exit_code=$?
set -e

# Restore the original doc immediately so subsequent test cases see clean state
__iter113_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
    "$ORIGINAL_DOC_BACKUP_FILE"

# Iter-126 release the exclusive mutation-window flock now that the on-disk
# doc is back to its canonical state.
#
# Iter-187: immediately re-acquire it SHARED, because the post-Case-7
# restoration verification below runs another `--check` against the shared
# doc and would otherwise read iter-115's mutation window as a spurious
# DRIFT. Full release then fresh acquisition — never an in-place LOCK_EX →
# LOCK_SH juggle interleaved with another process's upgrade.
exec 9<&-
__iter113_acquire_shared_on_disk_doc_read_lock

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

# Iter-187: last read of the shared on-disk doc is done — release the shared
# lock so the other tests' exclusive mutation windows can proceed.
exec 9<&-

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
