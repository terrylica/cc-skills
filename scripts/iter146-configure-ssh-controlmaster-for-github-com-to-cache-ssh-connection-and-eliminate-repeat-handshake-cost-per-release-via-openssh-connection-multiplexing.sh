#!/usr/bin/env bash
# iter-146: configure OpenSSH ControlMaster connection multiplexing for
# github.com to cache the authenticated SSH session for 10 minutes, dropping
# semantic-release's `get-git-auth-url` verifyAuth-via-git-push-dry-run cost
# from ~1.7s to ~100-200ms per release.
#
# Background (iter-144 forensic discovery + iter-146 root-cause analysis):
#
#   Iter-144's debug-namespace stderr parser surfaced
#   `semantic-release:get-git-auth-url` as the dominant remaining bottleneck
#   inside Phase 2 (semantic-release) after iter-145 eliminated the silent
#   JSON.parse SyntaxError stack traces from getTagsNotes.
#
#   `node_modules/semantic-release/lib/get-git-auth-url.js` line 91-93 ALWAYS
#   runs `verifyAuth(repositoryUrl, branch, {cwd, env})` first, regardless of
#   what authentication env vars (GH_TOKEN, GITHUB_TOKEN, GIT_CREDENTIALS,
#   etc.) are set. `verifyAuth` from `semantic-release/lib/git.js` executes:
#
#       git push --dry-run --no-verify <repositoryUrl> HEAD:<branch>
#
#   This is a real network round-trip to GitHub doing either SSH key exchange
#   (when remote is SSH-formatted) or HTTPS+TLS+token handshake. Empirically
#   ~1.7s per call on a warm-DNS connection from a residential US-west link.
#
#   There is no documented `--skip-auth-verify` flag.
#   semantic-release/semantic-release#2053 has been open since 2021 requesting
#   exactly this — the maintainer-accepted design decision is to verify
#   push access for every release. The only operator-side leverage to make
#   the verification cheaper is to make the network round-trip itself faster.
#
# Optimization mechanism: OpenSSH ControlMaster
#
#   OpenSSH ControlMaster ("connection multiplexing") establishes a single
#   persistent SSH session to a host on first connect, then reuses that
#   session for all subsequent SSH operations to the same host until the
#   ControlPersist TTL expires. Subsequent connections skip:
#     - TCP handshake (3-way SYN/SYNACK/ACK round-trip)
#     - SSH protocol version exchange
#     - Diffie-Hellman / curve25519 key exchange (most expensive — CPU bound)
#     - SSH user authentication (signature verification)
#
#   Empirical cost-reduction:
#     - Cold SSH connection: ~1500-1800ms (full handshake)
#     - Warm ControlMaster reuse: ~50-150ms (just connection accept)
#
#   This makes semantic-release's verifyAuth call ~10-15x faster on every
#   release AFTER the first connection in any 10-minute window.
#
# Configuration applied to `~/.ssh/config`:
#
#   Host github.com
#       ControlMaster auto
#       ControlPath ~/.ssh/controlmasters/%r@%h:%p
#       ControlPersist 10m
#
#   Scoped to `Host github.com` ONLY — does not affect SSH to other hosts.
#   Existing user-configured Host stanzas are preserved untouched.
#
# Safety:
#   - Backs up existing ~/.ssh/config to ~/.ssh/config.iter146-backup-<timestamp>
#     before any modification.
#   - Idempotent: detects the iter-146 marker on a second run and skips.
#   - Refuses to modify if a `Host github.com` block already exists from
#     another source (operator must reconcile manually).
#   - Creates ~/.ssh/controlmasters/ with mode 0700 if absent.
#
# Operator opt-in:
#   - This script MODIFIES the user's ~/.ssh/config. It is NOT run
#     automatically by any release-pipeline phase. Operators must consciously
#     invoke it. Per-developer-machine; not pushed to the repo.
#
# Verification post-setup:
#   - Run iter-144 parser against a fresh dry-run capture and observe
#     `semantic-release:get-git-auth-url` cumulative-ms drop by ~1.5s.
#   - First release after setup still pays full cost (cold connection);
#     all subsequent releases within 10 minutes benefit from multiplexing.

set -euo pipefail

ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY="$HOME/.ssh/config"
ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS="$HOME/.ssh/controlmasters"
ITER146_MARKER_COMMENT_LINE_FOR_IDEMPOTENT_DETECTION="# iter-146-cc-skills: ControlMaster for github.com (semantic-release verifyAuth speedup)"
ITER146_SSH_CONTROLPERSIST_TTL_DURATION_FOR_CACHED_SESSION="10m"

iter146_emit_summary_banner_header_for_setup_run() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-146 SSH ControlMaster setup for github.com"
    echo "  Purpose: drop semantic-release verifyAuth cost from ~1.7s to ~100ms per call"
    echo "  by reusing one persistent SSH session for 10 minutes."
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

iter146_check_preconditions_and_bail_early_if_setup_already_applied_or_user_has_conflicting_config() {
    if [[ -f "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY" ]]; then
        if grep -qF "$ITER146_MARKER_COMMENT_LINE_FOR_IDEMPOTENT_DETECTION" "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY" 2>/dev/null; then
            echo "  = iter-146 marker already present in $ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY — already configured, exiting idempotently"
            exit 0
        fi

        # Detect pre-existing `Host github.com` block from another source.
        # Refuse to overwrite — operator must reconcile manually.
        if grep -qE '^[[:space:]]*Host[[:space:]]+([^[:space:]]+[[:space:]]+)?github\.com([[:space:]]|$)' "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY" 2>/dev/null; then
            echo "  ✗ Existing 'Host github.com' block detected in $ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY"
            echo "    (not from iter-146 — no marker comment present)."
            echo ""
            echo "  REFUSING to modify automatically — your existing config takes precedence."
            echo "  Manual reconciliation: add these directives to your existing 'Host github.com' block:"
            echo ""
            echo "      ControlMaster auto"
            echo "      ControlPath ~/.ssh/controlmasters/%r@%h:%p"
            echo "      ControlPersist $ITER146_SSH_CONTROLPERSIST_TTL_DURATION_FOR_CACHED_SESSION"
            echo ""
            echo "  Or remove the existing block and re-run this script."
            exit 1
        fi
    fi
}

iter146_ensure_controlmasters_directory_exists_with_correct_owner_only_permissions() {
    if [[ ! -d "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS" ]]; then
        echo "  → Creating $ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS (mode 0700)"
        mkdir -p "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS"
        chmod 700 "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS"
    else
        local current_dir_permissions_in_octal_form
        current_dir_permissions_in_octal_form=$(stat -f '%Lp' "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS" 2>/dev/null || stat -c '%a' "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS" 2>/dev/null || echo "unknown")
        if [[ "$current_dir_permissions_in_octal_form" != "700" ]]; then
            echo "  → Tightening $ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS permissions to 0700 (was $current_dir_permissions_in_octal_form)"
            chmod 700 "$ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS"
        else
            echo "  ✓ $ITER146_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS exists with mode 0700"
        fi
    fi
}

iter146_backup_existing_ssh_config_before_modification_if_present() {
    if [[ -f "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY" ]]; then
        local backup_path_with_iter146_marker_and_timestamp_suffix
        backup_path_with_iter146_marker_and_timestamp_suffix="$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY.iter146-backup-$(date +%Y%m%d-%H%M%S)"
        cp -p "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY" "$backup_path_with_iter146_marker_and_timestamp_suffix"
        echo "  ✓ Backed up existing ~/.ssh/config to $backup_path_with_iter146_marker_and_timestamp_suffix"
    fi
}

iter146_append_controlmaster_block_for_github_com_to_ssh_config_with_iter146_marker_comment() {
    {
        echo ""
        echo "$ITER146_MARKER_COMMENT_LINE_FOR_IDEMPOTENT_DETECTION"
        echo "Host github.com"
        echo "    ControlMaster auto"
        echo "    ControlPath ~/.ssh/controlmasters/%r@%h:%p"
        echo "    ControlPersist $ITER146_SSH_CONTROLPERSIST_TTL_DURATION_FOR_CACHED_SESSION"
    } >> "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY"
    chmod 600 "$ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY"
    echo "  ✓ Appended Host github.com ControlMaster block to $ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY"
}

iter146_emit_post_setup_verification_instructions_for_operator() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-146 SETUP COMPLETE"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Verify the speedup by capturing a fresh semantic-release dry-run + parsing:"
    echo ""
    echo "    DEBUG=semantic-release:* npx semantic-release --dry-run --no-ci \\"
    echo "      2> /tmp/iter146-post-setup.log"
    echo "    python3 scripts/iter144-...py /tmp/iter146-post-setup.log"
    echo ""
    echo "  NOTE: the FIRST release after setup still pays full SSH handshake cost"
    echo "  (cold connection — there's no cached session to reuse yet). All"
    echo "  releases within the next ${ITER146_SSH_CONTROLPERSIST_TTL_DURATION_FOR_CACHED_SESSION} benefit from the persistent connection."
    echo ""
    echo "  To uninstall: remove the iter-146 marker comment + Host github.com block"
    echo "  from $ITER146_SSH_CONFIG_PATH_IN_USER_HOME_DIRECTORY, or restore the .iter146-backup-* file."
    echo ""
}

iter146_main_entry_point_orchestrates_idempotent_setup_with_backup_and_post_verify_instructions() {
    iter146_emit_summary_banner_header_for_setup_run
    iter146_check_preconditions_and_bail_early_if_setup_already_applied_or_user_has_conflicting_config
    iter146_ensure_controlmasters_directory_exists_with_correct_owner_only_permissions
    iter146_backup_existing_ssh_config_before_modification_if_present
    iter146_append_controlmaster_block_for_github_com_to_ssh_config_with_iter146_marker_comment
    iter146_emit_post_setup_verification_instructions_for_operator
}

iter146_main_entry_point_orchestrates_idempotent_setup_with_backup_and_post_verify_instructions
