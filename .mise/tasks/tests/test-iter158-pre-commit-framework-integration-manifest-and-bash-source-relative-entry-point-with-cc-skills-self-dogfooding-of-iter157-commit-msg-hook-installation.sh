#!/usr/bin/env bash
#MISE description="Iter-158 regression test pinning the pre-commit framework integration: (a) .pre-commit-hooks.yaml manifest at repo root is valid YAML + declares the cc-skills-commits-advise-commit-msg hook with the canonical fields (id, name, entry, language=system, stages=[commit-msg], pass_filenames=true), (b) iter-158 entry-point script exists + bash-clean + shellcheck-clean + correctly classifies conformant/compound-prefix/missing-type/merge-bypass/breaking-change-shorthand subjects, (c) cc-skills self-dogfoods iter-157 by installing the commit-msg hook in its own .git/hooks/ (closes the dogfooding gap surfaced by the iter-158 adversarial audit)."
set -euo pipefail

ITER158_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER158_REPO_ROOT"

ITER158_ENTRY_POINT_RELATIVE_PATH="scripts/iter158-pre-commit-framework-entry-point-script-locating-iter153-advisor-via-bash-source-relative-path-resolution-for-consumption-by-polyglot-pre-commit-framework-from-its-hidden-cached-clone-of-cc-skills.sh"
ITER158_ENTRY_POINT_ABSOLUTE_PATH="$ITER158_REPO_ROOT/$ITER158_ENTRY_POINT_RELATIVE_PATH"
ITER158_PRECOMMIT_MANIFEST_ABSOLUTE_PATH="$ITER158_REPO_ROOT/.pre-commit-hooks.yaml"

ITER158_TOTAL_ASSERTIONS_EVALUATED=0
ITER158_TOTAL_ASSERTIONS_FAILED=0

iter158_assert_entry_point_exits_with_expected_code() {
    local human_readable_assertion_label="$1"
    local commit_msg_body="$2"
    local expected_exit_code="$3"
    ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
    local tmp_msg_file
    tmp_msg_file=$(mktemp -t iter158-regression-msg-XXXXXX)
    printf '%s\n' "$commit_msg_body" > "$tmp_msg_file"
    local actual_exit_code=0
    "$ITER158_ENTRY_POINT_ABSOLUTE_PATH" "$tmp_msg_file" >/dev/null 2>&1 \
        || actual_exit_code=$?
    rm -f "$tmp_msg_file"
    if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
        echo "  ✓ $human_readable_assertion_label (exit=$actual_exit_code)"
    else
        echo "  ✗ $human_readable_assertion_label (expected exit=$expected_exit_code, got $actual_exit_code)"
        ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-158 PRE-COMMIT-FRAMEWORK-INTEGRATION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Entry-point structurally valid ─────────────────────────────────
echo ""
echo "GROUP A (3 assertions): iter-158 entry-point structurally valid"

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER158_ENTRY_POINT_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: entry-point exists at iter-158 canonical path + executable"
else
    echo "  ✗ A1: entry-point missing or not executable"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER158_ENTRY_POINT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: entry-point passes bash -n syntax check"
else
    echo "  ✗ A2: entry-point FAILS bash -n"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER158_ENTRY_POINT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: entry-point passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: entry-point has shellcheck warnings"
        ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: .pre-commit-hooks.yaml manifest valid ──────────────────────────
echo ""
echo "GROUP B (6 assertions): .pre-commit-hooks.yaml manifest structurally valid"

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER158_PRECOMMIT_MANIFEST_ABSOLUTE_PATH" ]]; then
    echo "  ✓ B1: .pre-commit-hooks.yaml exists at repo root (pre-commit framework canonical discovery path)"
else
    echo "  ✗ B1: .pre-commit-hooks.yaml missing at repo root"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
# 2026-06-05: `uv run --python 3.14 --with pyyaml` — system python3 (3.13) lacks
# PyYAML; bare `python3 -c "import yaml"` false-negatives this check. Mirrors the
# repo-canonical uv pattern (plugins/pushover-commander/CLAUDE.md). Same for the
# field-probe below. Do NOT revert to bare python3.
if uv run --python 3.14 --with pyyaml python -c "import yaml; yaml.safe_load(open('$ITER158_PRECOMMIT_MANIFEST_ABSOLUTE_PATH'))" 2>/dev/null; then
    echo "  ✓ B2: .pre-commit-hooks.yaml parses as valid YAML"
else
    echo "  ✗ B2: .pre-commit-hooks.yaml does NOT parse as valid YAML"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_MANIFEST_FIELD_PROBE_OUTPUT=$(
    uv run --python 3.14 --with pyyaml python -c "
import yaml
with open('$ITER158_PRECOMMIT_MANIFEST_ABSOLUTE_PATH') as f:
    m = yaml.safe_load(f)
h = m[0]
print(f'id={h.get(\"id\")}')
print(f'language={h.get(\"language\")}')
print(f'stages={h.get(\"stages\")}')
print(f'pass_filenames={h.get(\"pass_filenames\")}')
print(f'entry_basename={h.get(\"entry\", \"\").split(\"/\")[-1]}')
" 2>/dev/null
)

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER158_MANIFEST_FIELD_PROBE_OUTPUT" == *"id=cc-skills-commits-advise-commit-msg"* ]]; then
    echo "  ✓ B3: manifest declares canonical hook id (cc-skills-commits-advise-commit-msg)"
else
    echo "  ✗ B3: manifest hook id is wrong or missing"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
# Note: corrected from `language=system` to `language=script` in iter-159 —
# pre-commit's `language: script` resolves the entry as a RELATIVE PATH within
# the cloned hook repo, which is the correct semantics for shipping a bash
# script alongside the manifest. `language: system` would have tried to
# resolve the entry on $PATH and silently failed at runtime.
if [[ "$ITER158_MANIFEST_FIELD_PROBE_OUTPUT" == *"language=script"* ]]; then
    echo "  ✓ B4: manifest declares language=script (correct: resolves entry as path in cloned hook repo)"
else
    echo "  ✗ B4: manifest language field is wrong or missing (must be 'script' per iter-159 empirical fix)"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER158_MANIFEST_FIELD_PROBE_OUTPUT" == *"stages=['commit-msg']"* ]]; then
    echo "  ✓ B5: manifest declares stages=[commit-msg] (post-author validation stage)"
else
    echo "  ✗ B5: manifest stages field is wrong or missing"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER158_MANIFEST_FIELD_PROBE_OUTPUT" == *"pass_filenames=True"* ]] \
   && [[ "$ITER158_MANIFEST_FIELD_PROBE_OUTPUT" == *"entry_basename=iter158-"* ]]; then
    echo "  ✓ B6: manifest declares pass_filenames=true + entry points at iter-158 script"
else
    echo "  ✗ B6: manifest pass_filenames or entry field is wrong"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: Entry-point classifies correctly ──────────────────────────────
echo ""
echo "GROUP C (7 assertions): entry-point classifies commit-msg files correctly"

iter158_assert_entry_point_exits_with_expected_code \
    "C1: STANDARD-CONFORMANT subject → ACCEPT (exit 0)" \
    "feat(release): iter-158 pre-commit manifest" \
    "0"

iter158_assert_entry_point_exits_with_expected_code \
    "C2: COMPOUND-PREFIX subject → REJECT (exit 1)" \
    "feat(scope)+docs: bad compound prefix" \
    "1"

iter158_assert_entry_point_exits_with_expected_code \
    "C3: MISSING-TYPE subject → REJECT (exit 1)" \
    "just fix the bug in the parser" \
    "1"

iter158_assert_entry_point_exits_with_expected_code \
    "C4: 'Merge ' auto-bypass → ACCEPT (exit 0)" \
    "Merge branch 'main' into feature" \
    "0"

iter158_assert_entry_point_exits_with_expected_code \
    "C5: 'Revert ' auto-bypass → ACCEPT (exit 0)" \
    "Revert \"feat: previous change\"" \
    "0"

iter158_assert_entry_point_exits_with_expected_code \
    "C6: breaking-change shorthand feat!: → ACCEPT (exit 0)" \
    "feat!: drop legacy API" \
    "0"

iter158_assert_entry_point_exits_with_expected_code \
    "C7: breaking-change with scope feat(api)!: → ACCEPT (exit 0)" \
    "feat(api)!: drop legacy endpoints" \
    "0"

# ─── Group D: cc-skills self-dogfoods iter-157 ──────────────────────────────
echo ""
echo "GROUP D (2 assertions): cc-skills dogfoods iter-157 commit-msg hook on itself"

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER158_CC_SKILLS_OWN_COMMIT_MSG_HOOK_ABSOLUTE_PATH="$ITER158_REPO_ROOT/.git/hooks/commit-msg"
if [[ -f "$ITER158_CC_SKILLS_OWN_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]]; then
    echo "  ✓ D1: .git/hooks/commit-msg installed on cc-skills repo (dogfooding gap closed)"
else
    echo "  ✗ D1: cc-skills does NOT dogfood — .git/hooks/commit-msg missing"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER158_TOTAL_ASSERTIONS_EVALUATED=$((ITER158_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER158_CC_SKILLS_OWN_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]] \
   && grep -qF "ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_DO_NOT_EDIT_DIRECTLY" \
        "$ITER158_CC_SKILLS_OWN_COMMIT_MSG_HOOK_ABSOLUTE_PATH"; then
    echo "  ✓ D2: cc-skills .git/hooks/commit-msg carries the cc-skills-managed sentinel (verified iter-157 install)"
else
    echo "  ✗ D2: cc-skills .git/hooks/commit-msg lacks the iter-157 sentinel"
    ITER158_TOTAL_ASSERTIONS_FAILED=$((ITER158_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER158_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-158 REGRESSION TEST: ${ITER158_TOTAL_ASSERTIONS_EVALUATED}/${ITER158_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-158 REGRESSION TEST: $((ITER158_TOTAL_ASSERTIONS_EVALUATED - ITER158_TOTAL_ASSERTIONS_FAILED))/${ITER158_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER158_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
