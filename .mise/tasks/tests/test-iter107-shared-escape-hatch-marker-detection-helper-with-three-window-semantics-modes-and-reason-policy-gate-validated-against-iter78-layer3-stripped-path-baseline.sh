#!/usr/bin/env bash
#MISE description="Iter-107 regression test for the shared escape-hatch-marker detection helper. Verifies (1) helper file exists with all 3 documented exports (config type, single-line detector, file-wide detector); (2) iter-78 layer3-stripped-path-guard has migrated to the helper (its hand-rolled regex + window loop replaced by a single helper call); (3) iter-78 regression test still PASSES (behavior-preserving migration confirmed); (4) inventory audit exists + is executable + reports the iter-78 migration; (5) helper SAME_LINE_ONLY mode works (programmatic probe); (6) helper SAME_LINE_OR_PRECEDING_N_LINES mode honors the N-line window boundary; (7) helper FILE_WIDE mode + hasFileWideEscapeHatchMarkerInContent convenience wrapper work; (8) reason-policy gate enforces ≥10-char reason after colon when configured (rejects bare marker, accepts marker-with-reason)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
ITER107_SHARED_HELPER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts"
ITER78_GUARD_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts"
ITER78_REGRESSION_TEST_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/tests/test-pretooluse-iter78-layer3-stripped-path-edit-time-guard-classifies-allowlisted-vs-stripped-segments-honors-escape-hatch-with-belt-and-suspenders-github37210-defense.sh"
ITER107_INVENTORY_AUDIT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-with-recommendation-to-migrate-hand-rolled-patterns-to-iter107-canonical-shared-helper.sh"

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-107 shared escape-hatch-marker detection helper regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: shared helper file exists with all 3 documented exports ─────
if [[ -f "$ITER107_SHARED_HELPER_ABSOLUTE_PATH" ]] && \
   grep -qE "^export type EscapeHatchMarkerWindowSemanticsMode" "$ITER107_SHARED_HELPER_ABSOLUTE_PATH" && \
   grep -qE "^export interface EscapeHatchMarkerDetectionConfiguration" "$ITER107_SHARED_HELPER_ABSOLUTE_PATH" && \
   grep -qE "^export function detectEscapeHatchMarkerCoveringTargetSourceLine" "$ITER107_SHARED_HELPER_ABSOLUTE_PATH" && \
   grep -qE "^export function hasFileWideEscapeHatchMarkerInContent" "$ITER107_SHARED_HELPER_ABSOLUTE_PATH"; then
    assert_passes "Case 1: iter-107 shared helper file exists with all 4 documented exports (window-semantics-mode type + configuration interface + per-line detector + file-wide detector)"
else
    assert_fails "Case 1: iter-107 shared helper missing or missing required exports"
fi

# ─── Case 2: iter-78 guard has migrated to the shared helper ─────────────
if grep -q "from \"./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107" "$ITER78_GUARD_ABSOLUTE_PATH" && \
   grep -q "detectEscapeHatchMarkerCoveringTargetSourceLine" "$ITER78_GUARD_ABSOLUTE_PATH" && \
   ! grep -q "ESCAPE_HATCH_MARKER_MIN_TEN_CHAR_REASON_REGEX" "$ITER78_GUARD_ABSOLUTE_PATH"; then
    assert_passes "Case 2: iter-78 layer3-stripped-path-guard migrated to shared helper (hand-rolled regex constant removed + helper imported + helper invoked)"
else
    assert_fails "Case 2: iter-78 migration incomplete (hand-rolled regex still present OR helper import missing OR helper call missing)"
fi

# ─── Case 3: iter-78 regression test STILL PASSES (behavior-preserving) ──
set +e
iter78_regression_output=$(bash "$ITER78_REGRESSION_TEST_ABSOLUTE_PATH" 2>&1)
iter78_regression_exit_code=$?
set -e
if [[ "$iter78_regression_exit_code" == "0" ]] && [[ "$iter78_regression_output" == *"all 7 assertions passed"* ]]; then
    assert_passes "Case 3: iter-78 regression test still PASSES (behavior-preserving iter-107 migration confirmed)"
else
    assert_fails "Case 3: iter-78 regression test broken by iter-107 migration (exit=$iter78_regression_exit_code)"
fi

# ─── Case 4: iter-107 inventory audit exists + executable + reports iter-78 migration ─
if [[ -x "$ITER107_INVENTORY_AUDIT_ABSOLUTE_PATH" ]]; then
    set +e
    inventory_audit_output=$(bash "$ITER107_INVENTORY_AUDIT_ABSOLUTE_PATH" 2>&1)
    inventory_audit_exit_code=$?
    set -e
    if [[ "$inventory_audit_exit_code" == "0" ]] && [[ "$inventory_audit_output" == *"pretooluse-iter78-layer3-stripped-path-edit-time-guard"* ]] && [[ "$inventory_audit_output" == *"AUDIT PASSED"* ]]; then
        assert_passes "Case 4: iter-107 inventory audit exists + reports iter-78 as MIGRATED (informational pass)"
    else
        assert_fails "Case 4: iter-107 inventory audit ran but did NOT report iter-78 as MIGRATED (exit=$inventory_audit_exit_code)"
    fi
else
    assert_fails "Case 4: iter-107 inventory audit task missing or not executable"
fi

# ─── Case 5-8: programmatic probes against the helper API via bun --eval ─
# Build a temp bun script that imports the helper + exercises each mode.

PROBE_SCRIPT_DIRECTORY=$(mktemp -d -t iter107-probe-XXXXXX)
trap 'rm -rf "$PROBE_SCRIPT_DIRECTORY"' EXIT

cat > "$PROBE_SCRIPT_DIRECTORY/probe.ts" <<EOF
import {
  detectEscapeHatchMarkerCoveringTargetSourceLine,
  hasFileWideEscapeHatchMarkerInContent,
} from "$ITER107_SHARED_HELPER_ABSOLUTE_PATH";

let allTestsPassed = true;

// Probe 5: SAME_LINE_ONLY
const sameLineOnlyResult_markerOnSameLine =
  detectEscapeHatchMarkerCoveringTargetSourceLine(
    ["allowed-line", "violation-line # FOO-OK", "another-line"],
    1,
    {
      markerNameTokenIncludingSuffix: "FOO-OK",
      windowSemanticsMode: "SAME_LINE_ONLY",
    },
  );
const sameLineOnlyResult_markerOnPrecedingLine =
  detectEscapeHatchMarkerCoveringTargetSourceLine(
    ["# FOO-OK", "violation-line", "another-line"],
    1,
    {
      markerNameTokenIncludingSuffix: "FOO-OK",
      windowSemanticsMode: "SAME_LINE_ONLY",
    },
  );
if (
  sameLineOnlyResult_markerOnSameLine === true &&
  sameLineOnlyResult_markerOnPrecedingLine === false
) {
  console.log("PROBE-5-PASS: SAME_LINE_ONLY mode works (same line YES, preceding line NO)");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-5-FAIL: same-line=\${sameLineOnlyResult_markerOnSameLine} preceding=\${sameLineOnlyResult_markerOnPrecedingLine}\`);
}

// Probe 6: SAME_LINE_OR_PRECEDING_N_LINES (N=3, iter-78 default)
const precedingNResult_markerInWindow =
  detectEscapeHatchMarkerCoveringTargetSourceLine(
    ["# BAR-OK", "line-1", "line-2", "violation-line", "outside"],
    3,
    {
      markerNameTokenIncludingSuffix: "BAR-OK",
      windowSemanticsMode: "SAME_LINE_OR_PRECEDING_N_LINES",
      precedingLineLookbackWindowLineCount: 3,
    },
  );
const precedingNResult_markerOutsideWindow =
  detectEscapeHatchMarkerCoveringTargetSourceLine(
    ["# BAR-OK", "line-1", "line-2", "line-3", "violation-line"],
    4,
    {
      markerNameTokenIncludingSuffix: "BAR-OK",
      windowSemanticsMode: "SAME_LINE_OR_PRECEDING_N_LINES",
      precedingLineLookbackWindowLineCount: 3,
    },
  );
if (precedingNResult_markerInWindow === true && precedingNResult_markerOutsideWindow === false) {
  console.log("PROBE-6-PASS: SAME_LINE_OR_PRECEDING_N_LINES mode honors N-line window boundary");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-6-FAIL: in-window=\${precedingNResult_markerInWindow} outside-window=\${precedingNResult_markerOutsideWindow}\`);
}

// Probe 7: FILE_WIDE + convenience wrapper
const fileWideResult_present = hasFileWideEscapeHatchMarkerInContent(
  "lots of content\\nmore content\\n# BAZ-OK\\neven more\\n",
  { markerNameTokenIncludingSuffix: "BAZ-OK" },
);
const fileWideResult_absent = hasFileWideEscapeHatchMarkerInContent(
  "lots of content\\nmore content\\nno marker here\\n",
  { markerNameTokenIncludingSuffix: "BAZ-OK" },
);
if (fileWideResult_present === true && fileWideResult_absent === false) {
  console.log("PROBE-7-PASS: FILE_WIDE mode + convenience wrapper work");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-7-FAIL: present=\${fileWideResult_present} absent=\${fileWideResult_absent}\`);
}

// Probe 8: ≥10-char reason policy gate
const reasonGated_bareMarker = hasFileWideEscapeHatchMarkerInContent(
  "# QUX-OK\\n",
  {
    markerNameTokenIncludingSuffix: "QUX-OK",
    requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
  },
);
const reasonGated_shortReason = hasFileWideEscapeHatchMarkerInContent(
  "# QUX-OK: tiny\\n",
  {
    markerNameTokenIncludingSuffix: "QUX-OK",
    requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
  },
);
const reasonGated_validReason = hasFileWideEscapeHatchMarkerInContent(
  "# QUX-OK: this is a sufficient reason explanation\\n",
  {
    markerNameTokenIncludingSuffix: "QUX-OK",
    requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
  },
);
if (reasonGated_bareMarker === false && reasonGated_shortReason === false && reasonGated_validReason === true) {
  console.log("PROBE-8-PASS: ≥10-char reason policy rejects bare marker AND short reason; accepts sufficient reason");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-8-FAIL: bare=\${reasonGated_bareMarker} short=\${reasonGated_shortReason} valid=\${reasonGated_validReason}\`);
}

// Probe 9 (iter-108): caseSensitivityMode CASE_SENSITIVE default rejects
// lowercase, CASE_INSENSITIVE accepts lowercase.
const caseSensitive_lowercaseMarker_strict = hasFileWideEscapeHatchMarkerInContent(
  "# foo-ok\\n",
  {
    markerNameTokenIncludingSuffix: "FOO-OK",
    caseSensitivityMode: "CASE_SENSITIVE",
  },
);
const caseSensitive_lowercaseMarker_lenient = hasFileWideEscapeHatchMarkerInContent(
  "# foo-ok\\n",
  {
    markerNameTokenIncludingSuffix: "FOO-OK",
    caseSensitivityMode: "CASE_INSENSITIVE",
  },
);
const caseSensitive_uppercaseMarker_strict = hasFileWideEscapeHatchMarkerInContent(
  "# FOO-OK\\n",
  {
    markerNameTokenIncludingSuffix: "FOO-OK",
    caseSensitivityMode: "CASE_SENSITIVE",
  },
);
if (caseSensitive_lowercaseMarker_strict === false && caseSensitive_lowercaseMarker_lenient === true && caseSensitive_uppercaseMarker_strict === true) {
  console.log("PROBE-9-PASS: caseSensitivityMode CASE_SENSITIVE rejects lowercase; CASE_INSENSITIVE accepts lowercase; uppercase always accepted");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-9-FAIL: lower-strict=\${caseSensitive_lowercaseMarker_strict} lower-lenient=\${caseSensitive_lowercaseMarker_lenient} upper-strict=\${caseSensitive_uppercaseMarker_strict}\`);
}

// Probe 10 (iter-110): multi-marker composition — the same hook can call the
// helper with TWO different marker configurations (opt-out + opt-in), each
// matching independently. Documented by iter-109's cargo-tty-guard migration
// (CARGO-TTY-SKIP opt-out + CARGO-TTY-WRAP opt-in). Verifies the helper has
// no hidden global state and each call is independent.
const optOutConfig_skipMarker = {
  markerNameTokenIncludingSuffix: "FOO-TTY-SKIP",
  caseSensitivityMode: "CASE_INSENSITIVE" as const,
};
const optInConfig_wrapMarker = {
  markerNameTokenIncludingSuffix: "FOO-TTY-WRAP",
  caseSensitivityMode: "CASE_INSENSITIVE" as const,
};
const commandWithOptOutOnly = "cargo bench --bench foo & # FOO-TTY-SKIP";
const commandWithOptInOnly = "cargo bench --bench foo # FOO-TTY-WRAP";
const commandWithNeither = "cargo bench --bench foo &";
const multiMarker_optOutDetectsSkip = hasFileWideEscapeHatchMarkerInContent(commandWithOptOutOnly, optOutConfig_skipMarker);
const multiMarker_optOutMissesWrap = hasFileWideEscapeHatchMarkerInContent(commandWithOptInOnly, optOutConfig_skipMarker);
const multiMarker_optInDetectsWrap = hasFileWideEscapeHatchMarkerInContent(commandWithOptInOnly, optInConfig_wrapMarker);
const multiMarker_optInMissesSkip = hasFileWideEscapeHatchMarkerInContent(commandWithOptOutOnly, optInConfig_wrapMarker);
const multiMarker_neitherMatches_skip = hasFileWideEscapeHatchMarkerInContent(commandWithNeither, optOutConfig_skipMarker);
const multiMarker_neitherMatches_wrap = hasFileWideEscapeHatchMarkerInContent(commandWithNeither, optInConfig_wrapMarker);
if (
  multiMarker_optOutDetectsSkip === true &&
  multiMarker_optOutMissesWrap === false &&
  multiMarker_optInDetectsWrap === true &&
  multiMarker_optInMissesSkip === false &&
  multiMarker_neitherMatches_skip === false &&
  multiMarker_neitherMatches_wrap === false
) {
  console.log("PROBE-10-PASS: multi-marker composition works (helper has no hidden global state; SKIP and WRAP markers match independently per cargo-tty-guard iter-109 pattern)");
} else {
  allTestsPassed = false;
  console.log(\`PROBE-10-FAIL: skip-detects-skip=\${multiMarker_optOutDetectsSkip} skip-misses-wrap=\${multiMarker_optOutMissesWrap} wrap-detects-wrap=\${multiMarker_optInDetectsWrap} wrap-misses-skip=\${multiMarker_optInMissesSkip} neither-skip=\${multiMarker_neitherMatches_skip} neither-wrap=\${multiMarker_neitherMatches_wrap}\`);
}

if (!allTestsPassed) {
  process.exit(1);
}
EOF

set +e
probe_output=$(cd "$REPO_ROOT" && bun "$PROBE_SCRIPT_DIRECTORY/probe.ts" 2>&1)
probe_exit_code=$?
set -e

if [[ "$probe_output" == *"PROBE-5-PASS"* ]]; then
    assert_passes "Case 5: helper SAME_LINE_ONLY mode works (programmatic probe — marker on target line MATCHES, marker on preceding line does NOT)"
else
    assert_fails "Case 5: helper SAME_LINE_ONLY mode broken"
fi

if [[ "$probe_output" == *"PROBE-6-PASS"* ]]; then
    assert_passes "Case 6: helper SAME_LINE_OR_PRECEDING_N_LINES mode honors N-line window boundary (probe with N=3)"
else
    assert_fails "Case 6: helper preceding-N-lines window-boundary semantics broken"
fi

if [[ "$probe_output" == *"PROBE-7-PASS"* ]]; then
    assert_passes "Case 7: helper FILE_WIDE mode + hasFileWideEscapeHatchMarkerInContent convenience wrapper work"
else
    assert_fails "Case 7: helper FILE_WIDE mode or convenience wrapper broken"
fi

if [[ "$probe_output" == *"PROBE-8-PASS"* ]]; then
    assert_passes "Case 8: ≥10-char reason policy gate enforces correctly (rejects bare marker, rejects short reason, accepts ≥10-char reason)"
else
    assert_fails "Case 8: reason-policy gate broken (probe exit=$probe_exit_code, output=$probe_output)"
fi

if [[ "$probe_output" == *"PROBE-9-PASS"* ]]; then
    assert_passes "Case 9 (iter-108): caseSensitivityMode default CASE_SENSITIVE rejects lowercase; CASE_INSENSITIVE accepts lowercase (legacy /i compatibility for hooks being migrated from hand-rolled /i regexes)"
else
    assert_fails "Case 9: caseSensitivityMode mode-switch broken (probe exit=$probe_exit_code, output=$probe_output)"
fi

if [[ "$probe_output" == *"PROBE-10-PASS"* ]]; then
    assert_passes "Case 10 (iter-110): multi-marker composition works (helper has no hidden global state; SKIP and WRAP markers match independently — documents iter-109's cargo-tty-guard pattern as an API contract)"
else
    assert_fails "Case 10: multi-marker composition broken (probe exit=$probe_exit_code, output=$probe_output)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-107 regression — Summary"
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
echo "  🚀 Iter-107 canonical shared escape-hatch-marker detection helper"
echo "     established. Iter-78 layer3-stripped-path-guard migrated to the"
echo "     shared helper as proof-of-integration (behavior-preserving: iter-78"
echo "     regression test still passes 7/7)."
echo "  🚀 Iter-107 inventory audit task (informational, never blocks release)"
echo "     enumerates hand-rolled marker detection patterns + recommends"
echo "     migration. Future iters (108+) migrate the remaining ~8 hand-rolled"
echo "     consumers (file-size-guard, version-guard, native-binary-guard,"
echo "     process-storm-guard, cwd-deletion-guard, inline-ignore-guard,"
echo "     cargo-tty-guard, etc.) one by one with the same behavior-preserving"
echo "     pattern: replace regex literal + window loop with a single helper"
echo "     call configured from a per-hook configuration object."
echo "  🚀 Iter-108+ candidate: promote inventory audit from informational to"
echo "     strict-block once all hand-rolled implementations are migrated."
