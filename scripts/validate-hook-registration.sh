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
# EVENT COVERAGE — derived, never hardcoded.
# Until 2026-09-02 checks 1 and 2 each carried their OWN hardcoded list of six
# events (PreToolUse PostToolUse Stop SessionStart UserPromptSubmit
# PermissionRequest). SessionEnd, SubagentStop, Notification and PreCompact were
# in NEITHER list, so a hook registered under one of them with a nonexistent
# command path sailed past both checks and the script still printed an
# unqualified "✓ All hook command paths exist" — a vacuous green. Two copies of
# a list is how they drift; a hardcoded list is how events get missed. The event
# set is now read from the settings document itself (`.hooks | keys`), so every
# event Claude Code writes — including ones that do not exist yet — is covered,
# and BOTH checks consume that single derived list.
#
# Exit 0 on PASS. Exit 1 on FAIL.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS="${SETTINGS:-$HOME/.claude/settings.json}"

# Hook-command parsing SSoT (tasks/lib/hook-command-parsing.sh): strips the
# load-bearing `env -u AI_AGENT -u CLAUDECODE` prefix, the interpreter and its
# flags, and any `bun run`/`uv run` subcommand. The old inline awk assumed the
# first token was the interpreter, so an env-prefixed command yielded the
# literal path "env".
HOOK_COMMAND_PARSING_LIB="$REPO_ROOT/tasks/lib/hook-command-parsing.sh"
if [[ ! -f "$HOOK_COMMAND_PARSING_LIB" ]]; then
    echo "✗ missing hook-command parsing SSoT: $HOOK_COMMAND_PARSING_LIB" >&2
    exit 1
fi
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=tasks/lib/hook-command-parsing.sh
source "$HOOK_COMMAND_PARSING_LIB"

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

# ---- Derived event coverage: the ONE list both checks below consume ----
# Every key under `.hooks` is an event Claude Code will fire. Reading them off
# the document means no event can be silently excluded from checks 1 and 2.
hook_event_names=()
while IFS= read -r hook_event_name; do
    [[ -n "$hook_event_name" ]] && hook_event_names+=("$hook_event_name")
done < <(jq -r 'if ((.hooks? // null) | type) == "object" then (.hooks | keys[]) else empty end' "$SETTINGS" 2>/dev/null)

# Every `command` string registered under one event, robust to null/malformed
# levels (settings.json is user-authored — see issue #103).
hook_commands_for_event() {
    jq -r --arg e "$1" '
        ((.hooks? // {})[$e] // [])
        | if type == "array" then .[] else empty end
        | ((.hooks? // []) | if type == "array" then .[] else empty end)
        | .command // empty
    ' "$SETTINGS" 2>/dev/null
}

# The filesystem path a hook command actually executes, or "" when it cannot be
# resolved statically. Uses the parsing SSoT, then unquotes and expands $HOME/~.
resolve_hook_command_script_path() {
    local hook_script_path
    hook_script_path=$(extract_hook_script_path_from_hook_command "$1")
    hook_script_path=${hook_script_path%\"}; hook_script_path=${hook_script_path#\"}
    hook_script_path=${hook_script_path%\'}; hook_script_path=${hook_script_path#\'}
    hook_script_path=${hook_script_path//\$\{HOME\}/$HOME}
    hook_script_path=${hook_script_path//\$HOME/$HOME}
    # A leading tilde is LITERAL inside a JSON command string (no shell expands
    # it before Claude Code runs the hook) — expand it ourselves before testing.
    local literal_tilde_slash_prefix
    literal_tilde_slash_prefix=$(printf '\176/')
    [[ "${hook_script_path:0:2}" == "$literal_tilde_slash_prefix" ]] && hook_script_path="$HOME/${hook_script_path:2}"
    printf '%s' "$hook_script_path"
}

if [[ ${#hook_event_names[@]} -eq 0 ]]; then
    warn "settings.json declares no hook events — checks 1 and 2 have nothing to inspect"
fi

# ---- Check 1: settings.json paths exist on disk ----
echo "  [1/3] All settings.json hook commands resolve to existing files"
missing=0
commands_checked=0
for evt in ${hook_event_names[@]+"${hook_event_names[@]}"}; do
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        path=$(resolve_hook_command_script_path "$cmd")
        [[ -z "$path" ]] && continue
        # ${CLAUDE_PLUGIN_ROOT} is plugin-relative — can't resolve statically here.
        # shellcheck disable=SC2016
        [[ "$path" == *'${CLAUDE_PLUGIN_ROOT}'* ]] && continue
        # shellcheck disable=SC2016
        [[ "$path" == *'$CLAUDE_PLUGIN_ROOT'* ]] && continue

        commands_checked=$((commands_checked + 1))
        if [[ ! -e "$path" ]]; then
            fail "settings.json $evt references missing file: $path"
            missing=$((missing + 1))
        fi
    done < <(hook_commands_for_event "$evt")
done
errors=$((errors + missing))
# Qualified on purpose: "All hook command paths exist" over zero inspected
# commands is the same green as over a hundred.
[[ $missing -eq 0 ]] && ok "All $commands_checked resolvable hook command path(s) exist (events: ${hook_event_names[*]:-none})"

# ---- Check 2: no duplicate commands within same event-type ----
echo "  [2/3] No duplicate hook commands within same event-type"
check2_errors=0
for evt in ${hook_event_names[@]+"${hook_event_names[@]}"}; do
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
