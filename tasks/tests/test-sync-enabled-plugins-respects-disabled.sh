#!/usr/bin/env bash
# Regression: a release never switches a plugin the user disabled back on (enabledPlugins false survives sync-enabled-plugins.sh)
#
# sync-enabled-plugins.sh runs twice in every release (pre-sync and sync) to add an `enabledPlugins`
# key for each plugin that is new in the marketplace. It decided "new" with
# `jq '.enabledPlugins[$key] // "missing"'`, and jq's `//` yields its right-hand side for `false`
# as well as for null and absent. So a plugin the user had set to `false` looked missing and was
# set to `true`: one release re-enabled 18 plugins two minutes after they had been disabled, while
# the disabled plugins of other marketplaces in the same file were left alone.
#
# The script now tests presence with has(). This file drives the real script against synthetic
# settings in a throwaway HOME, and pins the release scripts against the `//` presence test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/sync-enabled-plugins.sh"
FIXTURE_ROOT="$(mktemp -d -t sync-enabled-plugins.XXXXXX)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

# A marketplace of three plugins, in a directory the script is run from (it reads
# .claude-plugin/marketplace.json relative to the working directory).
MARKETPLACE_ROOT="$FIXTURE_ROOT/marketplace"
mkdir -p "$MARKETPLACE_ROOT/.claude-plugin"
printf '%s' '{"name":"cc-skills","plugins":[{"name":"alpha"},{"name":"beta"},{"name":"gamma"}]}' \
    > "$MARKETPLACE_ROOT/.claude-plugin/marketplace.json"

new_home() {
    local home="$FIXTURE_ROOT/$1"
    mkdir -p "$home/.claude"
    printf '%s' "$2" > "$home/.claude/settings.json"
    echo "$home"
}
run_sync() { (cd "$MARKETPLACE_ROOT" && HOME="$1" "$SYNC_SCRIPT"); }
setting() { jq -c "$2" "$1/.claude/settings.json"; }
stray_files() { find "$1/.claude" -mindepth 1 -maxdepth 1 ! -name settings.json | wc -l | tr -d ' '; }

echo "→ sync-enabled-plugins.sh respects a disabled plugin"

# 1. The reported case: every plugin has a key, some are false. Nothing may change.
home=$(new_home all-present '{"model":"opus","enabledPlugins":{"alpha@cc-skills":true,"beta@cc-skills":false,"gamma@cc-skills":false,"other@elsewhere":false},"skillListingBudgetFraction":0.02}')
before=$(cat "$home/.claude/settings.json")
ln "$home/.claude/settings.json" "$home/.claude/original-file"   # a second name for the same file
output=$(run_sync "$home")
after=$(cat "$home/.claude/settings.json")
same_file=$([[ "$home/.claude/settings.json" -ef "$home/.claude/original-file" ]] && echo yes || echo no)
if [[ "$(setting "$home" '[.enabledPlugins["beta@cc-skills"], .enabledPlugins["gamma@cc-skills"]]')" == "[false,false]" ]]; then
    pass "plugins set to false stay false"
else
    fail "plugins set to false stay false" "enabledPlugins is now $(setting "$home" '.enabledPlugins')"
fi
if [[ "$after" == "$before" && "$same_file" == "yes" ]]; then
    pass "a run with no new plugin leaves settings.json byte-identical and does not replace the file"
else
    fail "a run with no new plugin leaves settings.json byte-identical and does not replace the file" "content changed=$([[ "$after" == "$before" ]] && echo no || echo yes) still the same file=$same_file"
fi
if [[ "$output" == *"2 disabled by you and left off"* && "$output" != *"Enabled new plugin"* ]]; then
    pass "the report counts the disabled plugins and claims no new plugin"
else
    fail "the report counts the disabled plugins and claims no new plugin" "output: $output"
fi

# 2. A genuinely new plugin is still enabled, in the same run that leaves a disabled one off.
home=$(new_home one-new '{"model":"opus","enabledPlugins":{"alpha@cc-skills":true,"beta@cc-skills":false,"other@elsewhere":false},"skillListingBudgetFraction":0.02}')
chmod 600 "$home/.claude/settings.json"
output=$(run_sync "$home")
got=$(setting "$home" '[.enabledPlugins["alpha@cc-skills"], .enabledPlugins["beta@cc-skills"], .enabledPlugins["gamma@cc-skills"], .enabledPlugins["other@elsewhere"], .model, .skillListingBudgetFraction]')
if [[ "$got" == '[true,false,true,false,"opus",0.02]' ]]; then
    pass "a new plugin is enabled; disabled plugins, other marketplaces and unrelated keys are untouched"
else
    fail "a new plugin is enabled; disabled plugins, other marketplaces and unrelated keys are untouched" "got $got"
fi
if [[ "$output" == *"+ Enabled new plugin: gamma@cc-skills"* && "$output" != *"beta@cc-skills"* ]]; then
    pass "only the new plugin is reported as enabled"
else
    fail "only the new plugin is reported as enabled" "output: $output"
fi
mode=$(find "$home/.claude/settings.json" -perm 600 | wc -l | tr -d ' ')
if [[ "$mode" == "1" && "$(stray_files "$home")" == "0" ]]; then
    pass "the rewrite keeps the file's permissions and leaves no temporary file behind"
else
    fail "the rewrite keeps the file's permissions and leaves no temporary file behind" "mode-600=$mode stray=$(stray_files "$home")"
fi

# 3. Second run is a no-op (idempotent).
before=$(cat "$home/.claude/settings.json")
run_sync "$home" >/dev/null
if [[ "$(cat "$home/.claude/settings.json")" == "$before" ]]; then
    pass "a second run changes nothing"
else
    fail "a second run changes nothing" "settings.json differs after the second run"
fi

# 4. No enabledPlugins key at all (a fresh settings.json): every plugin is added as true.
home=$(new_home no-key '{"model":"opus"}')
run_sync "$home" >/dev/null
got=$(setting "$home" '[.model, (.enabledPlugins | to_entries | map(select(.value == true)) | length)]')
if [[ "$got" == '["opus",3]' ]]; then
    pass "a settings.json without enabledPlugins gets all three plugins enabled"
else
    fail "a settings.json without enabledPlugins gets all three plugins enabled" "got $got"
fi

# 5. enabledPlugins that is not an object is malformed input: leave the file alone, exit 0.
home=$(new_home malformed '{"enabledPlugins":["alpha@cc-skills"]}')
before=$(cat "$home/.claude/settings.json")
rc=0
run_sync "$home" >/dev/null || rc=$?
if [[ $rc -eq 0 && "$(cat "$home/.claude/settings.json")" == "$before" ]]; then
    pass "a non-object enabledPlugins is left untouched"
else
    fail "a non-object enabledPlugins is left untouched" "rc=$rc"
fi

# 6. Source pin: no release script may test enabledPlugins presence with `//` again. The verify
#    phase had the same expression and would fail a release for every disabled plugin.
offenders=$(grep -nE 'enabledPlugins\[[^]]*\][[:space:]]*//' \
    "$REPO_ROOT/scripts/sync-enabled-plugins.sh" "$REPO_ROOT"/tasks/release/* | grep -vE ':[0-9]+:[[:space:]]*#' || true)
if [[ -z "$offenders" ]]; then
    pass "no release script tests enabledPlugins presence with jq's // operator"
else
    fail "no release script tests enabledPlugins presence with jq's // operator" "$offenders"
fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — a release adds new plugins and never re-enables a disabled one"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
