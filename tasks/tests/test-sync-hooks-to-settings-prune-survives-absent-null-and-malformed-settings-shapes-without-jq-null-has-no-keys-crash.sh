#!/usr/bin/env bash
#MISE description="Regression: sync-hooks-to-settings.sh prunes cc-skills entries and never crashes on absent/null/malformed settings.json shapes (issue #103)"
#
# A settings.json is user-authored, so every level may be absent or null. jq's
# `to_entries`/`map` abort on null, and the pre-fix prune filter dereferenced
# `.hooks` unguarded — so `sync-hooks-to-settings.sh` died with
# `jq: error: null (null) has no keys` for any user whose settings.json simply
# had no `hooks` key. Reported from a clean Quick Install (issue #103).
#
# Each case below asserts the script exits 0 AND leaves valid JSON behind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/sync-hooks-to-settings.sh"
FIXTURE_HOME_ROOT="$(mktemp -d -t sync-hooks-settings-shapes.XXXXXX)"
trap 'rm -rf "$FIXTURE_HOME_ROOT"' EXIT

CC_SKILLS_HOOK_COMMAND='bun /Users/x/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/a.ts'
FOREIGN_HOOK_COMMAND='bun /Users/x/.claude/other/hook.ts'

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

# Run the script against a synthetic settings.json; echo the resulting file.
run_case() {
    local case_name="$1" settings_json="$2" expected_remaining="$3"
    local case_home="$FIXTURE_HOME_ROOT/$case_name"
    mkdir -p "$case_home/.claude"
    printf '%s' "$settings_json" > "$case_home/.claude/settings.json"

    local rc=0
    HOME="$case_home" "$SCRIPT_UNDER_TEST" >/dev/null 2>"$case_home/stderr.txt" || rc=$?

    if [[ $rc -ne 0 ]]; then
        fail "$case_name" "exit $rc — $(tr -d '\n' < "$case_home/stderr.txt" | head -c 200)"
        return
    fi
    if ! jq empty "$case_home/.claude/settings.json" 2>/dev/null; then
        fail "$case_name" "settings.json is no longer valid JSON"
        return
    fi

    local remaining
    remaining=$(jq --arg f 'marketplaces/cc-skills/plugins/' '
        [ (if (.hooks | type) == "object" then .hooks else {} end)
          | to_entries[] | (.value // [])[] | (.hooks // [])[] | (.command // "") ]
        | map(select(contains($f))) | length
    ' "$case_home/.claude/settings.json")

    if [[ "$remaining" != "$expected_remaining" ]]; then
        fail "$case_name" "expected $expected_remaining cc-skills entries remaining, got $remaining"
        return
    fi
    pass "$case_name"
}

echo "→ sync-hooks-to-settings.sh settings-shape regression (issue #103)"

# The reported crash: a settings.json with no `hooks` key at all.
run_case "absent-hooks-key" '{"model":"opus","permissions":{"allow":[]}}' 0

# Explicit nulls at each level the filter walks.
run_case "null-hooks" '{"hooks":null}' 0
run_case "null-matcher-list" '{"hooks":{"PreToolUse":null}}' 0
run_case "matcher-entry-without-hooks-array" '{"hooks":{"PreToolUse":[{"matcher":"Bash"}]}}' 0
run_case "hook-entry-without-command" '{"hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command"}]}]}}' 0

# Empty and malformed-but-parseable shapes must pass through untouched.
run_case "empty-object" '{}' 0
run_case "empty-hooks-object" '{"hooks":{}}' 0
run_case "non-object-hooks-is-left-alone" '{"hooks":[]}' 0

# The actual job: cc-skills marketplace entries are removed, foreign ones kept.
run_case "prunes-cc-skills-entry" \
    "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"$CC_SKILLS_HOOK_COMMAND\"}]}]}}" 0

MIXED_SETTINGS="{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"$CC_SKILLS_HOOK_COMMAND\"},{\"type\":\"command\",\"command\":\"$FOREIGN_HOOK_COMMAND\"}]}]}}"
run_case "keeps-foreign-entry" "$MIXED_SETTINGS" 0

# The foreign hook must SURVIVE — pruning must not empty out unrelated config.
MIXED_HOME="$FIXTURE_HOME_ROOT/keeps-foreign-entry"
surviving=$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command] | length' "$MIXED_HOME/.claude/settings.json")
if [[ "$surviving" == "1" ]]; then
    pass "foreign hook survives the prune"
else
    fail "foreign hook survives the prune" "expected 1 surviving hook, got $surviving"
fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — every settings shape pruned cleanly, no jq null crash"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
