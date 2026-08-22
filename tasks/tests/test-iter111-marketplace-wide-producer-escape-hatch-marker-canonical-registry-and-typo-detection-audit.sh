#!/usr/bin/env bash
#MISE description="Iter-111 regression test for the marketplace-wide producer-side escape-hatch-marker canonical registry + typo-detection audit. Verifies (1) registry TypeScript file exists with all 3 documented exports (entry interface + registry array + lookup function); (2) registry contains all 12 iter-111 baseline markers (BASH-LAUNCHD-OK, CARGO-TTY-SKIP, CARGO-TTY-WRAP, CWD-DELETE-OK, FILE-SIZE-OK, INIT-MONOLITH-OK, INLINE-IGNORE-OK, LAYER3-STRIPPED-PATH-OK, PROCESS-STORM-OK, PUEUE-LOCAL-OK, SETPROCTITLE-OK, SSoT-OK); (3) typo-detection audit task exists and is executable; (4) audit passes against the live marketplace (every producer-side marker is registered); (5) audit correctly flags a synthetic injected typo (DELIBERATE-TYPO-FOR-ITER111-REGRESSION-TEST-OK in a temp producer file); (6) lookup helper function correctly resolves known markers + returns undefined for unknown."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"
ITER111_TYPO_DETECTION_AUDIT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-marketplace-wide-producer-escape-hatch-marker-typo-detection-against-canonical-iter111-registry.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-111 marketplace-wide producer-marker registry + typo audit regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: registry TypeScript file exists with documented exports ─────
if [[ -f "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" ]] && \
   grep -qE "^export interface MarketplaceWideEscapeHatchProducerMarkerCanonicalRegistryEntry" "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export const MARKETPLACE_WIDE_ESCAPE_HATCH_PRODUCER_MARKER_CANONICAL_REGISTRY" "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function lookupCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent" "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH" && \
   grep -qE "^export function listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically" "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-111 registry file exists with all 4 documented exports (entry interface + registry array + lookup function + list-all function)"
else
    assert_fails "Case 1: iter-111 registry file missing or missing required exports"
fi

# ─── Case 2: registry contains all 12 iter-111 baseline markers ──────────
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

MISSING_BASELINE_MARKER_COUNT=0
for baseline_marker_token in "${ITER111_BASELINE_MARKER_TOKENS[@]}"; do
    if ! grep -q "markerNameTokenIncludingSuffix: \"$baseline_marker_token\"" "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH"; then
        MISSING_BASELINE_MARKER_COUNT=$((MISSING_BASELINE_MARKER_COUNT + 1))
        echo "    (missing baseline marker: $baseline_marker_token)"
    fi
done

if [[ "$MISSING_BASELINE_MARKER_COUNT" -eq 0 ]]; then
    assert_passes "Case 2: registry contains all 12 iter-111 baseline markers"
else
    assert_fails "Case 2: registry missing $MISSING_BASELINE_MARKER_COUNT baseline marker(s)"
fi

# ─── Case 3: typo-detection audit task exists and is executable ──────────
if [[ -x "$ITER111_TYPO_DETECTION_AUDIT_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 3: iter-111 typo-detection audit task exists and is executable"
else
    assert_fails "Case 3: iter-111 typo-detection audit task missing or not executable"
fi

# ─── Case 4: audit passes against the live marketplace ───────────────────
set +e
live_audit_output=$(bash "$ITER111_TYPO_DETECTION_AUDIT_ABSOLUTE_PATH" 2>&1)
live_audit_exit_code=$?
set -e
if [[ "$live_audit_exit_code" == "0" ]] && [[ "$live_audit_output" == *"AUDIT PASSED"* ]]; then
    assert_passes "Case 4: live audit run passes (every producer-side marker is registered)"
else
    assert_fails "Case 4: live audit run did NOT pass (exit=$live_audit_exit_code)"
fi

# ─── Case 5: audit flags a synthetic injected typo ────────────────────────
# Plant a temporary producer file with a deliberate typo marker that is
# NOT in the registry, run the audit, verify it surfaces the typo, then
# clean up. The deliberate-typo marker name is intentionally distinctive
# so a grep across the marketplace will never find it elsewhere.
SYNTHETIC_TYPO_INJECTION_TARGET_DIRECTORY="$REPO_ROOT/plugins/agent-reach/scripts"
SYNTHETIC_TYPO_INJECTION_TARGET_FILENAME="iter111-synthetic-typo-fixture-for-producer-side-typo-detection-audit-regression-test-DO-NOT-COMMIT.sh"
SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH="$SYNTHETIC_TYPO_INJECTION_TARGET_DIRECTORY/$SYNTHETIC_TYPO_INJECTION_TARGET_FILENAME"
SYNTHETIC_TYPO_MARKER_TOKEN_DELIBERATELY_NOT_IN_REGISTRY="DELIBERATE-TYPO-FOR-ITER111-REGRESSION-TEST-OK"

# Cleanup trap (removes the synthetic file even on early exit)
cleanup_synthetic_typo_fixture() {
    rm -f "$SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH"
}
trap cleanup_synthetic_typo_fixture EXIT

cat > "$SYNTHETIC_TYPO_INJECTION_TARGET_ABSOLUTE_PATH" <<EOF
#!/usr/bin/env bash
# $SYNTHETIC_TYPO_MARKER_TOKEN_DELIBERATELY_NOT_IN_REGISTRY — iter-111 regression test fixture.
# This file is a temporary marker-injection target used ONLY by
# test-iter111-marketplace-wide-producer-escape-hatch-marker-canonical-registry-and-typo-detection-audit.sh
# and is removed by the test's cleanup trap. If you see this file in
# the working tree after the test has run, the cleanup trap failed.
echo "iter-111 synthetic typo fixture"
EOF

set +e
synthetic_typo_audit_output=$(bash "$ITER111_TYPO_DETECTION_AUDIT_ABSOLUTE_PATH" 2>&1)
synthetic_typo_audit_exit_code=$?
set -e

if [[ "$synthetic_typo_audit_output" == *"$SYNTHETIC_TYPO_MARKER_TOKEN_DELIBERATELY_NOT_IN_REGISTRY"* ]]; then
    assert_passes "Case 5: audit correctly flags a synthetic injected typo ($SYNTHETIC_TYPO_MARKER_TOKEN_DELIBERATELY_NOT_IN_REGISTRY) in a temp producer file"
else
    assert_fails "Case 5: audit did NOT surface the synthetic typo (exit=$synthetic_typo_audit_exit_code)"
fi

# Cleanup is also triggered by the trap, but doing it here lets Case 6
# run against a clean marketplace.
cleanup_synthetic_typo_fixture
trap - EXIT

# ─── Case 6: lookup helper resolves known + returns undefined for unknown ─
# Programmatic probe via bun: import the registry, call the lookup helper
# with a known marker and an unknown one, verify both behaviors.
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter111-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  lookupCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent,
  listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically,
} from "$ITER111_REGISTRY_TYPESCRIPT_ABSOLUTE_PATH";

let allTestsPassed = true;

// Probe 6a: lookup known marker returns full entry
const knownEntry = lookupCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent("PROCESS-STORM-OK");
if (
  knownEntry !== undefined &&
  knownEntry.markerNameTokenIncludingSuffix === "PROCESS-STORM-OK" &&
  knownEntry.consumerHookSourceFileRelativePath.includes("process-storm-patterns.mjs") &&
  knownEntry.caseSensitivityModeDeclaredAtConsumerCallSite === "CASE_INSENSITIVE" &&
  knownEntry.windowSemanticsModeDeclaredAtConsumerCallSite === "FILE_WIDE"
) {
  console.log("PROBE-6A-PASS: lookup of known marker PROCESS-STORM-OK returned a fully-populated entry");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-6A-FAIL: known-marker lookup returned \${JSON.stringify(knownEntry)}\`);
}

// Probe 6b: lookup unknown marker returns undefined
const unknownEntry = lookupCanonicalRegistryEntryByMarkerNameTokenOrUndefinedWhenAbsent("THIS-IS-NOT-A-REAL-MARKER-OK");
if (unknownEntry === undefined) {
  console.log("PROBE-6B-PASS: lookup of unknown marker returns undefined");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-6B-FAIL: unknown-marker lookup returned \${JSON.stringify(unknownEntry)} (expected undefined)\`);
}

// Probe 6c: list-all returns at least 12 sorted markers
const sortedMarkers = listAllCanonicalRegistryMarkerNameTokensSortedAlphabetically();
const sortedAlphabetically =
  sortedMarkers.length >= 12 &&
  sortedMarkers.every((marker, index) => {
    if (index === 0) return true;
    return sortedMarkers[index - 1].localeCompare(marker) <= 0;
  });
if (sortedAlphabetically) {
  console.log(\`PROBE-6C-PASS: list-all returns \${sortedMarkers.length} markers in alphabetical order\`);
} else {
  allTestsPassed = false;
  console.log(\`PROBE-6C-FAIL: list-all returned \${sortedMarkers.length} markers, sort-check failed\`);
}

if (!allTestsPassed) {
  process.exit(1);
}
EOF

set +e
probe_output=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
probe_exit_code=$?
set -e

if [[ "$probe_output" == *"PROBE-6A-PASS"* ]] && [[ "$probe_output" == *"PROBE-6B-PASS"* ]] && [[ "$probe_output" == *"PROBE-6C-PASS"* ]]; then
    assert_passes "Case 6: registry lookup + list-all helpers work correctly (known marker resolves, unknown returns undefined, list-all is sorted)"
else
    assert_fails "Case 6: registry helper probes failed (exit=$probe_exit_code, output=$probe_output)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-111 regression — Summary"
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
echo "  🚀 Iter-111 marketplace-wide producer-side escape-hatch-marker"
echo "     canonical registry + typo-detection audit established. Audit"
echo "     immediately surfaced one real unregistered marker on first run"
echo "     (SETPROCTITLE-OK in plugins/tlg/scripts/tg-cli.py, consumed by"
echo "     posttooluse-reminder.ts via raw \`.includes()\` substring check)."
echo "  🚀 Iter-112+ candidates documented:"
echo "     - Migrate posttooluse-reminder.ts setproctitle marker detection"
echo "       to the iter-107 canonical helper for behavioral consistency"
echo "     - Extend registry to cover the 10+ AUDIT-marker family"
echo "       (WILDCARD-MATCHER-OK, MATCHER-NO-MULTIEDIT-OK,"
echo "       POSTTOOLUSE-RAW-STDOUT-OK, HOOK-OUTPUT-SIZE-CAP-OK, etc.)"
echo "     - Promote iter-111 audit from informational to strict-block"
echo "       once registry coverage stabilizes"
