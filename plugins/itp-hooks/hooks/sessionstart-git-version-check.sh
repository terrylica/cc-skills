#!/usr/bin/env bash
# SessionStart: warn, into the session's context, when the git first on PATH is too old for
# config-based hooks (hook.<name>.event in ~/.gitconfig need git >= 2.54) or is Apple's
# /usr/bin/git. Such a git silently runs none of those hooks, so every gate defined there is
# skipped. Silent when the floor holds. Never blocks: SessionStart cannot; the PreToolUse
# old-git guard is what refuses the commit. Spoke: docs/old-git-guard.md.
set -euo pipefail

# Mirrors GIT_CONFIG_HOOKS_MIN_VERSION in hooks/lib/old-git-detector.ts (a test keeps them equal).
MIN_MAJOR=2
MIN_MINOR=54

git_path="$(command -v git || true)"
if [[ -z "$git_path" ]]; then
    exit 0
fi

rc=0
version_text="$("$git_path" --version 2>/dev/null)" || rc=$?
if (( rc != 0 )); then
    exit 0
fi

if [[ ! "$version_text" =~ git\ version\ ([0-9]+)\.([0-9]+) ]]; then
    exit 0
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"

below_floor=0
if (( major < MIN_MAJOR || (major == MIN_MAJOR && minor < MIN_MINOR) )); then
    below_floor=1
fi
apple_git=0
if [[ "$git_path" == "/usr/bin/git" && "$(uname -s)" == "Darwin" ]]; then
    apple_git=1
fi
fix="Use /opt/homebrew/bin/git, or put Homebrew first on PATH (export PATH=\"/opt/homebrew/bin:\$PATH\")."
if (( below_floor )); then
    echo "[itp-hooks] The git first on PATH is ${git_path} (${version_text}), older than ${MIN_MAJOR}.${MIN_MINOR}. Config-based git hooks in ~/.gitconfig need git >= ${MIN_MAJOR}.${MIN_MINOR}; this git silently skips them, so the old-git guard will refuse git commit/push/merge/pull/rebase/cherry-pick/revert/am here. ${fix}"
elif (( apple_git )); then
    echo "[itp-hooks] The git first on PATH is Apple's /usr/bin/git (${version_text}). It meets the ${MIN_MAJOR}.${MIN_MINOR} floor for config-based hooks today, but it changes only with Xcode updates and has trailed Homebrew git by several releases. ${fix}"
fi
exit 0
