#!/usr/bin/env bash
# validate-hook-registration.sh — pre-release sanity check on hook wiring.
#
# As of v20.2.3+: plugin hooks are auto-loaded by Claude Code from each
# plugin's `hooks/hooks.json`. The user's settings.json should NOT
# contain ANY cc-skills marketplace-path entries — those would
# duplicate the auto-loaded ones.
#
# Checks:
#   1. settings.json paths exist on disk
#   2. No duplicate command strings within the same event-type array
#   3. ZERO cc-skills marketplace-path entries leak into settings.json
#
# Exit 0 on PASS. Exit 1 on FAIL.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS="${SETTINGS:-$HOME/.claude/settings.json}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }

errors=0
warnings=0

echo "→ Validating hook registration..."

if [[ ! -f "$SETTINGS" ]]; then
    warn "settings.json not found at $SETTINGS — skipping (fresh install?)"
    exit 0
fi

# ---- Check 1: settings.json paths exist on disk ----
echo "  [1/3] All settings.json hook commands resolve to existing files"
missing=0
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    path=$(printf '%s' "$cmd" | awk '{
        if ($1 == "bun" || $1 == "node" || $1 == "sh" || $1 == "bash") {
            print $2
        } else {
            print $1
        }
    }' | sed 's|^"||; s|"$||')
    path=$(printf '%s' "$path" | sed "s|\\\${HOME}|$HOME|g; s|\\\$HOME|$HOME|g")
    # ${CLAUDE_PLUGIN_ROOT} is plugin-relative — can't resolve statically here.
    # shellcheck disable=SC2016
    [[ "$path" == *'${CLAUDE_PLUGIN_ROOT}'* ]] && continue
    # shellcheck disable=SC2016
    [[ "$path" == *'$CLAUDE_PLUGIN_ROOT'* ]] && continue

    if [[ ! -e "$path" ]]; then
        fail "settings.json references missing file: $path"
        missing=$((missing + 1))
    fi
done < <(jq -r '
    [.hooks.PreToolUse[]?, .hooks.PostToolUse[]?, .hooks.Stop[]?, .hooks.SessionStart[]?, .hooks.UserPromptSubmit[]?, .hooks.PermissionRequest[]?]
    | .[].hooks[]? | .command // empty
' "$SETTINGS")
errors=$((errors + missing))
[[ $missing -eq 0 ]] && ok "All hook command paths exist"

# ---- Check 2: no duplicate commands within same event-type ----
echo "  [2/3] No duplicate hook commands within same event-type"
check2_errors=0
for evt in PreToolUse PostToolUse Stop SessionStart UserPromptSubmit PermissionRequest; do
    dups=$(jq -r --arg e "$evt" '
        [.hooks[$e][]?.hooks[]?.command]
        | group_by(.) | map(select(length > 1)) | map(.[0])
        | .[]
    ' "$SETTINGS" 2>/dev/null)
    if [[ -n "$dups" ]]; then
        while IFS= read -r d; do
            fail "$evt has duplicate command: $d"
            check2_errors=$((check2_errors + 1))
        done <<<"$dups"
    fi
done
errors=$((errors + check2_errors))
[[ $check2_errors -eq 0 ]] && ok "No within-event-type duplicates"

# ---- Check 3: zero cc-skills marketplace-path entries in settings.json ----
echo "  [3/3] No cc-skills marketplace-path entries leaked into settings.json"
leaked=$(jq '
    [.hooks // {} | to_entries[] | .value[]?.hooks[]?.command]
    | map(select(. != null and contains("marketplaces/cc-skills/plugins/")))
    | length
' "$SETTINGS")

if [[ "$leaked" -gt 0 ]]; then
    fail "$leaked cc-skills marketplace-path entr$([[ $leaked -eq 1 ]] && echo y || echo ies) found in settings.json"
    fail "Run: ./scripts/sync-hooks-to-settings.sh   (prunes them)"
    errors=$((errors + 1))
else
    ok "No marketplace-path leaks"
fi

echo ""
if [[ $errors -gt 0 ]]; then
    echo -e "${RED}✗ Hook registration validation FAILED ($errors error(s), $warnings warning(s))${NC}"
    exit 1
fi
if [[ $warnings -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Hook registration validation passed with $warnings warning(s)${NC}"
    exit 0
fi
echo -e "${GREEN}✓ Hook registration validation PASSED${NC}"
