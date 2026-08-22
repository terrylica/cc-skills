#!/usr/bin/env bash
#MISE description="Iter-157 regression test pinning the installable commit-msg git hook + idempotent installer/uninstaller. Asserts (a) hook source script exists + executable + bash-clean + shellcheck-clean, (b) installer + uninstaller scripts exist + bash-clean + shellcheck-clean, (c) mise task shims exist + bash-clean + shellcheck-clean, (d) end-to-end in a sandbox git repo: install creates .git/hooks/commit-msg with sentinel marker + sentinel-keyed status detection + idempotent re-install no-op + pre-existing-hook backup-and-restore + refuse-to-remove-non-cc-skills-hook + git commit rejects COMPOUND-PREFIX subject + git commit accepts STANDARD-CONFORMANT subject + merge-commit subjects bypass classification."
set -euo pipefail

ITER157_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER157_REPO_ROOT"

ITER157_HOOK_SOURCE_RELATIVE_PATH="scripts/iter157-installable-commit-msg-git-hook-delegating-to-iter153-strict-mode-advisor-for-automatic-rejection-of-compound-prefix-and-missing-type-silent-fail-class-violations-at-commit-time-closing-the-natural-git-workflow-integration-gap.sh"
ITER157_HOOK_SOURCE_ABSOLUTE_PATH="$ITER157_REPO_ROOT/$ITER157_HOOK_SOURCE_RELATIVE_PATH"
ITER157_INSTALLER_RELATIVE_PATH="scripts/iter157-idempotent-installer-and-uninstaller-of-the-commit-msg-git-hook-managing-existing-hook-backup-restoration-with-cc-skills-managed-sentinel-marker-for-safe-detection-of-our-own-installs-vs-third-party.sh"
ITER157_INSTALLER_ABSOLUTE_PATH="$ITER157_REPO_ROOT/$ITER157_INSTALLER_RELATIVE_PATH"
ITER157_INSTALL_HOOK_MISE_TASK="$ITER157_REPO_ROOT/.mise/tasks/commits/install-hook"
ITER157_UNINSTALL_HOOK_MISE_TASK="$ITER157_REPO_ROOT/.mise/tasks/commits/uninstall-hook"

ITER157_TOTAL_ASSERTIONS_EVALUATED=0
ITER157_TOTAL_ASSERTIONS_FAILED=0

iter157_assert_file_passes_bash_n_syntax_check_and_shellcheck() {
    local human_readable_label="$1"
    local file_absolute_path="$2"
    ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ ! -x "$file_absolute_path" ]]; then
        echo "  ✗ $human_readable_label: file missing or not executable"
        ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
        return
    fi
    if ! bash -n "$file_absolute_path" 2>/dev/null; then
        echo "  ✗ $human_readable_label: bash -n FAILED"
        ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
        return
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        if ! shellcheck "$file_absolute_path" >/dev/null 2>&1; then
            echo "  ✗ $human_readable_label: shellcheck FAILED"
            ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
            return
        fi
    fi
    echo "  ✓ $human_readable_label"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-157 COMMIT-MSG-GIT-HOOK + IDEMPOTENT-INSTALLER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Source scripts structurally valid ─────────────────────────────
echo ""
echo "GROUP A (4 assertions): source scripts structurally valid"

iter157_assert_file_passes_bash_n_syntax_check_and_shellcheck \
    "A1: hook source script (executable, bash-clean, shellcheck-clean)" \
    "$ITER157_HOOK_SOURCE_ABSOLUTE_PATH"

iter157_assert_file_passes_bash_n_syntax_check_and_shellcheck \
    "A2: installer/uninstaller script (executable, bash-clean, shellcheck-clean)" \
    "$ITER157_INSTALLER_ABSOLUTE_PATH"

iter157_assert_file_passes_bash_n_syntax_check_and_shellcheck \
    "A3: install-hook mise task shim (executable, bash-clean, shellcheck-clean)" \
    "$ITER157_INSTALL_HOOK_MISE_TASK"

iter157_assert_file_passes_bash_n_syntax_check_and_shellcheck \
    "A4: uninstall-hook mise task shim (executable, bash-clean, shellcheck-clean)" \
    "$ITER157_UNINSTALL_HOOK_MISE_TASK"

# ─── Group B: End-to-end in sandbox git repo ────────────────────────────────
#
# All Group B assertions use a single throwaway sandbox repo so that the
# cc-skills repo's own .git/hooks/ is never touched by the regression test.

ITER157_SANDBOX_REPO_ABSOLUTE_PATH=$(mktemp -d -t iter157-regression-sandbox-XXXXXX)
trap 'rm -rf "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"' EXIT
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    git init --quiet --initial-branch=main
    git config user.email regression@test.local
    git config user.name "iter-157 regression"
)

echo ""
echo "GROUP B (8 assertions): end-to-end install/uninstall in sandbox git repo"

# B1: fresh install in empty hooks dir
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" install >/dev/null 2>&1
)
if [[ -x "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg" ]] \
   && grep -qF "ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_DO_NOT_EDIT_DIRECTLY" \
        "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg"; then
    echo "  ✓ B1: install creates .git/hooks/commit-msg with cc-skills sentinel marker"
else
    echo "  ✗ B1: install failed to create hook with sentinel"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B2: re-install is idempotent no-op (no error, no content change)
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER157_HOOK_BYTES_BEFORE_REINSTALL=$(wc -c < "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg")
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" install >/dev/null 2>&1
)
ITER157_HOOK_BYTES_AFTER_REINSTALL=$(wc -c < "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg")
if [[ "$ITER157_HOOK_BYTES_BEFORE_REINSTALL" == "$ITER157_HOOK_BYTES_AFTER_REINSTALL" ]]; then
    echo "  ✓ B2: re-install is idempotent (byte-identical hook)"
else
    echo "  ✗ B2: re-install changed hook bytes ($ITER157_HOOK_BYTES_BEFORE_REINSTALL → $ITER157_HOOK_BYTES_AFTER_REINSTALL)"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B3: pre-existing third-party hook gets backed up
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" uninstall >/dev/null 2>&1
    printf '#!/usr/bin/env bash\necho "pre-existing third party hook"\n' > .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
    "$ITER157_INSTALLER_ABSOLUTE_PATH" install >/dev/null 2>&1
)
ITER157_BACKUP_COUNT=$(
    find "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks" -maxdepth 1 -type f \
        -name 'commit-msg.backup-iter157-*' 2>/dev/null | wc -l | tr -d ' '
)
if [[ "$ITER157_BACKUP_COUNT" -ge 1 ]]; then
    echo "  ✓ B3: pre-existing non-cc-skills hook is backed up (found $ITER157_BACKUP_COUNT backup)"
else
    echo "  ✗ B3: pre-existing hook was NOT backed up"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B4: uninstall restores backup
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" uninstall >/dev/null 2>&1
)
if [[ -f "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg" ]] \
   && grep -qF "pre-existing third party hook" "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg"; then
    echo "  ✓ B4: uninstall restored the pre-existing third-party hook from backup"
else
    echo "  ✗ B4: uninstall did NOT restore the third-party hook"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B5: uninstall refuses to remove third-party hook lacking sentinel
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER157_UNINSTALL_EXIT_CODE_FOR_THIRD_PARTY=0
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" uninstall >/dev/null 2>&1
) || ITER157_UNINSTALL_EXIT_CODE_FOR_THIRD_PARTY=$?
if [[ "$ITER157_UNINSTALL_EXIT_CODE_FOR_THIRD_PARTY" -ne 0 ]] \
   && [[ -f "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg" ]] \
   && grep -qF "pre-existing third party hook" "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg"; then
    echo "  ✓ B5: uninstall refused to remove third-party hook (exit=$ITER157_UNINSTALL_EXIT_CODE_FOR_THIRD_PARTY, hook preserved)"
else
    echo "  ✗ B5: uninstall did not refuse third-party hook (exit=$ITER157_UNINSTALL_EXIT_CODE_FOR_THIRD_PARTY)"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Clean up sandbox for git-commit subtests
rm -f "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg" \
      "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH/.git/hooks/commit-msg.backup-iter157-"*
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    "$ITER157_INSTALLER_ABSOLUTE_PATH" install >/dev/null 2>&1
)

# B6: git commit with COMPOUND-PREFIX subject → REJECTED (git exit non-zero)
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER157_GIT_COMMIT_EXIT_FOR_COMPOUND_PREFIX=0
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    echo "x" > test1.txt && git add test1.txt
    git -c core.editor=true commit -m 'feat(scope)+docs: bad compound prefix' >/dev/null 2>&1
) || ITER157_GIT_COMMIT_EXIT_FOR_COMPOUND_PREFIX=$?
if [[ "$ITER157_GIT_COMMIT_EXIT_FOR_COMPOUND_PREFIX" -ne 0 ]]; then
    echo "  ✓ B6: git commit rejects COMPOUND-PREFIX (exit=$ITER157_GIT_COMMIT_EXIT_FOR_COMPOUND_PREFIX)"
else
    echo "  ✗ B6: git commit accepted COMPOUND-PREFIX subject (should reject)"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B7: git commit with STANDARD-CONFORMANT subject → ACCEPTED (git exit 0)
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER157_GIT_COMMIT_EXIT_FOR_CONFORMANT=0
(
    cd "$ITER157_SANDBOX_REPO_ABSOLUTE_PATH"
    git -c core.editor=true commit -m 'feat(test): iter-157 conformant' >/dev/null 2>&1
) || ITER157_GIT_COMMIT_EXIT_FOR_CONFORMANT=$?
if [[ "$ITER157_GIT_COMMIT_EXIT_FOR_CONFORMANT" -eq 0 ]]; then
    echo "  ✓ B7: git commit accepts STANDARD-CONFORMANT subject (exit=0)"
else
    echo "  ✗ B7: git commit rejected conformant subject (exit=$ITER157_GIT_COMMIT_EXIT_FOR_CONFORMANT)"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# B8: merge-commit-style subject bypasses classification (Merge prefix)
ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER157_HOOK_EXIT_FOR_MERGE_PREFIX=0
ITER157_MERGE_COMMIT_MSG_FILE=$(mktemp -t iter157-merge-XXXXXX)
printf "Merge branch 'main' into feature\n" > "$ITER157_MERGE_COMMIT_MSG_FILE"
"$ITER157_HOOK_SOURCE_ABSOLUTE_PATH" "$ITER157_MERGE_COMMIT_MSG_FILE" >/dev/null 2>&1 \
    || ITER157_HOOK_EXIT_FOR_MERGE_PREFIX=$?
rm -f "$ITER157_MERGE_COMMIT_MSG_FILE"
if [[ "$ITER157_HOOK_EXIT_FOR_MERGE_PREFIX" -eq 0 ]]; then
    echo "  ✓ B8: hook bypasses classification on 'Merge ' prefix (exit=0)"
else
    echo "  ✗ B8: hook rejected merge-prefix subject (exit=$ITER157_HOOK_EXIT_FOR_MERGE_PREFIX)"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group C: docs/RELEASE.md cross-reference for iter-157 ──────────────────
echo ""
echo "GROUP C (2 assertions): docs/RELEASE.md cross-reference"

ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
# Future-proof: match "iter-150 → iter-N" for any N ≥ 157 so subsequent
# arc extensions don't regress this iter-157 assertion.
if grep -qE 'iter-150 → iter-1[5-9][0-9]' "$ITER157_REPO_ROOT/docs/RELEASE.md" 2>/dev/null \
   && grep -qF "COMMIT-MSG HOOK" "$ITER157_REPO_ROOT/docs/RELEASE.md" 2>/dev/null; then
    echo "  ✓ C1: docs/RELEASE.md Toolkit Index header covers iter-157+ arc range and lists COMMIT-MSG HOOK row"
else
    echo "  ✗ C1: docs/RELEASE.md arc range or COMMIT-MSG HOOK row missing"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER157_TOTAL_ASSERTIONS_EVALUATED=$((ITER157_TOTAL_ASSERTIONS_EVALUATED + 1))
if grep -qF "commits:install-hook" "$ITER157_REPO_ROOT/docs/RELEASE.md" 2>/dev/null; then
    echo "  ✓ C2: docs/RELEASE.md mentions commits:install-hook"
else
    echo "  ✗ C2: docs/RELEASE.md missing commits:install-hook mention"
    ITER157_TOTAL_ASSERTIONS_FAILED=$((ITER157_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER157_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-157 REGRESSION TEST: ${ITER157_TOTAL_ASSERTIONS_EVALUATED}/${ITER157_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-157 REGRESSION TEST: $((ITER157_TOTAL_ASSERTIONS_EVALUATED - ITER157_TOTAL_ASSERTIONS_FAILED))/${ITER157_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER157_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
