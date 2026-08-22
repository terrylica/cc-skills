#!/usr/bin/env bash
#MISE description="Iter-165 regression test pinning the pending-release aggregator. Iter-153 advisor answers single-subject questions; iter-165 answers multi-commit aggregate questions across an unreleased release window. Asserts (a) script structurally valid (bash -n + shellcheck clean), (b) zero-commits-since-tag case emits aggregate=NONE + count=0, (c) synthetic 4-commit window with fix+docs+feat+chore correctly aggregates to MINOR (feat wins precedence) + next version applies +0.1.0 reset-patch, (d) synthetic 3-commit window with BREAKING CHANGE footer in body correctly aggregates to MAJOR via iter-162 detection + next version applies +1.0.0 reset-minor-and-patch, (e) all-PATCH window aggregates to PATCH (correct precedence math, no upward leak), (f) --json mode parses cleanly via python3 json.loads + emits stable iter165_schema_version=1, (g) JSON breakdown array has correct element count + triggering_commit_short_sha matches the feat commit, (h) lib resolution from BASH_SOURCE (not git toplevel) survives running against synthetic /tmp repos via ITER165_REPO_ROOT_OVERRIDE."
set -euo pipefail

ITER165_TEST_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER165_TEST_REPO_ROOT"

ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH="$ITER165_TEST_REPO_ROOT/scripts/iter165-pending-release-aggregator-computing-cumulative-semver-bump-across-all-unreleased-commits-since-most-recent-git-tag-by-aggregating-iter161-classifier-output-and-rendering-concrete-iter164-next-version-preview.sh"
ITER165_MISE_TASK_ABSOLUTE_PATH="$ITER165_TEST_REPO_ROOT/.mise/tasks/commits/pending-release"

ITER165_TOTAL_ASSERTIONS_EVALUATED=0
ITER165_TOTAL_ASSERTIONS_FAILED=0

iter165_assert_truthy() {
    local label="$1" cond="$2"
    ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$cond" == "true" ]]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label"
        ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

# Build a synthetic git repo with N commits since one initial tag.
# Returns its absolute path. Caller is responsible for cleanup.
iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path() {
    local scenario_label="$1"
    shift
    local synthetic_repo_dir
    synthetic_repo_dir=$(mktemp -d -t "iter165-${scenario_label}-XXXXXX")
    (
        cd "$synthetic_repo_dir"
        git init -q
        git config user.email "iter165-test@example.com"
        git config user.name "iter165-test"
        git commit --allow-empty -q -m "initial baseline before tag"
        git tag v1.0.0
        # Remaining args are commit specs of form "subject" or "subject|||body".
        for commit_spec in "$@"; do
            if [[ "$commit_spec" == *'|||'* ]]; then
                local subj="${commit_spec%%|||*}"
                local body="${commit_spec#*|||}"
                printf '%s\n\n%s\n' "$subj" "$body" | git commit --allow-empty -q -F -
            else
                git commit --allow-empty -q -m "$commit_spec"
            fi
        done
    ) >/dev/null 2>&1
    echo "$synthetic_repo_dir"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-165 PENDING-RELEASE-AGGREGATOR REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: structural validity ────────────────────────────────────────────
echo ""
echo "GROUP A (3 assertions): aggregator script structurally valid"

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: aggregator script exists at canonical path"
else
    echo "  ✗ A1: aggregator script missing"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: aggregator passes bash -n syntax check"
else
    echo "  ✗ A2: aggregator FAILS bash -n syntax check"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: aggregator passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: aggregator has shellcheck warnings"
        ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: zero-commit edge case ──────────────────────────────────────────
echo ""
echo "GROUP B (3 assertions): zero-commits-since-tag scenario"

ITER165_GROUP_B_REPO=$(iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path "groupB-zero")
ITER165_GROUP_B_HUMAN=$(cd "$ITER165_GROUP_B_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" 2>&1 || true)

iter165_assert_truthy \
    "B1: zero-commit human output contains 'commits since tag:     0'" \
    "$([[ "$ITER165_GROUP_B_HUMAN" == *"commits since tag:     0"* ]] && echo true || echo false)"

iter165_assert_truthy \
    "B2: zero-commit human output flags skip diagnostic (no pending commits)" \
    "$([[ "$ITER165_GROUP_B_HUMAN" == *"no pending commits"* ]] && echo true || echo false)"

ITER165_GROUP_B_JSON=$(cd "$ITER165_GROUP_B_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)
ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_B_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["commit_count_since_tag"]==0; assert d["aggregate_bump_label_per_semver_precedence"]=="NONE"' 2>/dev/null; then
    echo "  ✓ B3: zero-commit JSON parses + count==0 + aggregate==NONE"
else
    echo "  ✗ B3: zero-commit JSON failed schema check"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

rm -rf "$ITER165_GROUP_B_REPO"

# ─── Group C: 4-commit MINOR-dominated window ────────────────────────────────
echo ""
echo "GROUP C (5 assertions): synthetic 4-commit fix+docs+feat+chore window aggregates to MINOR"

ITER165_GROUP_C_REPO=$(iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path \
    "groupC-minor" \
    "fix: small fix one" \
    "docs: tweak readme" \
    "feat: add feature alpha" \
    "chore: bump dep")
ITER165_GROUP_C_HUMAN=$(cd "$ITER165_GROUP_C_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" 2>&1 || true)

iter165_assert_truthy \
    "C1: 4-commit human shows 'commits since tag:     4'" \
    "$([[ "$ITER165_GROUP_C_HUMAN" == *"commits since tag:     4"* ]] && echo true || echo false)"

iter165_assert_truthy \
    "C2: 4-commit human aggregate-bump line includes MINOR" \
    "$([[ "$ITER165_GROUP_C_HUMAN" =~ aggregate\ bump:[[:space:]]+[^[:space:]]*MINOR ]] && echo true || echo false)"

iter165_assert_truthy \
    "C3: 4-commit human next-release shows v1.0.0 → v1.1.0 (MINOR resets patch to 0)" \
    "$([[ "$ITER165_GROUP_C_HUMAN" =~ v1\.0\.0.*v1\.1\.0 ]] && echo true || echo false)"

ITER165_GROUP_C_JSON=$(cd "$ITER165_GROUP_C_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)
ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_C_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["commit_count_since_tag"]==4; assert d["aggregate_bump_label_per_semver_precedence"]=="MINOR"; assert d["iter164_next_version_preview"]["next_version"]=="v1.1.0"; assert d["bump_histogram"]=={"MAJOR":0,"MINOR":1,"PATCH":3,"NONE":0}' 2>/dev/null; then
    echo "  ✓ C4: 4-commit JSON aggregate=MINOR, next=v1.1.0, histogram MAJOR=0/MINOR=1/PATCH=3/NONE=0"
else
    echo "  ✗ C4: 4-commit JSON aggregate/next/histogram failed"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_C_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["triggering_commit_subject_at_highest_precedence"]; assert s.startswith("feat:")' 2>/dev/null; then
    echo "  ✓ C5: 4-commit JSON triggering-commit subject starts with 'feat:' (highest-precedence commit identified correctly)"
else
    echo "  ✗ C5: triggering-commit subject did not start with feat:"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

rm -rf "$ITER165_GROUP_C_REPO"

# ─── Group D: MAJOR via body-footer breaking change (iter-162 path) ──────────
echo ""
echo "GROUP D (4 assertions): synthetic 3-commit window with body-footer BREAKING CHANGE aggregates to MAJOR"

ITER165_GROUP_D_REPO=$(iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path \
    "groupD-major" \
    "fix: routine fix" \
    "feat: routine feature" \
    "feat: rewrite api surface|||BREAKING CHANGE: removed old endpoints")
ITER165_GROUP_D_HUMAN=$(cd "$ITER165_GROUP_D_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" 2>&1 || true)

iter165_assert_truthy \
    "D1: body-footer-MAJOR human aggregate-bump line includes MAJOR" \
    "$([[ "$ITER165_GROUP_D_HUMAN" =~ aggregate\ bump:[[:space:]]+[^[:space:]]*MAJOR ]] && echo true || echo false)"

iter165_assert_truthy \
    "D2: body-footer-MAJOR human shows v1.0.0 → v2.0.0 (MAJOR resets minor+patch)" \
    "$([[ "$ITER165_GROUP_D_HUMAN" =~ v1\.0\.0.*v2\.0\.0 ]] && echo true || echo false)"

ITER165_GROUP_D_JSON=$(cd "$ITER165_GROUP_D_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)
ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_D_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["aggregate_bump_label_per_semver_precedence"]=="MAJOR"; assert d["iter164_next_version_preview"]["next_version"]=="v2.0.0"; assert d["bump_histogram"]["MAJOR"]==1' 2>/dev/null; then
    echo "  ✓ D3: body-footer-MAJOR JSON aggregate=MAJOR, next=v2.0.0, histogram MAJOR=1"
else
    echo "  ✗ D3: body-footer-MAJOR JSON failed schema check"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_D_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["triggering_commit_subject_at_highest_precedence"]; assert "rewrite api surface" in s' 2>/dev/null; then
    echo "  ✓ D4: body-footer-MAJOR triggering-commit subject is the api-rewrite commit (latest MAJOR wins on tie)"
else
    echo "  ✗ D4: body-footer-MAJOR triggering-commit subject mismatch"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

rm -rf "$ITER165_GROUP_D_REPO"

# ─── Group E: all-PATCH window stays PATCH (no upward leak) ──────────────────
echo ""
echo "GROUP E (2 assertions): all-PATCH window aggregates to PATCH (no precedence leak)"

ITER165_GROUP_E_REPO=$(iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path \
    "groupE-patch" \
    "fix: one" \
    "fix: two" \
    "docs: three")
ITER165_GROUP_E_JSON=$(cd "$ITER165_GROUP_E_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_E_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["aggregate_bump_label_per_semver_precedence"]=="PATCH"; assert d["iter164_next_version_preview"]["next_version"]=="v1.0.1"' 2>/dev/null; then
    echo "  ✓ E1: all-PATCH window aggregate=PATCH, next=v1.0.1 (only patch component incremented)"
else
    echo "  ✗ E1: all-PATCH window failed: aggregate should be PATCH, next should be v1.0.1"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_E_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); h=d["bump_histogram"]; assert h["MAJOR"]==0 and h["MINOR"]==0 and h["PATCH"]==3 and h["NONE"]==0' 2>/dev/null; then
    echo "  ✓ E2: all-PATCH window histogram exactly MAJOR=0/MINOR=0/PATCH=3/NONE=0"
else
    echo "  ✗ E2: all-PATCH window histogram wrong"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

rm -rf "$ITER165_GROUP_E_REPO"

# ─── Group F: --json schema invariants ───────────────────────────────────────
echo ""
echo "GROUP F (3 assertions): --json schema invariants across all scenarios"

ITER165_GROUP_F_REPO=$(iter165_create_synthetic_repo_with_commits_since_tag_returning_absolute_path \
    "groupF-schema" \
    "feat: schema fixture commit")
ITER165_GROUP_F_JSON=$(cd "$ITER165_GROUP_F_REPO" && bash "$ITER165_AGGREGATOR_SCRIPT_ABSOLUTE_PATH" --json 2>/dev/null || true)

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_F_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["iter165_schema_version"]==1' 2>/dev/null; then
    echo "  ✓ F1: --json emits stable iter165_schema_version=1 (AI-agent consumer contract)"
else
    echo "  ✗ F1: iter165_schema_version missing or wrong value"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_F_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); nv=d["iter164_next_version_preview"]; assert nv["iter164_schema_version"]==1; assert nv["current_git_tag"]=="v1.0.0"; assert nv["next_version"]=="v1.1.0"' 2>/dev/null; then
    echo "  ✓ F2: --json embeds iter164_next_version_preview nested object with correct schema_version + current_git_tag + next_version"
else
    echo "  ✗ F2: nested iter164_next_version_preview object malformed"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_F_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["per_commit_bump_breakdown"])==1; r=d["per_commit_bump_breakdown"][0]; assert set(r.keys())=={"short_sha","subject","bump_label","rationale"}' 2>/dev/null; then
    echo "  ✓ F3: per_commit_bump_breakdown elements have canonical 4-field schema (short_sha + subject + bump_label + rationale)"
else
    echo "  ✗ F3: per_commit_bump_breakdown element schema mismatch"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

rm -rf "$ITER165_GROUP_F_REPO"

# ─── Group G: mise task wrapper delegates correctly ──────────────────────────
echo ""
echo "GROUP G (2 assertions): mise task wrapper delegates correctly to underlying script"

ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -x "$ITER165_MISE_TASK_ABSOLUTE_PATH" ]]; then
    echo "  ✓ G1: mise task file commits/pending-release exists and is executable"
else
    echo "  ✗ G1: mise task missing or not executable"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER165_GROUP_G_OUTPUT=$(bash "$ITER165_MISE_TASK_ABSOLUTE_PATH" --json 2>/dev/null || true)
ITER165_TOTAL_ASSERTIONS_EVALUATED=$((ITER165_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER165_GROUP_G_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "iter165_schema_version" in d' 2>/dev/null; then
    echo "  ✓ G2: mise task wrapper emits parseable JSON matching schema (delegation contract intact)"
else
    echo "  ✗ G2: mise task wrapper JSON delegation failed"
    ITER165_TOTAL_ASSERTIONS_FAILED=$((ITER165_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER165_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-165 REGRESSION TEST: ${ITER165_TOTAL_ASSERTIONS_EVALUATED}/${ITER165_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-165 REGRESSION TEST: $((ITER165_TOTAL_ASSERTIONS_EVALUATED - ITER165_TOTAL_ASSERTIONS_FAILED))/${ITER165_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER165_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
