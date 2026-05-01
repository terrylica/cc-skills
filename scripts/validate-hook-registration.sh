#!/usr/bin/env bash
# validate-hook-registration.sh — pre-release sanity check on hook wiring.
#
# Catches the failure modes that bit us in v17.0.0:
#   1. Stale paths in settings.json (e.g., dir renamed but settings.json
#      still references the old path).
#   2. Duplicate command strings within the same event-type array
#      (sync logic regression).
#   3. SKIP_HOOK_SYNC typos — names that don't match plugin directories.
#   4. Coverage gap — a plugin has hooks.json but is NEITHER in
#      SKIP_HOOK_SYNC NOR has its hooks present in settings.json
#      (silent miss; hooks won't fire).
#   5. Contradiction — a plugin is BOTH in SKIP_HOOK_SYNC AND in
#      settings.json (skip-list isn't being honored).
#
# Exit 0 on PASS. Exit 1 on FAIL. Run via release:preflight.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS="${SETTINGS:-$HOME/.claude/settings.json}"
MARKETPLACE_DIR="${MARKETPLACE_DIR:-$HOME/.claude/plugins/marketplaces/cc-skills}"
SYNC_SCRIPT="${SYNC_SCRIPT:-$REPO_ROOT/scripts/sync-hooks-to-settings.sh}"

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

# Extract SKIP_HOOK_SYNC list from sync script (single source of truth).
# Portable to bash 3.2 (macOS default) — no mapfile.
skip_list=()
while IFS= read -r line; do
    [[ -n "$line" ]] && skip_list+=("$line")
done < <(awk '
    /^SKIP_HOOK_SYNC=\(/ { in_array=1; next }
    in_array && /^\)/ { in_array=0; next }
    in_array { gsub(/[ \t]+#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0) print $0 }
' "$SYNC_SCRIPT")

is_skipped() {
    local p="$1"
    # Empty array safe-guard for bash 3.2 with set -u
    [[ "${#skip_list[@]}" -eq 0 ]] && return 1
    local s
    for s in "${skip_list[@]}"; do
        [[ "$s" == "$p" ]] && return 0
    done
    return 1
}

# ---- Check 1: skip-list entries exist as real plugin dirs ----
echo "  [1/5] SKIP_HOOK_SYNC entries match real plugins"
check1_errors=0
if [[ "${#skip_list[@]}" -gt 0 ]]; then
    for skip in "${skip_list[@]}"; do
        if [[ ! -d "$REPO_ROOT/plugins/$skip" ]]; then
            fail "SKIP_HOOK_SYNC has '$skip' but plugins/$skip does not exist"
            check1_errors=$((check1_errors + 1))
        fi
    done
fi
errors=$((errors + check1_errors))
if [[ $check1_errors -eq 0 && "${#skip_list[@]}" -gt 0 ]]; then
    ok "${#skip_list[@]} skip-list entr$([[ ${#skip_list[@]} -eq 1 ]] && echo y || echo ies) verified"
fi

# ---- Check 2: settings.json paths exist on disk ----
echo "  [2/5] All settings.json hook commands resolve to existing files"
missing=0
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    # Extract the script path from the command. Strip leading interpreter
    # token (bun/node/sh/bash) and any surrounding quotes / args. Use awk
    # for portable parsing — BSD sed alternation is unreliable.
    path=$(printf '%s' "$cmd" | awk '{
        # If the first word is a known interpreter, take the second word.
        if ($1 == "bun" || $1 == "node" || $1 == "sh" || $1 == "bash") {
            print $2
        } else {
            print $1
        }
    }' | sed 's|^"||; s|"$||')
    # Expand $HOME / ${HOME}
    path=$(printf '%s' "$path" | sed "s|\\\${HOME}|$HOME|g; s|\\\$HOME|$HOME|g")
    # ${CLAUDE_PLUGIN_ROOT} is plugin-relative — can't resolve statically here.
    # Skip those (they're auto-discovered, not synced literal paths).
    # shellcheck disable=SC2016  # literal substring match, no expansion intended
    [[ "$path" == *'${CLAUDE_PLUGIN_ROOT}'* ]] && continue
    # shellcheck disable=SC2016
    [[ "$path" == *'$CLAUDE_PLUGIN_ROOT'* ]] && continue

    if [[ ! -e "$path" ]]; then
        fail "settings.json references missing file: $path"
        missing=$((missing + 1))
    fi
done < <(jq -r '
    [.hooks.PreToolUse[]?, .hooks.PostToolUse[]?, .hooks.Stop[]?]
    | .[].hooks[]? | .command // empty
' "$SETTINGS")
errors=$((errors + missing))
[[ $missing -eq 0 ]] && ok "All hook command paths exist"

# ---- Check 3: no duplicate commands within same event-type ----
echo "  [3/5] No duplicate hook commands within same event-type"
check3_errors=0
for evt in PreToolUse PostToolUse Stop; do
    dups=$(jq -r --arg e "$evt" '
        [.hooks[$e][]?.hooks[]?.command]
        | group_by(.) | map(select(length > 1)) | map(.[0])
        | .[]
    ' "$SETTINGS" 2>/dev/null)
    if [[ -n "$dups" ]]; then
        while IFS= read -r d; do
            fail "$evt has duplicate command: $d"
            check3_errors=$((check3_errors + 1))
        done <<<"$dups"
    fi
done
errors=$((errors + check3_errors))
[[ $check3_errors -eq 0 ]] && ok "No within-event-type duplicates"

# ---- Check 4 + 5: coverage gap + contradiction ----
echo "  [4/5] Coverage: every plugin with hooks.json is classified"
echo "  [5/5] No contradictions (skipped plugins absent from settings.json)"
for hooks_file in "$REPO_ROOT"/plugins/*/hooks/hooks.json; do
    [[ -f "$hooks_file" ]] || continue
    plugin=$(basename "$(dirname "$(dirname "$hooks_file")")")

    # Does plugin declare any hooks?
    has_hooks=$(jq '[.hooks // {} | to_entries[] | .value | length] | add // 0' "$hooks_file" 2>/dev/null)
    [[ "${has_hooks:-0}" -eq 0 ]] && continue

    # Is plugin in settings.json (any hook command containing the plugin name)?
    in_settings=$(jq --arg p "$plugin" '
        [.hooks.PreToolUse[]?, .hooks.PostToolUse[]?, .hooks.Stop[]?]
        | .[].hooks[]?.command // empty
        | select(test("plugins/" + $p + "/"))
    ' "$SETTINGS" 2>/dev/null | head -1)

    if is_skipped "$plugin"; then
        if [[ -n "$in_settings" ]]; then
            fail "Contradiction: '$plugin' is in SKIP_HOOK_SYNC but its hooks ARE in settings.json"
            errors=$((errors + 1))
        fi
    else
        if [[ -z "$in_settings" ]]; then
            warn "Coverage gap: '$plugin' has hooks.json, NOT in SKIP_HOOK_SYNC, but its hooks are NOT in settings.json. Either run release:sync or add to SKIP_HOOK_SYNC."
            warnings=$((warnings + 1))
        fi
    fi
done
[[ $errors -eq 0 && $warnings -eq 0 ]] && ok "Plugin/skip-list/settings.json all consistent"

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
