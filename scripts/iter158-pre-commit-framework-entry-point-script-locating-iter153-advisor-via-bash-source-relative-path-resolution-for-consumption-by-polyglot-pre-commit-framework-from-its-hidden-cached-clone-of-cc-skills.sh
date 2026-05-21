#!/usr/bin/env bash
#
# iter-158 pre-commit framework entry-point script.
#
# Purpose: make the cc-skills conventional-commits arc consumable by the
# polyglot pre-commit framework (https://pre-commit.com) — the 2026
# industry-standard distribution channel for git hooks across language
# stacks. Closes the gap left by iter-157, where the installable git hook
# only works for operators who clone cc-skills locally.
#
# Why this is a separate entry-point vs. the iter-157 hook:
#
#   • The iter-157 hook locates the cc-skills repo via env-override or
#     git-config or canonical `$HOME/eon/cc-skills` default. None of those
#     are reachable from inside the pre-commit framework's hidden cache,
#     which clones cc-skills into something like
#     `~/.cache/pre-commit/repo<hash>/`. So iter-157's hook would
#     fail-OPEN there.
#
#   • This iter-158 entry-point uses `BASH_SOURCE[0]` instead, locating
#     the iter-153 advisor as a sibling file in the SAME script directory
#     wherever cc-skills was cloned. This is the standard pre-commit
#     framework pattern for `language: system` hooks (entry runs from the
#     framework's cached clone of the repo).
#
# Pre-commit framework contract:
#   - When configured with `stages: [commit-msg]` + `pass_filenames: true`,
#     pre-commit passes the absolute path to the .git/COMMIT_EDITMSG file
#     as $1.
#   - Exit 0 accepts the commit; non-zero rejects.
#   - The framework prints stderr unfiltered, so the iter-153 advisor's
#     verdict banner reaches the operator's terminal.
#
# Industry-standard escape hatch: operators can bypass with
# `git commit --no-verify`, just like the iter-157 hook.

set -euo pipefail

# ─── Step 1: locate iter-153 advisor via BASH_SOURCE-relative resolution ────
#
# When invoked from the pre-commit framework's cached clone, BASH_SOURCE[0]
# points to <cache>/scripts/iter158-...sh, so the sibling iter-153 advisor
# is at <cache>/scripts/iter153-...sh. This works regardless of where the
# clone lives because it's relative.

ITER158_ENTRY_POINT_SCRIPT_DIRECTORY_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER158_ITER153_ADVISOR_RELATIVE_PATH="iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"
ITER158_ITER153_ADVISOR_ABSOLUTE_PATH="$ITER158_ENTRY_POINT_SCRIPT_DIRECTORY_ABSOLUTE_PATH/$ITER158_ITER153_ADVISOR_RELATIVE_PATH"

if [[ ! -x "$ITER158_ITER153_ADVISOR_ABSOLUTE_PATH" ]]; then
    printf '[iter-158 pre-commit entry-point] ERROR: iter-153 advisor not found at %s — check cc-skills clone integrity in pre-commit cache.\n' \
        "$ITER158_ITER153_ADVISOR_ABSOLUTE_PATH" >&2
    exit 1
fi

# ─── Step 2: extract subject line from commit-msg file ──────────────────────
#
# Pre-commit framework with stages=[commit-msg] + pass_filenames=true passes
# the absolute path to .git/COMMIT_EDITMSG (or equivalent) as $1.

ITER158_COMMIT_MSG_FILE_ABSOLUTE_PATH="${1:-}"
if [[ -z "$ITER158_COMMIT_MSG_FILE_ABSOLUTE_PATH" ]] || [[ ! -f "$ITER158_COMMIT_MSG_FILE_ABSOLUTE_PATH" ]]; then
    printf '[iter-158 pre-commit entry-point] ERROR: missing or unreadable commit-msg file argument: %s\n' \
        "$ITER158_COMMIT_MSG_FILE_ABSOLUTE_PATH" >&2
    exit 1
fi

iter158_extract_first_non_comment_non_blank_subject_line_from_commit_editmsg_file_for_pre_commit_framework_consumption() {
    local commit_msg_file_absolute_path="$1"
    awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        { print; exit }
    ' "$commit_msg_file_absolute_path"
}

ITER158_PROPOSED_SUBJECT_LINE=$(
    iter158_extract_first_non_comment_non_blank_subject_line_from_commit_editmsg_file_for_pre_commit_framework_consumption "$ITER158_COMMIT_MSG_FILE_ABSOLUTE_PATH"
)

if [[ -z "$ITER158_PROPOSED_SUBJECT_LINE" ]]; then
    # Empty commit message — git itself aborts; no need for us to error.
    exit 0
fi

# ─── Step 3: skip auto-generated subjects (merge/revert/fixup/squash/amend) ──
#
# Same bypass logic as iter-157. The pre-commit framework respects this and
# moves on without flagging the commit.

case "$ITER158_PROPOSED_SUBJECT_LINE" in
    "Merge "* | "Revert "* | "fixup! "* | "squash! "* | "amend! "*)
        exit 0
        ;;
esac

# ─── Step 4: delegate to iter-153 advisor --strict ──────────────────────────

exec "$ITER158_ITER153_ADVISOR_ABSOLUTE_PATH" --strict -- "$ITER158_PROPOSED_SUBJECT_LINE"
