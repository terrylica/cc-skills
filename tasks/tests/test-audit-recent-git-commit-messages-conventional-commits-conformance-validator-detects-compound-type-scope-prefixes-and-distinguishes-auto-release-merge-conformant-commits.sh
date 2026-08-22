#!/usr/bin/env bash
#MISE description="Iter-82 regression test for audit-recent-git-commit-messages-for-conventional-commits-conformance. Synthesizes a fixture git repo with known mix of conformant + compound-prefix + auto-release + merge + missing-type commits, runs the validator, and asserts the classification counts + diagnostic-line presence. Locks in the silent-fail detection (compound prefix like 'feat(scope)+docs:') so future edits to the validator can't silently regress."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR_TASK_PATH="$SCRIPT_DIR/../audit-recent-git-commit-messages-for-conventional-commits-conformance-to-prevent-silent-semantic-release-skip-of-non-standard-compound-type-scope-prefixes.sh"

if [[ ! -f "$VALIDATOR_TASK_PATH" ]]; then
    echo "FAIL: Validator task not found at $VALIDATOR_TASK_PATH"
    exit 1
fi

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0

assert_passes() {
    ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1))
    echo "  ✓ PASS: $1"
}

assert_fails() {
    ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1))
    echo "  ✗ FAIL: $1"
}

# Build a synthetic fixture git repo to exercise every classification branch.
FIXTURE_REPO_DIR=$(mktemp -d -t iter82-commit-validator-fixture-repo.XXXXXX)
trap 'rm -rf "$FIXTURE_REPO_DIR"' EXIT

cd "$FIXTURE_REPO_DIR"
git init -q -b main
git config user.email "iter82-test@local"
git config user.name "iter82 fixture"

# Helper: create empty commit with a specific subject.
create_synthetic_commit_with_subject() {
    git commit -q --allow-empty -m "$1"
}

echo "═══════════════════════════════════════════════════════════"
echo "  Iter-82 Conventional-Commits Validator — Regression Test"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Building fixture commit history at $FIXTURE_REPO_DIR"
echo ""

# Anchor commit so HEAD~11 resolves (the validator scans HEAD~11..HEAD
# in the synthetic-fixture test range; without this anchor, HEAD~11
# doesn't exist and the range is empty).
create_synthetic_commit_with_subject "chore: anchor commit for fixture range resolution"

# Conformant commits (each on the recognized-types allowlist).
create_synthetic_commit_with_subject "feat(scope-a): conformant feat"
create_synthetic_commit_with_subject "fix(scope-b): conformant fix"
create_synthetic_commit_with_subject "perf(scope-c): conformant perf"
create_synthetic_commit_with_subject "docs: conformant docs without scope"
create_synthetic_commit_with_subject "feat(scope-d)!: conformant breaking-change"

# Auto-release commit (excluded from non-conformance reporting).
create_synthetic_commit_with_subject "chore(release): 99.99.0 [skip ci]"

# Compound-prefix violations (the silent-fail class).
create_synthetic_commit_with_subject "feat(scope-e)+docs: compound prefix violation #1"
create_synthetic_commit_with_subject "perf(scope-f)+chore(scope-g): compound prefix violation #2"
create_synthetic_commit_with_subject "fix(scope-h);refactor: compound prefix with semicolon violation #3"

# Merge commit (excluded by Merge prefix heuristic).
create_synthetic_commit_with_subject "Merge branch 'feature/foo' into main"

# Unrecognized-type violation.
create_synthetic_commit_with_subject "wibble(scope-i): unrecognized type wibble"

# Run the validator against this synthetic range.
validator_output_captured=$(
    cd "$FIXTURE_REPO_DIR" && bash "$VALIDATOR_TASK_PATH" --range "HEAD~11..HEAD" 2>&1
)

# Extract counts via grep.
extract_count_from_validator_output() {
    local label="$1"
    echo "$validator_output_captured" \
        | grep -oE "${label}[[:space:]]*[0-9]+" \
        | grep -oE '[0-9]+$' | head -1 || echo "MISSING"
}

total_commits_count=$(extract_count_from_validator_output "Total commits scanned:")
conformant_count=$(extract_count_from_validator_output "Standard-conformant:")
auto_release_count=$(extract_count_from_validator_output "Auto-release.*:")
merge_count=$(extract_count_from_validator_output "Merge commits:")
compound_count=$(extract_count_from_validator_output "Compound-prefix violations.*:")
missing_type_count=$(extract_count_from_validator_output "Missing-type.*:")

# Assertions.
if [[ "$total_commits_count" == "11" ]]; then
    assert_passes "Total commits scanned = 11 (matches fixture count)"
else
    assert_fails "Total commits scanned = $total_commits_count, expected 11"
fi

if [[ "$conformant_count" == "5" ]]; then
    assert_passes "Conformant = 5 (feat, fix, perf, docs, breaking-feat)"
else
    assert_fails "Conformant = $conformant_count, expected 5"
fi

if [[ "$auto_release_count" == "1" ]]; then
    assert_passes "Auto-release = 1 (chore(release) by sem-rel)"
else
    assert_fails "Auto-release = $auto_release_count, expected 1"
fi

if [[ "$merge_count" == "1" ]]; then
    assert_passes "Merge commits = 1 (Merge branch ...)"
else
    assert_fails "Merge commits = $merge_count, expected 1"
fi

if [[ "$compound_count" == "3" ]]; then
    assert_passes "Compound-prefix violations = 3 (silent-fail class detected)"
else
    assert_fails "Compound-prefix violations = $compound_count, expected 3"
fi

if [[ "$missing_type_count" == "1" ]]; then
    assert_passes "Missing-type / unrecognized = 1 (wibble type)"
else
    assert_fails "Missing-type / unrecognized = $missing_type_count, expected 1"
fi

# Verify the diagnostic message includes the specific compound-prefix commits.
if echo "$validator_output_captured" | grep -q "compound prefix violation #1"; then
    assert_passes "Diagnostic includes compound-prefix violation #1"
else
    assert_fails "Diagnostic missing compound-prefix violation #1"
fi

# Verify strict mode exits non-zero with violations.
if cd "$FIXTURE_REPO_DIR" && bash "$VALIDATOR_TASK_PATH" --strict --range "HEAD~11..HEAD" >/dev/null 2>&1; then
    assert_fails "Strict mode should exit non-zero on violations but exited 0"
else
    assert_passes "Strict mode exits non-zero on violations (release-gate behavior)"
fi

# Verify informational mode exits 0 even with violations.
if cd "$FIXTURE_REPO_DIR" && bash "$VALIDATOR_TASK_PATH" --range "HEAD~11..HEAD" >/dev/null 2>&1; then
    assert_passes "Informational mode exits 0 regardless (non-blocking)"
else
    assert_fails "Informational mode should exit 0 but exited non-zero"
fi

# Verify clean-conformant range exits 0 in strict mode too.
if cd "$FIXTURE_REPO_DIR" && bash "$VALIDATOR_TASK_PATH" --strict --range "HEAD~6..HEAD~5" >/dev/null 2>&1; then
    assert_passes "Strict mode on single-conformant commit exits 0"
else
    assert_fails "Strict mode should exit 0 on conformant commit"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Iter-82 conventional-commits validator regression test"
echo "═══════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
