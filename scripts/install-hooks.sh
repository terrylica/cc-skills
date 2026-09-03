#!/usr/bin/env bash
# Install git hooks for cc-skills development
# ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
#
# Usage: ./scripts/install-hooks.sh
#
# This installs a pre-commit hook that:
#   1. Blocks staged content containing forbidden client identifiers (PII guard)
#   2. Validates plugin registration, preventing the
#      "Plugin not found in any marketplace" error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing cc-skills git hooks..."

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/usr/bin/env bash
# Pre-commit hook for cc-skills marketplace
# ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
#
# Validates:
# 1. No staged content carries a forbidden client identifier (PII guard)
# 2. All plugin directories are registered in marketplace.json
# 3. Marketplace entries have valid paths and required fields

set -euo pipefail

# PII guard runs FIRST and on EVERY commit, deliberately ungated by path:
# this is a PUBLIC repository, client PII has reached it three times, and a
# leak can arrive in any file — including documentation about redaction,
# which is how two of the three incidents actually happened.
# Reports file/line/term-ID only, never the matched text.
# Bypass with a reason: PII_GUARD_OK="why this is safe" git commit ...

# Resolve the bun interpreter explicitly rather than trusting $PATH.
# Non-interactive shells on this machine routinely lack /opt/homebrew/bin,
# which has silently broken bun, gh and rclone before. A bare `bun` here
# would die with exit 127 and a bare "command not found" on every commit —
# and an operator facing that reaches for --no-verify or deletes the hook,
# which loses the guard entirely. Search a fixed list instead.
PII_GUARD_BUN=""
for pii_guard_candidate in \
    "$(command -v bun 2>/dev/null || true)" \
    /opt/homebrew/bin/bun \
    "$HOME/.bun/bin/bun"
do
    if [[ -n "$pii_guard_candidate" && -x "$pii_guard_candidate" ]]; then
        PII_GUARD_BUN="$pii_guard_candidate"
        break
    fi
done

# Fail CLOSED when no interpreter exists: an unverifiable commit on a public
# repo is exactly the case the guard exists for. But fail legibly — name what
# was searched and how to proceed, so this costs ten seconds, not the hook.
if [[ -z "$PII_GUARD_BUN" ]]; then
    # The escape hatch is honored HERE too, with the same >=12-char reason
    # gate the guard itself applies. Advertising an override in the message
    # below while ignoring it would be a hook that lies to its operator.
    PII_GUARD_REASON="${PII_GUARD_OK:-}"
    if [[ -n "$PII_GUARD_REASON" && "${#PII_GUARD_REASON}" -ge 12 ]]; then
        echo "[pii-guard] BYPASSED (no bun interpreter) — reason: $PII_GUARD_REASON" >&2
    else
        echo "" >&2
        echo "[pii-guard] BLOCKED — cannot run: no 'bun' interpreter found." >&2
        echo "" >&2
        echo "  Searched, in order:" >&2
        echo "    1. bun on \$PATH  (command -v bun)" >&2
        echo "    2. /opt/homebrew/bin/bun" >&2
        echo "    3. \$HOME/.bun/bin/bun" >&2
        echo "" >&2
        echo "  Staged content could NOT be checked for client identifiers, so" >&2
        echo "  this commit is blocked rather than allowed through unverified." >&2
        echo "" >&2
        echo "  Fix: install bun, or add its directory to PATH." >&2
        echo "  Override, with a reason of at least 12 characters:" >&2
        echo "    PII_GUARD_OK=\"bun unavailable, reviewed by hand\" git commit ..." >&2
        echo "" >&2
        exit 1
    fi
fi

if [[ -n "$PII_GUARD_BUN" ]] && ! "$PII_GUARD_BUN" scripts/pii-staged-content-guard.ts; then
    exit 1
fi

# Only run if marketplace.json or plugins/ changed
CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

if grep -qE '^(plugins/|\.claude-plugin/marketplace\.json)' <<<"$CHANGED_FILES"; then
    echo "🔍 Validating plugin registration..."

    if ! bun scripts/validate-plugins.mjs; then
        echo ""
        echo "💡 Tip: Run 'bun scripts/validate-plugins.mjs --fix' to see fix instructions"
        exit 1
    fi
else
    echo "⏭️  No plugin changes detected, skipping validation"
fi
HOOK

chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Pre-commit hook installed at $HOOKS_DIR/pre-commit"
echo ""
echo "The hook scans staged content for forbidden client identifiers on every"
echo "commit, and validates plugin registration when plugins/ changes."
echo ""
echo "PII denylist:  ${PII_DENYLIST:-$HOME/.claude/pii-denylist.txt}"
echo "               (kept outside this repo on purpose - the list is itself PII)"
echo ""
echo "To bypass the PII guard, with a recorded reason:"
echo "  PII_GUARD_OK=\"why this is safe\" git commit ..."
echo "To bypass every hook (use sparingly): git commit --no-verify"
