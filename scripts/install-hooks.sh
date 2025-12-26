#!/usr/bin/env bash
# Install git hooks for cc-skills development
# ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
#
# Usage: ./scripts/install-hooks.sh
#
# This installs a pre-commit hook that validates plugin registration
# to prevent the "Plugin not found in any marketplace" error.

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
# 1. All plugin directories are registered in marketplace.json
# 2. Marketplace entries have valid paths and required fields

set -euo pipefail

# Only run if marketplace.json or plugins/ changed
CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

if echo "$CHANGED_FILES" | grep -qE '^(plugins/|\.claude-plugin/marketplace\.json)'; then
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
echo "The hook will validate plugin registration on every commit."
echo "To bypass (use sparingly): git commit --no-verify"
