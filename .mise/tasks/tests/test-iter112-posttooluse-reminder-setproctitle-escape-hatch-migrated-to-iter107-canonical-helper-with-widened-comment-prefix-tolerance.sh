#!/usr/bin/env bash
#MISE description="Iter-112 regression test: verifies (1) posttooluse-reminder.ts imports the iter-107 canonical helper; (2) raw fileContent.includes(...) substring check for SETPROCTITLE-OK is gone; (3) iter-110 strict audit recognizes posttooluse-reminder.ts as the ninth canonical cohort member; (4) iter-111 producer-marker registry's SETPROCTITLE-OK entry no longer carries the not-yet-migrated caveat; (5) widened-comment-prefix tolerance — pre-iter-112 detection required leading `# ` prefix; iter-112 also accepts `// `, `<!-- `, or no prefix (operator-friendly, matches the marketplace UPPER-KEBAB-CASE-substring convention used by the other 8 cohort members)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER112_MIGRATED_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-reminder.ts"
ITER107_SHARED_HELPER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts"
ITER111_REGISTRY_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"
ITER110_STRICT_INVENTORY_AUDIT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-with-recommendation-to-migrate-hand-rolled-patterns-to-iter107-canonical-shared-helper.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-112 posttooluse-reminder.ts SETPROCTITLE migration regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: posttooluse-reminder.ts imports the iter-107 canonical helper ─
if grep -q "from \"./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107" "$ITER112_MIGRATED_HOOK_ABSOLUTE_PATH" && \
   grep -q "hasFileWideEscapeHatchMarkerInContent" "$ITER112_MIGRATED_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 1: posttooluse-reminder.ts imports the iter-107 canonical helper and invokes hasFileWideEscapeHatchMarkerInContent"
else
    assert_fails "Case 1: posttooluse-reminder.ts missing helper import or missing helper invocation"
fi

# ─── Case 2: raw `.includes("# SETPROCTITLE-OK")` substring check is gone ──
# Strip line-leading `//` doc-comments (which legitimately describe the
# pre-iter-112 pattern as documentation), then check for the executable
# code pattern. The pre-iter-112 line was
#   `if (fileContent.includes("# SETPROCTITLE-OK")) return null;`
# at column-2 of an `if` statement, which the grep below targets via the
# leading-whitespace + `if` anchor.
NON_DOC_COMMENT_INCLUDES_CHECK_SURVIVOR_COUNT=$(grep -E '^\s+if\s*\(\s*fileContent\.includes\(' "$ITER112_MIGRATED_HOOK_ABSOLUTE_PATH" | grep -c 'SETPROCTITLE' || true)
if [[ "${NON_DOC_COMMENT_INCLUDES_CHECK_SURVIVOR_COUNT:-0}" -eq 0 ]]; then
    assert_passes "Case 2: raw fileContent.includes('# SETPROCTITLE-OK') substring check has been removed from executable code (doc-comment references describing the pre-iter-112 pattern are allowed and ignored by the grep filter)"
else
    assert_fails "Case 2: raw .includes() substring check still present in executable code ($NON_DOC_COMMENT_INCLUDES_CHECK_SURVIVOR_COUNT match(es))"
fi

# ─── Case 3: iter-110 strict audit lists posttooluse-reminder.ts in cohort ─
if grep -q "plugins/itp-hooks/hooks/posttooluse-reminder.ts" "$ITER110_STRICT_INVENTORY_AUDIT_ABSOLUTE_PATH"; then
    assert_passes "Case 3: iter-110 strict audit's canonical cohort array includes posttooluse-reminder.ts (ninth member)"
else
    assert_fails "Case 3: iter-110 strict audit cohort missing posttooluse-reminder.ts"
fi

# ─── Case 4: iter-111 registry SETPROCTITLE-OK entry updated ──────────────
# Pre-iter-112 description carried "as of iter-111 this marker is detected by
# `posttooluse-reminder.ts` via a raw `.includes()` substring check, NOT yet
# via the iter-107 canonical helper" caveat. Iter-112 must have removed it.
if ! grep -q "NOT yet via the iter-107 canonical helper" "$ITER111_REGISTRY_ABSOLUTE_PATH"; then
    assert_passes "Case 4: iter-111 registry's SETPROCTITLE-OK description no longer carries the iter-112-resolved 'not yet migrated' caveat"
else
    assert_fails "Case 4: iter-111 registry still carries the pre-iter-112 'not yet via the iter-107 canonical helper' caveat"
fi

# ─── Case 5: iter-110 strict audit passes with the 9-member cohort ────────
set +e
iter110_audit_output=$(bash "$ITER110_STRICT_INVENTORY_AUDIT_ABSOLUTE_PATH" 2>&1)
iter110_audit_exit_code=$?
set -e
if [[ "$iter110_audit_exit_code" == "0" ]] && [[ "$iter110_audit_output" == *"all 9 canonical cohort members import the shared helper"* ]]; then
    assert_passes "Case 5: iter-110 strict audit passes with the new 9-member canonical cohort (was 8 pre-iter-112)"
else
    assert_fails "Case 5: iter-110 strict audit did not recognize 9-member cohort (exit=$iter110_audit_exit_code)"
fi

# ─── Case 6: widened-comment-prefix tolerance via programmatic probe ──────
# Pre-iter-112 required the literal `# ` prefix to detect SETPROCTITLE-OK.
# Iter-112 accepts any prefix (or none) because the canonical helper does
# CASE_SENSITIVE pure substring matching. This is operator-friendly + matches
# the convention used by the other 8 cohort members (the UPPER-KEBAB-CASE
# marker convention never collides with code identifiers).
PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter112-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import { hasFileWideEscapeHatchMarkerInContent } from "$ITER107_SHARED_HELPER_ABSOLUTE_PATH";

const CONFIG = {
  markerNameTokenIncludingSuffix: "SETPROCTITLE-OK",
  caseSensitivityMode: "CASE_SENSITIVE" as const,
};

let allTestsPassed = true;

// Pre-iter-112 ALSO detected (must continue to detect):
const detected_with_hash_prefix = hasFileWideEscapeHatchMarkerInContent(
  "# SETPROCTITLE-OK — short-lived CLI, not a daemon.\\nimport sys\\n",
  CONFIG,
);

// Iter-112 NEW: also detects without leading # prefix:
const detected_with_slash_prefix = hasFileWideEscapeHatchMarkerInContent(
  "// SETPROCTITLE-OK — TypeScript bot wrapper.\\nimport bot from './bot';\\n",
  CONFIG,
);
const detected_with_html_prefix = hasFileWideEscapeHatchMarkerInContent(
  "<!-- SETPROCTITLE-OK — HTML doc fragment, never a daemon -->\\n<html>\\n",
  CONFIG,
);
const detected_without_any_prefix = hasFileWideEscapeHatchMarkerInContent(
  "SETPROCTITLE-OK marker on a bare line — still honored\\n",
  CONFIG,
);

// Must NOT detect when marker is absent:
const not_detected_when_absent = hasFileWideEscapeHatchMarkerInContent(
  "import time\\nwhile True:\\n    time.sleep(1)\\n",
  CONFIG,
);

// Must NOT detect a typo (CASE_SENSITIVE — typo doesn't match):
const not_detected_typo_lowercase = hasFileWideEscapeHatchMarkerInContent(
  "# setproctitle-ok — wrong case, should not match in CASE_SENSITIVE mode\\n",
  CONFIG,
);

if (
  detected_with_hash_prefix === true &&
  detected_with_slash_prefix === true &&
  detected_with_html_prefix === true &&
  detected_without_any_prefix === true &&
  not_detected_when_absent === false &&
  not_detected_typo_lowercase === false
) {
  console.log("PROBE-6-PASS: widened-comment-prefix tolerance works (# / // / <!-- / no-prefix all detected; absent + lowercase-typo correctly skipped)");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-6-FAIL: hash=\${detected_with_hash_prefix} slash=\${detected_with_slash_prefix} html=\${detected_with_html_prefix} none=\${detected_without_any_prefix} absent=\${not_detected_when_absent} typo=\${not_detected_typo_lowercase}\`);
}

if (!allTestsPassed) {
  process.exit(1);
}
EOF

set +e
probe_output=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
probe_exit_code=$?
set -e

if [[ "$probe_output" == *"PROBE-6-PASS"* ]]; then
    assert_passes "Case 6: widened-comment-prefix tolerance verified programmatically — all 4 prefix variants (#, //, <!--, none) honor the marker; absent + lowercase-typo correctly skipped"
else
    assert_fails "Case 6: widened-comment-prefix tolerance broken (probe exit=$probe_exit_code, output=$probe_output)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-112 regression — Summary"
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
echo "  🚀 Iter-112 closes the iter-111-surfaced registry-consistency gap:"
echo "     posttooluse-reminder.ts SETPROCTITLE detection now routes through"
echo "     the iter-107 canonical helper alongside the other 8 cohort members."
echo "     iter-110 canonical cohort expanded 8 → 9 (all members import the"
echo "     shared helper). Side benefit: widened comment-prefix tolerance"
echo "     (operators can now use #, //, <!-- -->, or no prefix at all)."
echo "  🚀 Iter-113+ candidates documented in HOOKS.md:"
echo "     - Extend iter-111 registry to cover the AUDIT-marker family"
echo "       (~10 markers consumed by .mise/ audit tasks, separate lifecycle)"
echo "     - Promote iter-111 audit (Check 4t) from informational to STRICT-BLOCK"
echo "       once the AUDIT-marker family is also registered"
