#!/usr/bin/env bash
#
# iter-157 idempotent installer/uninstaller for the commit-msg git hook.
#
# Operations:
#   install   — copy iter-157 hook into $(git rev-parse --git-dir)/hooks/commit-msg,
#               first backing up any pre-existing non-cc-skills hook to
#               commit-msg.backup-iter157-<unix-timestamp>. Re-runs are no-ops
#               if the destination already matches the source byte-for-byte.
#   uninstall — remove the cc-skills-managed hook and, if a backup exists,
#               restore the most recent one. Refuses to touch hooks that
#               lack the cc-skills sentinel marker.
#   status    — print whether the hook is installed, the source location,
#               and any backups present.
#
# Detection: the hook source script's first comment line uniquely identifies it
# as cc-skills-managed via the
# ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_SENTINEL_MARKER string the installer
# embeds into the deployed file. This is how `uninstall` knows it's safe to
# remove vs. a third-party hook the user installed manually.

set -euo pipefail

# Resolve the installer's OWN directory (NOT the current git repo) so the
# installer can locate the sibling iter-157 hook source script even when
# invoked from inside an unrelated target repo. Using `git rev-parse
# --show-toplevel` here would resolve to the target repo, not cc-skills.
ITER157_INSTALLER_SCRIPT_DIRECTORY_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER157_HOOK_SOURCE_SCRIPT_RELATIVE_PATH="iter157-installable-commit-msg-git-hook-delegating-to-iter153-strict-mode-advisor-for-automatic-rejection-of-compound-prefix-and-missing-type-silent-fail-class-violations-at-commit-time-closing-the-natural-git-workflow-integration-gap.sh"
ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH="$ITER157_INSTALLER_SCRIPT_DIRECTORY_ABSOLUTE_PATH/$ITER157_HOOK_SOURCE_SCRIPT_RELATIVE_PATH"
ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_SENTINEL_MARKER="ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_DO_NOT_EDIT_DIRECTLY_REGENERATE_VIA_MISE_RUN_COMMITS_INSTALL_HOOK"
ITER157_TARGET_GIT_DIR=""
ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH=""

iter157_resolve_target_git_dir_and_commit_msg_hook_destination_absolute_path() {
    ITER157_TARGET_GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
    if [[ -z "$ITER157_TARGET_GIT_DIR" ]]; then
        echo "  ✗ iter-157 installer: not inside a git repository" >&2
        exit 1
    fi
    # `git rev-parse --git-dir` may return a relative path — make absolute.
    if [[ "$ITER157_TARGET_GIT_DIR" != /* ]]; then
        ITER157_TARGET_GIT_DIR="$(pwd)/$ITER157_TARGET_GIT_DIR"
    fi
    ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH="$ITER157_TARGET_GIT_DIR/hooks/commit-msg"
}

iter157_render_hook_body_with_sentinel_marker_embedded_for_safe_uninstall_detection() {
    printf '#!/usr/bin/env bash\n'
    printf '# %s\n' "$ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_SENTINEL_MARKER"
    printf '# Source: %s\n' "$ITER157_HOOK_SOURCE_SCRIPT_RELATIVE_PATH"
    printf '# Installed by: scripts/iter157-idempotent-installer-and-uninstaller-...sh\n'
    printf '# Regenerate: mise run commits:install-hook\n'
    printf '# Remove:     mise run commits:uninstall-hook\n'
    printf '#\n'
    printf '# This file is a thin shim that execs the canonical iter-157 hook from\n'
    printf '# the cc-skills repo. Editing this file directly will be lost on next\n'
    printf "# 'mise run commits:install-hook' invocation.\n"
    printf 'exec %q "$@"\n' "$ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH"
}

iter157_existing_hook_is_cc_skills_managed_via_sentinel_marker_detection() {
    local hook_path="$1"
    [[ -f "$hook_path" ]] || return 1
    grep -qF "$ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_SENTINEL_MARKER" "$hook_path" 2>/dev/null
}

iter157_install_commit_msg_git_hook_into_current_repo_dotgit_hooks_directory_with_idempotent_backup_of_existing_hook_for_safe_rollback() {
    iter157_resolve_target_git_dir_and_commit_msg_hook_destination_absolute_path
    if [[ ! -x "$ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH" ]]; then
        echo "  ✗ iter-157 hook source script missing or not executable at:" >&2
        echo "    $ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH" >&2
        exit 2
    fi
    mkdir -p "$ITER157_TARGET_GIT_DIR/hooks"
    local newly_rendered_hook_body_tmp_file
    newly_rendered_hook_body_tmp_file=$(mktemp -t iter157-commit-msg-hook-XXXXXX)
    iter157_render_hook_body_with_sentinel_marker_embedded_for_safe_uninstall_detection \
        > "$newly_rendered_hook_body_tmp_file"
    # Idempotency check: if dest exists, is cc-skills-managed, and identical, no-op.
    if [[ -f "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]] \
       && iter157_existing_hook_is_cc_skills_managed_via_sentinel_marker_detection "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" \
       && cmp -s "$newly_rendered_hook_body_tmp_file" "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"; then
        rm -f "$newly_rendered_hook_body_tmp_file"
        echo "  ✓ iter-157 commit-msg hook already installed and current at:"
        echo "    $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
        return 0
    fi
    # If dest exists and is NOT cc-skills-managed, back it up first.
    if [[ -f "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]] \
       && ! iter157_existing_hook_is_cc_skills_managed_via_sentinel_marker_detection "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"; then
        local backup_unix_timestamp
        backup_unix_timestamp=$(date +%s)
        local backup_destination="$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH.backup-iter157-$backup_unix_timestamp"
        mv "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" "$backup_destination"
        echo "  → Backed up existing non-cc-skills hook to:"
        echo "    $backup_destination"
    fi
    mv "$newly_rendered_hook_body_tmp_file" "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    chmod +x "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    echo "  ✓ iter-157 commit-msg hook installed at:"
    echo "    $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    echo "    → delegates to: $ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH"
}

iter157_uninstall_commit_msg_git_hook_restoring_backed_up_predecessor_or_removing_cc_skills_managed_hook() {
    iter157_resolve_target_git_dir_and_commit_msg_hook_destination_absolute_path
    if [[ ! -f "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]]; then
        echo "  ⊘ No commit-msg hook installed at $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH — nothing to do."
        return 0
    fi
    if ! iter157_existing_hook_is_cc_skills_managed_via_sentinel_marker_detection "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"; then
        echo "  ✗ Refusing to remove commit-msg hook that lacks the cc-skills sentinel:" >&2
        echo "    $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" >&2
        echo "    Remove it manually if you're sure it's not yours." >&2
        exit 3
    fi
    rm -f "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    echo "  ✓ Removed cc-skills-managed commit-msg hook."
    # Restore most-recent backup if one exists.
    local most_recent_backup
    most_recent_backup=$(
        find "$ITER157_TARGET_GIT_DIR/hooks" -maxdepth 1 -type f \
            -name 'commit-msg.backup-iter157-*' 2>/dev/null \
            | sort -r | head -1
    )
    if [[ -n "$most_recent_backup" ]]; then
        mv "$most_recent_backup" "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
        chmod +x "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
        echo "  ✓ Restored previous hook from backup:"
        echo "    (was) $most_recent_backup"
        echo "    (now) $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    fi
}

iter157_print_current_installation_status_with_source_target_and_backups_summary() {
    iter157_resolve_target_git_dir_and_commit_msg_hook_destination_absolute_path
    echo "iter-157 commit-msg hook installation status"
    echo "  source script: $ITER157_HOOK_SOURCE_SCRIPT_ABSOLUTE_PATH"
    echo "  target hook:   $ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"
    if [[ -f "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]]; then
        if iter157_existing_hook_is_cc_skills_managed_via_sentinel_marker_detection "$ITER157_TARGET_COMMIT_MSG_HOOK_ABSOLUTE_PATH"; then
            echo "  status:        ✓ INSTALLED (cc-skills-managed)"
        else
            echo "  status:        ⚠ INSTALLED (NOT cc-skills-managed — installed by some other tool)"
        fi
    else
        echo "  status:        ⊘ NOT INSTALLED"
    fi
    local backup_count
    backup_count=$(
        find "$ITER157_TARGET_GIT_DIR/hooks" -maxdepth 1 -type f \
            -name 'commit-msg.backup-iter157-*' 2>/dev/null | wc -l | tr -d ' '
    )
    echo "  backups:       $backup_count"
}

ITER157_INSTALLER_MODE_REQUESTED_BY_OPERATOR="${1:-install}"
case "$ITER157_INSTALLER_MODE_REQUESTED_BY_OPERATOR" in
    install)
        iter157_install_commit_msg_git_hook_into_current_repo_dotgit_hooks_directory_with_idempotent_backup_of_existing_hook_for_safe_rollback
        ;;
    uninstall)
        iter157_uninstall_commit_msg_git_hook_restoring_backed_up_predecessor_or_removing_cc_skills_managed_hook
        ;;
    status)
        iter157_print_current_installation_status_with_source_target_and_backups_summary
        ;;
    *)
        echo "Usage: $0 [install|uninstall|status]" >&2
        exit 64
        ;;
esac
