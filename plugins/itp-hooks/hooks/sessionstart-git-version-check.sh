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

reasons=()
if (( major < MIN_MAJOR || (major == MIN_MAJOR && minor < MIN_MINOR) )); then
    reasons+=("it is older than ${MIN_MAJOR}.${MIN_MINOR}")
fi
if [[ "$git_path" == "/usr/bin/git" && "$(uname -s)" == "Darwin" ]]; then
    reasons+=("it is Apple's /usr/bin/git")
fi
if (( ${#reasons[@]} == 0 )); then
    exit 0
fi

joined="${reasons[0]}"
if (( ${#reasons[@]} > 1 )); then
    joined="${reasons[0]} and ${reasons[1]}"
fi
echo "[itp-hooks] The git first on PATH is ${git_path} (${version_text}), and ${joined}. Config-based git hooks in ~/.gitconfig need git >= ${MIN_MAJOR}.${MIN_MINOR}; this git silently skips them, so the old-git guard will refuse git commit/push/merge/rebase/cherry-pick/am here. Use /opt/homebrew/bin/git, or put Homebrew first on PATH (export PATH=\"/opt/homebrew/bin:\$PATH\")."
exit 0
