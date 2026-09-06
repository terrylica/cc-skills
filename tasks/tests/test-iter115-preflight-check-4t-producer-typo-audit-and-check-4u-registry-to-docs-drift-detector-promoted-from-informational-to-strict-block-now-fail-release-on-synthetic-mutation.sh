#!/usr/bin/env bash
# Iter-115 regression test for the strict-promotion of Check 4t (iter-111 producer-side escape-hatch-marker typo audit) + Check 4u (iter-113 registry-to-docs drift detector) from INFORMATIONAL to STRICT-BLOCK in tasks/release/preflight. Verifies (1) preflight file declares both checks as iter-115 STRICT-BLOCK and exits 1 on either audit failure; (2) Check 4t audit emits the 'AUDIT FOUND N' signal that the preflight wrapper extracts when a synthetic unregistered marker is injected into a producer file; (3) the preflight wrapper's bash-extraction logic for ITER111_UNREGISTERED_COUNT correctly parses the count back out and yields ≥1 on injected typo / 0 on clean baseline; (4) Check 4u --check mode exits non-zero AND emits 'DRIFT' on injected doc mutation while remaining exit-zero AND emitting 'no drift' on the unmutated baseline; (5) both audit tasks return to clean baseline after trap-driven restoration (preflight's own subsequent run would pass).

# ────────────────────────────────────────────────────────────────────────
# Iter-115 design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-111 introduced Check 4t (producer-side marker typo audit) as
# INFORMATIONAL — the audit task itself always exits 0, but emits an
# "AUDIT FOUND N unregistered marker token(s)" line that the preflight
# wrapper can parse to decide whether to block release. Iter-111's
# preflight wiring intentionally never blocked: the goal was registry
# stabilization, not enforcement.
#
# Iter-113 introduced Check 4u (registry-to-docs drift detector) also as
# INFORMATIONAL — same rationale: the generator's --check mode exits
# non-zero on drift, but the preflight wrapper swallowed the exit and
# only logged a warning.
#
# Iter-114 stabilized both registries (12 runtime + 8 audit-task markers)
# and produced the canonical on-disk reference doc. Documented
# precondition for iter-115+ strict-promotion was: "registry coverage
# stabilized + on-disk doc generated + 0 unregistered markers in the
# baseline."
#
# Iter-115 promotes both checks from informational to STRICT-BLOCK. This
# regression test pins the new behavior so a future "rollback to
# informational" change (intentional or accidental) is caught.
#
# Three failure modes this test catches:
#
#   F1. Preflight strict-promotion regression — someone replaces
#       `exit 1` back with `echo "(Informational only…)"`. Test asserts
#       both Check 4t + 4u stanzas in preflight contain `exit 1` paths.
#
#   F2. Audit task contract regression — someone refactors the iter-111
#       audit task to no longer emit "AUDIT FOUND N" in a parseable
#       shape, breaking the preflight wrapper's count extraction.
#       Test asserts the synthetic-mutation injection produces the
#       expected signal AND the extraction logic returns the expected
#       count.
#
#   F3. Generator drift-detection regression — someone refactors the
#       iter-113 generator's --check mode to no longer exit non-zero
#       on drift (e.g., silent best-effort warning). Test asserts
#       --check returns non-zero on mutation AND emits "DRIFT" output.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

PREFLIGHT_SCRIPT_ABSOLUTE_PATH="$REPO_ROOT/tasks/release/preflight"
ITER111_PRODUCER_TYPO_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/tasks/audit-marketplace-wide-producer-escape-hatch-marker-typo-detection-against-canonical-iter111-registry.sh"
ITER113_DOC_GENERATOR_ABSOLUTE_PATH="$REPO_ROOT/tasks/generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry.sh"
ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH="$REPO_ROOT/docs/marketplace-escape-hatch-marker-reference.md"
ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE="/tmp/cc-skills-iter113-on-disk-doc-mutation-window-serialization-flock"

# Iter-187: replace the shared canonical doc ATOMICALLY.
#
# Every previous write to this file went through `cp -f`, which opens the
# destination O_TRUNC — so the canonical doc is momentarily ZERO BYTES and any
# concurrent reader in the suite (iter-113, iter-114, iter-117) can read an
# empty file. Measured with a tight-loop reader across 6 suite runs: 453
# zero-byte observations out of 6,353,768 reads. That is the root cause of the
# "iter-117 red ~2 runs in 11, green standalone" flake — reproduced 3/3 by
# running iter-117 against a bare `cp -f backup doc` loop.
#
# `mv` within the SAME directory is rename(2), which is atomic: a reader sees
# either the whole old file or the whole new one, never a truncated prefix.
# The staging file must live in docs/ (same filesystem) or mv degrades to a
# copy and the atomicity is lost. chmod 644 because mktemp creates 0600 and
# the committed doc is 0644.
__iter115_atomically_replace_canonical_on_disk_doc_via_same_directory_rename() {
    local content_source_file_absolute_path="$1"
    local staging_file_absolute_path
    staging_file_absolute_path=$(mktemp "$(dirname "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH")/.iter115-atomic-doc-replace-XXXXXX")
    if ! cp -f "$content_source_file_absolute_path" "$staging_file_absolute_path" ||
        ! chmod 644 "$staging_file_absolute_path" ||
        ! mv -f "$staging_file_absolute_path" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH"; then
        rm -f "$staging_file_absolute_path"
        return 1
    fi
}

# Producer file used as the synthetic-typo injection target. Chosen to be
# a TypeScript file under a plugin's scripts/ directory (NOT under
# plugins/itp-hooks/hooks/, which is the CONSUMER directory the audit
# explicitly excludes — see the iter-111 audit's Step 3 inclusion rules).
# We append a single-line comment with a synthetic UPPER-KEBAB-CASE-OK
# token that is guaranteed to never appear in the registry.
PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH="$REPO_ROOT/plugins/gmail-commander/scripts/bot.ts"

# ─── ITER-193: the PRODUCER file needs the same atomic restore as the doc ────
#
# Iter-187 made every write to the shared DOC atomic and left the three writes
# to this shared PRODUCER file on `cp -f`. The zero-byte window therefore did
# not go away, it just moved: measured 2026-09-05 with the same tight-loop
# reader across ~27 suite runs, `plugins/gmail-commander/scripts/bot.ts` was
# observed EMPTY 3,804 times in 174,050,501 stat() reads, while
# `docs/marketplace-escape-hatch-marker-reference.md` was observed empty 0
# times in the same 174,050,501 — the doc's fix works, and its absence here is
# visible in the same measurement. Both figures are the same order as the
# 453-in-6,353,768 that the 2026-09-02 entry proved was enough to redden
# iter-117 in ~18% of parallel runs.
#
# iter-192 serialised the two tree-SCANNERS (iter-111, iter-115) against each
# other, which is a different resource: it stops one test's synthetic marker
# from being seen by the other's clean-baseline scan. It does nothing about a
# THIRD process reading a truncated bot.ts — and `repo:lint`
# (scripts/validate-plugins.mjs) and `repo:test` run CONCURRENTLY with
# `repo:test-hooks` inside `moon run repo:check`, so third readers exist
# outside this suite entirely. Enumerate the roster from the RESOURCE.
#
# Same primitive as the doc helper above: stage in the target's OWN directory
# so `mv` is rename(2), and carry the mode across because mktemp creates 0600
# while the committed file is 0644.
__iter115_atomically_restore_shared_producer_file_via_same_directory_rename() {
    local content_source_file_absolute_path="$1"
    local target_absolute_path="$2"
    local staging_file_absolute_path target_directory preserved_octal_mode
    target_directory="${target_absolute_path%/*}"
    preserved_octal_mode=$(stat -f '%Lp' "$target_absolute_path" 2>/dev/null || echo 644)
    staging_file_absolute_path=$(mktemp "$target_directory/.iter193-atomic-producer-restore-XXXXXX")
    if ! cp -f "$content_source_file_absolute_path" "$staging_file_absolute_path" ||
        ! chmod "$preserved_octal_mode" "$staging_file_absolute_path" ||
        ! mv -f "$staging_file_absolute_path" "$target_absolute_path"; then
        rm -f "$staging_file_absolute_path"
        return 1
    fi
}
SYNTHETIC_UNREGISTERED_MARKER_TOKEN_GUARANTEED_NEVER_TO_APPEAR_IN_CANONICAL_REGISTRY="ITER115-SYNTHETIC-NEVER-REGISTERED-TYPO-PROBE-OK"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-115 Check 4t + 4u strict-promotion regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: preflight declares both checks as iter-115 STRICT-BLOCK with exit-1 paths ───
#
# Verify both Check 4t (producer-typo) and Check 4u (doc-drift) stanzas
# contain the iter-115 strict-promotion marker AND an `exit 1` path. This
# catches the most likely regression: someone reverting either check to
# the iter-111/iter-113 informational shape.

PREFLIGHT_CHECK_4T_BLOCK=$(awk '/# Check 4t:/,/# Check 4u:/' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")
PREFLIGHT_CHECK_4U_BLOCK=$(awk '/# Check 4u:/,/# Check 5:|# Check 4v:|# === Check 5/' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")

if [[ "$PREFLIGHT_CHECK_4T_BLOCK" == *"iter-115 STRICT-BLOCK"* ]] && \
   [[ "$PREFLIGHT_CHECK_4T_BLOCK" == *"exit 1"* ]] && \
   [[ "$PREFLIGHT_CHECK_4U_BLOCK" == *"iter-115 STRICT-BLOCK"* ]] && \
   [[ "$PREFLIGHT_CHECK_4U_BLOCK" == *"exit 1"* ]]; then
    assert_passes "Case 1: preflight declares Check 4t + Check 4u as iter-115 STRICT-BLOCK with exit-1 paths (rollback to informational would fail this test)"
else
    assert_fails "Case 1: preflight Check 4t and/or Check 4u missing iter-115 STRICT-BLOCK markers or exit-1 paths"
fi

# ─── iter-192: PRODUCER-TREE mutation/scan serialization ──────────────────
#
# ROOT CAUSE of the parallel-only suite flake (measured: 6 failures in 40
# parallel runs, 0 in 32 serial, Fisher one-sided p=0.02457; reproduced 2/12
# here as "Case 4: live audit run did NOT pass"). TWO test files plant a
# synthetic UNREGISTERED marker into the SHARED marketplace working tree:
#
#   iter-111 Case 5 -> plugins/agent-reach/scripts/<synthetic fixture>.sh
#   iter-115 Case 2 -> plugins/gmail-commander/scripts/bot.ts
#
# and BOTH also run a marketplace-WIDE audit that asserts a CLEAN baseline.
# In parallel, one file's plant is live in the tree while the other file's
# clean-baseline scan walks it, so the scan finds a real unregistered marker
# and fails. Nothing was wrong with either test in isolation.
#
# WHY THE EXISTING FLOCK DID NOT COVER THIS. iter-126's flock is named for,
# and scoped to, the on-disk DOC mutation window
# (/tmp/cc-skills-iter113-on-disk-doc-mutation-window-serialization-flock).
# An audit of "does every file that touches the doc hold the flock?" answers
# YES for all four doc-touchers -- and that question has a NARROWER DOMAIN
# than the claim it was taken to support. The resource actually at risk is
# the PRODUCER TREE, whose roster is {iter-111, iter-115}, and only one of
# those two held any lock at all. Enumerate the roster from the RESOURCE,
# not from the files you already noticed.
#
# FIX: a SEPARATE lock for the producer-tree window, taken by both members of
# that roster and held to process exit. It serialises exactly these two files
# against each other and leaves every other lane parallel. Lock ORDER is
# always producer-tree -> doc (iter-115 takes this one first, iter-113/114/117
# take only the doc lock), so no cycle exists and no deadlock is reachable.
ITER192_PRODUCER_TREE_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE="/tmp/cc-skills-iter192-producer-tree-mutation-window-serialization-flock"
touch "$ITER192_PRODUCER_TREE_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
exec 8<>"$ITER192_PRODUCER_TREE_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
# macOS BSD has no GNU `flock` CLI; python3's fcntl is the portable primitive
# (same approach as iter-126). Bound to fd 8 -- the doc lock owns fd 9 -- and
# released automatically when this process exits.
python3 -c '
import fcntl, sys
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX)
' 8 <&8

# ─── Case 2: synthetic typo injection produces parseable "AUDIT FOUND N" signal ───
#
# Inject a synthetic UPPER-KEBAB-CASE-OK token into a producer file via
# a one-line append, run the iter-111 audit, verify the output contains
# the "AUDIT FOUND N" line shape that the preflight wrapper extracts.
# Restore the producer file via trap before subsequent test cases run.

PRODUCER_FILE_BACKUP_ABSOLUTE_PATH=$(mktemp -t iter115-producer-backup-XXXXXX)

# Iter-186: sentinels that identify THIS test's own mutations, so cleanup can
# undo them without asserting authority over files it does not own. See the
# long rationale on the EXIT trap further down (Case 5).
ITER115_PRODUCER_MUTATION_SENTINEL="ITER115 REGRESSION TEST CASE 2 SYNTHETIC INJECTION"
ITER115_DOC_MUTATION_SENTINEL="ITER115 REGRESSION TEST CASE 5 SYNTHETIC DOC MUTATION"

__iter115_restore_producer_only_if_still_carrying_our_injection() {
    if [[ -s "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH" ]] &&
        grep -qF "$ITER115_PRODUCER_MUTATION_SENTINEL" "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH" 2>/dev/null; then
        __iter115_atomically_restore_shared_producer_file_via_same_directory_rename "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH" "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
    fi
    rm -f "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH"
}
trap __iter115_restore_producer_only_if_still_carrying_our_injection EXIT

if [[ ! -f "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH" ]]; then
    assert_fails "Case 2: producer-file injection target does not exist (cannot inject synthetic typo): $PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
    echo ""
    echo "  Test cannot proceed — producer-file injection target missing."
    exit 1
fi

cp "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH" "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH"
echo "" >> "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
echo "// ITER115 REGRESSION TEST CASE 2 SYNTHETIC INJECTION — $SYNTHETIC_UNREGISTERED_MARKER_TOKEN_GUARANTEED_NEVER_TO_APPEAR_IN_CANONICAL_REGISTRY (should be restored by trap)" >> "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"

set +e
ITER111_AUDIT_OUTPUT_WITH_SYNTHETIC_TYPO_INJECTED=$(bash "$ITER111_PRODUCER_TYPO_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
ITER111_AUDIT_EXIT_CODE_WITH_SYNTHETIC_TYPO_INJECTED=$?
set -e

# Restore producer file IMMEDIATELY so subsequent cases see clean state
__iter115_atomically_restore_shared_producer_file_via_same_directory_rename "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH" "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"

# The audit task itself exits 0 by design (it's INFORMATIONAL at the task
# layer; the STRICT-BLOCK enforcement lives in the preflight wrapper).
# What we verify here is the SIGNAL shape that the wrapper depends on.
if [[ "$ITER111_AUDIT_OUTPUT_WITH_SYNTHETIC_TYPO_INJECTED" == *"AUDIT FOUND"* ]] && \
   [[ "$ITER111_AUDIT_OUTPUT_WITH_SYNTHETIC_TYPO_INJECTED" == *"$SYNTHETIC_UNREGISTERED_MARKER_TOKEN_GUARANTEED_NEVER_TO_APPEAR_IN_CANONICAL_REGISTRY"* ]]; then
    assert_passes "Case 2: synthetic-typo injection produces 'AUDIT FOUND N' signal containing the injected token (audit→wrapper contract intact)"
else
    assert_fails "Case 2: audit failed to emit 'AUDIT FOUND' signal OR omitted injected token (exit=$ITER111_AUDIT_EXIT_CODE_WITH_SYNTHETIC_TYPO_INJECTED)"
fi

# ─── Case 3: preflight extraction logic correctly counts injected unregistered markers ───
#
# Replay the EXACT extraction shape the iter-115 preflight uses (search
# tasks/release/preflight for ITER111_UNREGISTERED_COUNT). We need
# to re-inject + re-run to get a fresh log; this case verifies the
# specific grep|sed|extract pipeline the preflight wrapper depends on.

cp "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH" "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH"
echo "" >> "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
echo "// ITER115 REGRESSION TEST CASE 3 SYNTHETIC INJECTION — $SYNTHETIC_UNREGISTERED_MARKER_TOKEN_GUARANTEED_NEVER_TO_APPEAR_IN_CANONICAL_REGISTRY (should be restored by trap)" >> "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"

PREFLIGHT_WRAPPER_LOG_FILE_ABSOLUTE_PATH=$(mktemp -t iter115-preflight-wrapper-log-XXXXXX.log)
set +e
bash "$ITER111_PRODUCER_TYPO_AUDIT_TASK_ABSOLUTE_PATH" >"$PREFLIGHT_WRAPPER_LOG_FILE_ABSOLUTE_PATH" 2>&1
set -e

# Replay the exact preflight extraction pipeline from iter-115 STRICT block
ITER111_UNREGISTERED_COUNT_EXTRACTED_BY_PREFLIGHT_WRAPPER_LOGIC=$( { grep -oE 'AUDIT FOUND [0-9]+' "$PREFLIGHT_WRAPPER_LOG_FILE_ABSOLUTE_PATH" || true; } | grep -oE '[0-9]+' | head -1 || echo 0)

__iter115_atomically_restore_shared_producer_file_via_same_directory_rename "$PRODUCER_FILE_BACKUP_ABSOLUTE_PATH" "$PRODUCER_FILE_USED_AS_SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
rm -f "$PREFLIGHT_WRAPPER_LOG_FILE_ABSOLUTE_PATH"

if [[ "${ITER111_UNREGISTERED_COUNT_EXTRACTED_BY_PREFLIGHT_WRAPPER_LOGIC:-0}" -ge 1 ]]; then
    assert_passes "Case 3: preflight bash-extraction pipeline (grep -oE 'AUDIT FOUND [0-9]+' | grep -oE '[0-9]+') correctly yields ≥1 (got $ITER111_UNREGISTERED_COUNT_EXTRACTED_BY_PREFLIGHT_WRAPPER_LOGIC) — wrapper would correctly trigger exit 1"
else
    assert_fails "Case 3: preflight extraction pipeline yielded $ITER111_UNREGISTERED_COUNT_EXTRACTED_BY_PREFLIGHT_WRAPPER_LOGIC (expected ≥1)"
fi

# ─── Case 4: preflight extraction logic returns 0 on clean baseline ───
#
# Inverse of Case 3: re-run the audit on the restored producer file and
# verify the extraction yields 0. This guards against a false-positive
# regression where the extraction pipeline always returns ≥1 (which
# would block EVERY release, not just the typo ones).

PREFLIGHT_WRAPPER_LOG_FILE_CLEAN_BASELINE_ABSOLUTE_PATH=$(mktemp -t iter115-preflight-clean-log-XXXXXX.log)
set +e
bash "$ITER111_PRODUCER_TYPO_AUDIT_TASK_ABSOLUTE_PATH" >"$PREFLIGHT_WRAPPER_LOG_FILE_CLEAN_BASELINE_ABSOLUTE_PATH" 2>&1
set -e

ITER111_UNREGISTERED_COUNT_EXTRACTED_ON_CLEAN_BASELINE=$( { grep -oE 'AUDIT FOUND [0-9]+' "$PREFLIGHT_WRAPPER_LOG_FILE_CLEAN_BASELINE_ABSOLUTE_PATH" || true; } | grep -oE '[0-9]+' | head -1 || echo 0)
rm -f "$PREFLIGHT_WRAPPER_LOG_FILE_CLEAN_BASELINE_ABSOLUTE_PATH"

if [[ "${ITER111_UNREGISTERED_COUNT_EXTRACTED_ON_CLEAN_BASELINE:-99}" -eq 0 ]]; then
    assert_passes "Case 4: preflight extraction pipeline correctly yields 0 on clean baseline (no false-positive release blocks)"
else
    assert_fails "Case 4: clean-baseline audit yielded $ITER111_UNREGISTERED_COUNT_EXTRACTED_ON_CLEAN_BASELINE unregistered markers (expected 0) — either the baseline has drift or the test injection wasn't fully restored"
fi

# ─── Case 5: --check mode exits non-zero AND emits 'DRIFT' on injected doc mutation ───
#
# Verifies the iter-113 generator's drift-detection contract. The
# preflight wrapper for Check 4u relies entirely on the generator's
# exit code: a non-zero exit (with the "DRIFT" string visible to the
# operator) is the release-blocking signal.

ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH=$(mktemp -t iter115-doc-backup-XXXXXX.md)
# Iter-186: extend cleanup to the doc, still restoring ONLY our own mutation.
#
# The previous trap was an unconditional pair of `cp -f "$backup" "$target"`.
# The iter-126 flock below is released as soon as Case 5 restores the doc
# inline, but the TRAP fires at process exit — outside the lock — so a
# legitimate rewrite that landed in between (a `--write` regeneration, or a
# sibling test's restore) was silently clobbered back to this test's stale
# snapshot. That took iter-113/114/115/117 down together and is why the suite
# reported anywhere from 94 to 109 passing. Observed twice on 2026-08-31, and
# it also left synthetic marker lines behind in the producer file.
#
# A cleanup handler must undo what it did, not restore a snapshot of a file it
# does not own. Keying off our own sentinel makes it race-free without holding
# the lock longer, idempotent, and a no-op when the inline restore already ran.
__iter115_restore_producer_and_doc_only_if_still_carrying_our_mutations() {
    __iter115_restore_producer_only_if_still_carrying_our_injection
    if [[ -s "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH" ]] &&
        grep -qF "$ITER115_DOC_MUTATION_SENTINEL" "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" 2>/dev/null; then
        # Iter-187: atomic rename, not cp -f — see the helper's header. The
        # trap fires at process exit, OUTSIDE the lock, so a torn write here
        # is visible to every other test still running.
        __iter115_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
            "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH"
    fi
    rm -f "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH"
}
trap __iter115_restore_producer_and_doc_only_if_still_carrying_our_mutations EXIT

# Iter-126 fix for iter-115↔iter-117 cross-test race condition under xargs -P
# parallelism (iter-75 parallel-suite runner). Case 5 below mutates the
# canonical on-disk doc transiently to verify the drift detector blocks
# release; the iter-117 Case 6 test reads --check on the same canonical
# on-disk doc to verify the no-drift idempotency invariant. When the two
# tests fire concurrently, iter-117 Case 6 fires inside iter-115 Case 5's
# mutation window and observes the synthetic mutation, producing a spurious
# DRIFT exit=1 from a test that passes standalone.
#
# Fix: wrap the mutation+check+restore window in flock against a fixed
# lock-file path. iter-117 Case 6 acquires the same lock, so the two tests
# serialize without affecting overall suite parallelism (only these two
# tests block on the shared lock). Lock-file path is process-shared at
# /tmp/cc-skills-iter113-on-disk-doc-mutation-window-serialization-flock
# — verbose and self-explanatory so future maintainers grepping for
# "iter-126" or "doc-mutation-window-serialization" find the rationale.
touch "$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
exec 9<>"$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
# Acquire exclusive lock for the mutation+check+restore atomic window.
# Use Python's fcntl.flock as the portable cross-Mac/Linux shell primitive
# (macOS BSD lacks the GNU `flock` CLI util; Python's fcntl module is
# always available since 1.x). The lock is bound to fd 9 and released
# automatically when fd 9 closes (i.e., when the test process exits) OR
# when we explicitly release it after the restore.
python3 -c '
import fcntl, sys, os
fd = int(sys.argv[1])
fcntl.flock(fd, fcntl.LOCK_EX)
' 9 <&9

cp "$ITER113_GENERATED_ON_DISK_DOC_ABSOLUTE_PATH" "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH"
# Iter-187: stage the mutated doc, then rename it into place, so the doc is
# only ever observable as fully-canonical or fully-mutated. The previous
# `>>` pair also left an intermediate "canonical + blank line" state.
ITER115_MUTATED_DOC_STAGING_FILE=$(mktemp -t iter115-mutated-doc-XXXXXX.md)
{
    cat "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH"
    echo ""
    echo "$ITER115_DOC_MUTATION_SENTINEL — verifying --check exits non-zero (restored by trap)"
} > "$ITER115_MUTATED_DOC_STAGING_FILE"
__iter115_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
    "$ITER115_MUTATED_DOC_STAGING_FILE"
rm -f "$ITER115_MUTATED_DOC_STAGING_FILE"

set +e
ITER113_DRIFT_CHECK_OUTPUT_WITH_SYNTHETIC_DOC_MUTATION=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
ITER113_DRIFT_CHECK_EXIT_CODE_WITH_SYNTHETIC_DOC_MUTATION=$?
set -e

# Restore immediately so subsequent cases (and the rest of the test suite) see clean state
__iter115_atomically_replace_canonical_on_disk_doc_via_same_directory_rename \
    "$ITER113_ON_DISK_DOC_BACKUP_ABSOLUTE_PATH"

# Iter-126 release the exclusive mutation-window flock now that the on-disk
# doc is back to its canonical state, so parallel readers can proceed.
#
# Iter-187: immediately re-acquire it SHARED, because Case 6 below runs
# another `--check` against the shared doc and would otherwise read
# iter-113 Case 7's mutation window as a spurious DRIFT — the same
# cross-test race iter-126 fixed for iter-117 Case 6 but never applied to
# this site. Full release then fresh acquisition, never an in-place
# LOCK_EX → LOCK_SH juggle interleaved with another process's upgrade.
exec 9<&-
exec 9<>"$ITER126_ON_DISK_DOC_MUTATION_WINDOW_SERIALIZATION_FLOCK_FILE"
python3 -c '
import fcntl, sys
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_SH)
' 9 <&9

if [[ "$ITER113_DRIFT_CHECK_EXIT_CODE_WITH_SYNTHETIC_DOC_MUTATION" -ne 0 ]] && \
   [[ "$ITER113_DRIFT_CHECK_OUTPUT_WITH_SYNTHETIC_DOC_MUTATION" == *"DRIFT"* ]]; then
    assert_passes "Case 5: generator --check exits non-zero ($ITER113_DRIFT_CHECK_EXIT_CODE_WITH_SYNTHETIC_DOC_MUTATION) AND emits 'DRIFT' signal on injected doc mutation (preflight Check 4u would correctly trigger exit 1)"
else
    assert_fails "Case 5: generator --check failed to detect mutation (exit=$ITER113_DRIFT_CHECK_EXIT_CODE_WITH_SYNTHETIC_DOC_MUTATION, output omits DRIFT signal)"
fi

# ─── Case 6: --check mode exits zero AND emits 'no drift' on restored baseline ───

set +e
ITER113_DRIFT_CHECK_OUTPUT_ON_RESTORED_BASELINE=$(bash "$ITER113_DOC_GENERATOR_ABSOLUTE_PATH" --check 2>&1)
ITER113_DRIFT_CHECK_EXIT_CODE_ON_RESTORED_BASELINE=$?
set -e

if [[ "$ITER113_DRIFT_CHECK_EXIT_CODE_ON_RESTORED_BASELINE" -eq 0 ]] && \
   [[ "$ITER113_DRIFT_CHECK_OUTPUT_ON_RESTORED_BASELINE" == *"no drift"* ]]; then
    assert_passes "Case 6: generator --check exits zero AND emits 'no drift' signal on restored baseline (no false-positive release blocks)"
else
    assert_fails "Case 6: post-restoration --check did NOT report clean state (exit=$ITER113_DRIFT_CHECK_EXIT_CODE_ON_RESTORED_BASELINE) — restoration may have failed OR generator is flaky"
fi

# Iter-187: last read of the shared on-disk doc is done — release the shared
# lock so the other tests' exclusive mutation windows can proceed.
exec 9<&-

# ─── Case 7: preflight wraps both audit tasks (post-iter-134: via parallel pre-warm metadata array) ───
#
# The strict-promoted preflight stanzas invoke the audit tasks indirectly.
# Pre-iter-134: inline `mise run <task-name>` invocations within each
# Check 4t/4u block. Post-iter-134: TAB-separated records in
# iter134_parallelizable_preflight_audit_metadata_records that the
# Phase-A parallel pre-warm fan-out reads and dispatches to xargs -P
# workers. Either form satisfies the underlying invariant: the audit
# task name appears verbatim in the preflight script. Verify the
# task-name references match the actual task file basenames so a future
# rename of either task file is caught at test time, not at next
# preflight invocation.
#
# Implementation: grep -qF on just the task name (no `mise run` prefix).
# Task names are 90+ chars of discriminating kebab-case; the chance of
# coincidental substring match in unrelated context is vanishingly low.
# This grep matches both:
#   - Legacy `mise run <task>` form (any remaining)
#   - Post-iter-134 metadata-array TAB-separated record form

EXPECTED_ITER111_MISE_TASK_NAME="audit-marketplace-wide-producer-escape-hatch-marker-typo-detection-against-canonical-iter111-registry"
EXPECTED_ITER113_MISE_TASK_NAME="generate-marketplace-escape-hatch-marker-reference-documentation-from-iter111-canonical-registry"

if grep -qF "$EXPECTED_ITER111_MISE_TASK_NAME" "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH" && \
   grep -qF "$EXPECTED_ITER113_MISE_TASK_NAME" "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 7: preflight references both iter-111 audit task + iter-113 generator task via their exact basenames (post-iter-134-aware: matches both legacy 'mise run <task>' form AND iter-134 parallel-pre-warm metadata-array record form; rename would fail this test)"
else
    assert_fails "Case 7: preflight task-name references drift from actual task file basenames"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-115 regression — Summary"
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
echo "  🚀 Iter-115 strict-promotion verified: Check 4t (iter-111 producer-marker"
echo "     typo audit) and Check 4u (iter-113 registry-to-docs drift detector)"
echo "     are now release-blocking. The 3-check escape-hatch-marker preflight"
echo "     triplet (4s consumer-STRICT + 4t producer-STRICT + 4u doc-drift-STRICT)"
echo "     is now uniformly enforced — the marketplace's escape-hatch lifecycle"
echo "     is fully covered at release time across producer, consumer, and"
echo "     operator-documentation dimensions."
echo "  🚀 Iter-116+ candidates:"
echo "     - Add a reverse-search registry accessor"
echo "       lookupCanonicalRegistryEntryByConsumerHookOrAuditTaskSourceFileRelativePath"
echo "       (suppression-target → marker discovery, across BOTH registries)"
echo "     - Add an audit task verifying every entry's"
echo "       humanReadableEscapeHatchDescriptionForOperatorDocumentation"
echo "       references the actual hook/task it suppresses (no stale descriptions"
echo "       after a hook rename)"
