#!/usr/bin/env bash
#MISE description="Iter-193 regression test pinning the iter-160 doctor's repo-root resolution. Pre-iter-193 the doctor resolved its root with 'git rev-parse --show-toplevel', i.e. from the CALLER'S working directory rather than from its own location, so invoking it from any other git repository made every derived shared-library path miss and produced verdict=TOOLKIT_BROKEN with critical_failed=13 about a perfectly healthy toolkit. That is the same signature the iter-160 regression test's C3/C4 emit, so a wrong cwd was indistinguishable in the log from the still-open intermittent gate failure. Asserts (a) the root-resolution block derives from BASH_SOURCE and no longer calls git rev-parse, (b) end-to-end: invoked with cwd inside a THROWAWAY git repo, all four shared-library CRITICAL checks (iter-155, iter-161, iter-162, iter-164) still report outcome=pass — these are the checks that false-failed before, (c) control: invoked from the repo root the verdict is still TOOLKIT_HEALTHY, (d) a repo-root OVERRIDE pointing somewhere that is not a cc-skills checkout now exits 2 with a harness-error diagnostic instead of reporting TOOLKIT_BROKEN, (e) bash -n clean."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

ITER193_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ITER193_REPO_ROOT"

ITER193_DOCTOR_ABSOLUTE_PATH="$ITER193_REPO_ROOT/scripts/iter160-operator-facing-commits-arc-self-diagnosis-task-checking-each-iter150-through-iter158-tool-for-presence-executability-and-functional-correctness-with-per-check-wall-clock-latency-reporting-and-json-mode.sh"

ITER193_ASSERTIONS_EVALUATED=0
ITER193_ASSERTIONS_FAILED=0
iter193_pass() { ITER193_ASSERTIONS_EVALUATED=$((ITER193_ASSERTIONS_EVALUATED + 1)); echo "  ✓ $1"; }
iter193_fail() {
    ITER193_ASSERTIONS_EVALUATED=$((ITER193_ASSERTIONS_EVALUATED + 1))
    ITER193_ASSERTIONS_FAILED=$((ITER193_ASSERTIONS_FAILED + 1))
    echo "  ✗ $1"
}

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-193: the doctor diagnoses its own tree, not the caller's cwd"
echo "═══════════════════════════════════════════════════════════════════════════════"

if [[ ! -x "$ITER193_DOCTOR_ABSOLUTE_PATH" ]]; then
    iter193_fail "PRECONDITION: iter-160 doctor missing or not executable at $ITER193_DOCTOR_ABSOLUTE_PATH"
    echo "  Test cannot proceed."
    exit 1
fi

# ─── Group A: the resolution block is BASH_SOURCE-anchored ──────────────────
echo ""
echo "GROUP A (2 assertions): root resolution is anchored to the script, not the cwd"

# The whole defect is one line, so the assertion is on that line's SHAPE rather
# than on a banner comment a refactor could carry along unchanged.
# shellcheck disable=SC2016
# SC2016 is the point: this is a LITERAL source line being searched for, so the
# `$(...)` and `${...}` inside it must reach grep unexpanded.
if grep -qF 'ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"' "$ITER193_DOCTOR_ABSOLUTE_PATH"; then
    iter193_pass "A1: root derives from \${BASH_SOURCE[0]} (iter-176 pattern)"
else
    iter193_fail "A1: the BASH_SOURCE-anchored root-resolution line is gone — the doctor may be reading the caller's cwd again"
fi

# `git rev-parse` legitimately remains inside Check 7, which is ABOUT the
# current repo. What must never come back is a rev-parse feeding the ROOT.
#
# NOT anchored with `^`. The first draft was, and it scored the pre-fix source
# 0 — a green verdict on the exact defect it exists to catch — because the
# offending line reads `    if ! ITER160_..._PATH="$(git rev-parse …)"`, with
# the assignment mid-line. Negative-controlled against `git show HEAD:` before
# being trusted: pre-fix must score 1, post-fix 0.
ITER193_REVPARSE_FEEDING_ROOT=$(
    awk '/^[[:space:]]*#/ { next }
         /ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH=/ && /git rev-parse/ { n++ }
         END { print n+0 }' \
        "$ITER193_DOCTOR_ABSOLUTE_PATH"
)
if [[ "$ITER193_REVPARSE_FEEDING_ROOT" -eq 0 ]]; then
    iter193_pass "A2: no assignment to the repo-root variable is fed by git rev-parse (found $ITER193_REVPARSE_FEEDING_ROOT)"
else
    iter193_fail "A2: $ITER193_REVPARSE_FEEDING_ROOT assignment(s) to the repo-root variable still call git rev-parse — cwd-dependence reintroduced"
fi

# ─── Group B: end-to-end from a FOREIGN git repository ──────────────────────
echo ""
echo "GROUP B (2 assertions): a foreign cwd cannot make the shared libraries vanish"

ITER193_FOREIGN_GIT_REPO_TEMP_DIR=$(mktemp -d -t iter193-foreign-repo-XXXXXX)
trap 'rm -rf "$ITER193_FOREIGN_GIT_REPO_TEMP_DIR"' EXIT
(
    cd "$ITER193_FOREIGN_GIT_REPO_TEMP_DIR"
    git init -q
    git config user.email "iter193-foreign-repo-probe@example.com"
    git config user.name "iter193-foreign-repo-probe"
    git commit --allow-empty -q -m "chore: iter-193 foreign-repo probe baseline"
) >/dev/null 2>&1

ITER193_FOREIGN_CWD_JSON=$(
    cd "$ITER193_FOREIGN_GIT_REPO_TEMP_DIR" && "$ITER193_DOCTOR_ABSOLUTE_PATH" --json 2>/dev/null || true
)

# These four are pure shared-library sourcing checks. They have nothing to do
# with the caller's repository, so their outcome is cwd-invariant BY DEFINITION
# — which is exactly why all four false-failed before iter-193, and why they are
# the right probe. Deliberately NOT asserting the whole verdict here: three
# other CRITICAL checks (iter-150 renderer, iter-152 dashboard, iter-157
# installer) are legitimately ABOUT whichever repo you are standing in, so
# pinning the aggregate would be pinning unrelated behaviour.
ITER193_LIBRARY_CHECK_REPORT=$(
    printf '%s' "$ITER193_FOREIGN_CWD_JSON" | python3 -c '
import json, sys
CWD_INVARIANT_SHARED_LIBRARY_CHECK_IDENTIFIERS = {
    "iter155_shared_json_escape_library",
    "iter161_semver_bump_classifier_library",
    "iter162_breaking_change_footer_detector_library",
    "iter164_semver_next_version_resolver_library",
}
try:
    parsed = json.load(sys.stdin)
except Exception as parse_error:
    print("JSON-UNPARSEABLE: %s" % parse_error)
    sys.exit(0)
seen = {}
for record in parsed.get("checks", []):
    if record.get("identifier") in CWD_INVARIANT_SHARED_LIBRARY_CHECK_IDENTIFIERS:
        seen[record["identifier"]] = record.get("outcome")
missing = sorted(CWD_INVARIANT_SHARED_LIBRARY_CHECK_IDENTIFIERS - set(seen))
if missing:
    print("MISSING-CHECKS: %s" % ", ".join(missing))
    sys.exit(0)
bad = sorted(k for k, v in seen.items() if v != "pass")
print("ALL-PASS" if not bad else "NOT-PASS: %s" % ", ".join("%s=%s" % (k, seen[k]) for k in bad))
' 2>&1 || true
)

if [[ "$ITER193_LIBRARY_CHECK_REPORT" == "ALL-PASS" ]]; then
    iter193_pass "B1: from a foreign git repo, all 4 cwd-invariant shared-library CRITICAL checks still pass"
else
    iter193_fail "B1: from a foreign git repo the shared-library checks report: $ITER193_LIBRARY_CHECK_REPORT"
fi

ITER193_CONTROL_JSON=$("$ITER193_DOCTOR_ABSOLUTE_PATH" --json 2>/dev/null || true)
if [[ "$ITER193_CONTROL_JSON" == *'"verdict": "TOOLKIT_HEALTHY"'* ]]; then
    iter193_pass "B2: control — from the cc-skills root the verdict is still TOOLKIT_HEALTHY"
else
    iter193_fail "B2: control run from the repo root is NOT TOOLKIT_HEALTHY (the iter-193 change may have broken the normal path)"
fi

# ─── Group C: a bad override is a HARNESS error, not a toolkit verdict ──────
echo ""
echo "GROUP C (2 assertions): an unusable root fails loudly instead of blaming the toolkit"

ITER193_BAD_OVERRIDE_EXIT_CODE=0
ITER193_BAD_OVERRIDE_OUTPUT=$(
    ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH_OVERRIDE="$ITER193_FOREIGN_GIT_REPO_TEMP_DIR" \
        "$ITER193_DOCTOR_ABSOLUTE_PATH" --json 2>&1
) || ITER193_BAD_OVERRIDE_EXIT_CODE=$?

if [[ "$ITER193_BAD_OVERRIDE_EXIT_CODE" -eq 2 ]]; then
    iter193_pass "C1: a root override that is not a cc-skills checkout exits 2 (harness error, distinct from 1 = toolkit broken)"
else
    iter193_fail "C1: bad root override exited $ITER193_BAD_OVERRIDE_EXIT_CODE (expected 2)"
fi

# Matched on the JSON VERDICT FIELD, not on the bare token. The first draft of
# this assertion looked for the token anywhere in the output and failed against
# a correct fix, because the harness-error message itself explains that it is
# NOT reporting TOOLKIT_BROKEN — the word appears in prose that proves the
# opposite of what the matcher concluded. Anchored on a positive sibling first,
# per the 2026-06-10 "negative-only assertions are regression-blind" rule.
if [[ "$ITER193_BAD_OVERRIDE_OUTPUT" == *"not a cc-skills checkout"* ]] \
   && [[ "$ITER193_BAD_OVERRIDE_OUTPUT" != *'"verdict"'* ]]; then
    iter193_pass "C2: the bad-override path names itself and emits no verdict field at all"
else
    iter193_fail "C2: bad override still produced a verdict field or lost its diagnostic"
fi

# ─── Group D: the doctor still parses ───────────────────────────────────────
echo ""
echo "GROUP D (1 assertion): syntax"

if bash -n "$ITER193_DOCTOR_ABSOLUTE_PATH" 2>/dev/null; then
    iter193_pass "D1: iter-160 doctor passes bash -n"
else
    iter193_fail "D1: iter-160 doctor fails bash -n"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER193_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-193 REGRESSION TEST: ${ITER193_ASSERTIONS_EVALUATED}/${ITER193_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-193 REGRESSION TEST: $((ITER193_ASSERTIONS_EVALUATED - ITER193_ASSERTIONS_FAILED))/${ITER193_ASSERTIONS_EVALUATED} assertions passed, ${ITER193_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
