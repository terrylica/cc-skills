#!/usr/bin/env bash
# Regression: tasks/lib/hook-command-parsing.sh is the ONLY hook-command parser. Pins the four sites migrated off hand-rolled parsers — the wildcard-matcher audit, the additionalContext pentad audit, the PreToolUse orchestration-candidacy ranker, and validate-plugins.mjs's settings shadow-hook check — by feeding each an env-prefixed hooks.json command that carries a trailing flag whose VALUE contains slashes. Every pre-migration parser resolves such a command to the flag value's last path segment or to the literal 'env'; the SSoT resolves it to the real script. Also asserts each migrated file sources/uses the SSoT and no longer contains its old inline parser.
#
# THE BUG CLASS THIS PINS
# -----------------------
# Every plugins/*/hooks/hooks.json command carries the load-bearing prefix
# `env -u AI_AGENT -u CLAUDECODE ` before the interpreter (proto shim → NDJSON
# banner on stdout → Claude Code's single JSON.parse throws → the hook's
# decision is SILENTLY DISCARDED at exit 0; 2,008 discarded decisions measured
# over three days, plus ~3,600 further banner-carrying events that survived).
#
# That prefix broke every parser that assumed "the first whitespace token is
# the interpreter". Two such parsers have already been caught mid-flight — the
# iter-92 audit, and the async-true audit, the latter found BY ACCIDENT and
# having audited ZERO hooks the whole time. The shapes that remained were
# subtler and stayed correct only by luck: today no marketplace hook command
# carries an ARGUMENT, so "the last /-separated segment of the whole command"
# happens to equal the script basename. Add one flag and the guess collapses.
#
# Each case below therefore uses a command of the shape
#
#     env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/X.ts --rules plugins/p/rules.d
#
# for which:
#     ${cmd##*/} then %% *          →  rules.d       (WRONG)
#     jq .command | split("/")[-1]  →  rules.d       (WRONG)
#     JS "first token containing /" →  /usr/bin/env  (WRONG, when env is a path)
#     the SSoT parser               →  X.ts          (RIGHT)
#
# WHAT THIS TEST ASSERTS — PRESENCE, NOT ABSENCE
# ----------------------------------------------
# docs/LESSONS.md (2026-06-10): an absence-only assertion passes just as
# happily when the feature is deleted. Every behavioural case below asserts a
# SPECIFIC diagnostic string and a SPECIFIC exit code, and the fixtures include
# both a hook that must be flagged and a hook that must NOT be.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d -t hook-command-parsing-ssot.XXXXXX)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

WILDCARD_AUDIT="$REPO_ROOT/tasks/audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation.sh"
STOP_AUDIT="$REPO_ROOT/tasks/audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json.sh"
RANKER_AUDIT="$REPO_ROOT/tasks/audit-pretooluse-hook-matcher-grouping-to-rank-orchestration-candidacy-by-bun-spawn-savings-from-iter80-cold-start-floor.sh"
ASYNC_AUDIT="$REPO_ROOT/tasks/audit-hooks-for-async-true-eligibility-via-blocking-decision-emission-detection"
PARSING_SSOT="$REPO_ROOT/tasks/lib/hook-command-parsing.sh"
PLUGIN_VALIDATOR="$REPO_ROOT/scripts/validate-plugins.mjs"

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

# assert_contains <name> <haystack> <needle>
# Matching is done in-process on the captured string — no `| grep -q` pipeline,
# whose SIGPIPE-killed producer inverts the boolean under `set -o pipefail`.
assert_contains() {
    if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "missing: $3"; fi
}

assert_absent() {
    if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "unexpectedly present: $3"; fi
}

assert_equals() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# The one command shape every case below is built from. Kept LITERAL —
# ${CLAUDE_PLUGIN_ROOT} must not expand here, it is the fixture.
# shellcheck disable=SC2016
ARG_CARRYING_COMMAND_TEMPLATE='env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/@SCRIPT@ --rules plugins/fixtureplug/rules.d'
arg_carrying_command_for() { echo "${ARG_CARRYING_COMMAND_TEMPLATE//@SCRIPT@/$1}"; }

echo "── Case 1: the SSoT parser resolves an arg-carrying env-prefixed command ──"

# shellcheck source=tasks/lib/hook-command-parsing.sh
source "$PARSING_SSOT"

case1_command="$(arg_carrying_command_for "wildcard-ok-hook.ts")"
assert_equals "SSoT basename ignores the --rules flag value" \
    "$(extract_hook_script_basename_from_hook_command "$case1_command")" \
    "wildcard-ok-hook.ts"
assert_equals "SSoT interpreter is bun, not env" \
    "$(extract_hook_interpreter_from_hook_command "$case1_command")" "bun"

# Documents the defect the migration removed: the pre-migration shape, applied
# to the very same string, yields the flag value's last path segment.
case1_pre_migration_last_slash_segment="${case1_command##*/}"
assert_equals "pre-migration last-slash-segment shape would have yielded rules.d" \
    "${case1_pre_migration_last_slash_segment%% *}" "rules.d"

echo
echo "── Case 2: wildcard-matcher audit honours an OK marker on an arg-carrying hook ──"

wildcard_fixture="$FIXTURE_ROOT/wildcard/plugins/fixtureplug/hooks"
mkdir -p "$wildcard_fixture"
cat >"$wildcard_fixture/wildcard-ok-hook.ts" <<'HOOK'
// WILDCARD-MATCHER-OK: genuinely tool-agnostic orphan reaper, must observe every call
console.log("{}");
HOOK
cat >"$wildcard_fixture/wildcard-violation-hook.ts" <<'HOOK'
console.log("{}");
HOOK

write_wildcard_hooks_json() {
    jq -n --arg cmd "$1" '{hooks:{PostToolUse:[{matcher:"*",hooks:[{type:"command",command:$cmd}]}]}}' \
        >"$wildcard_fixture/hooks.json"
}

write_wildcard_hooks_json "$(arg_carrying_command_for "wildcard-ok-hook.ts")"
case2_rc=0
case2_out=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_ROOT/wildcard" bash "$WILDCARD_AUDIT" 2>&1) || case2_rc=$?
assert_equals "audit exits 0 for a marker-carrying wildcard hook" "$case2_rc" "0"
assert_contains "hook is classified WITH-OK-MARKER by its real basename" "$case2_out" \
    "WILDCARD-WITH-OK-MARKER: fixtureplug/wildcard-ok-hook.ts"
assert_absent "no flag-value segment leaks into the report" "$case2_out" "rules.d"

echo
echo "── Case 3: wildcard-matcher audit still BLOCKS an unmarked wildcard hook ──"

write_wildcard_hooks_json "$(arg_carrying_command_for "wildcard-violation-hook.ts")"
case3_rc=0
case3_out=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_ROOT/wildcard" bash "$WILDCARD_AUDIT" 2>&1) || case3_rc=$?
assert_equals "audit exits non-zero on a real violation" "$case3_rc" "1"
assert_contains "violation names the real script" "$case3_out" "wildcard-violation-hook.ts"
assert_contains "violation is counted, not skipped" "$case3_out" \
    "WILDCARD-VIOLATION (unjustified broad scope):      1"

echo
echo "── Case 4: additionalContext pentad audit scans an arg-carrying Stop hook ──"

stop_fixture="$FIXTURE_ROOT/stop/plugins/fixtureplug/hooks"
mkdir -p "$stop_fixture"
cat >"$stop_fixture/stop-emits-additional-context.ts" <<'HOOK'
const out = { hookSpecificOutput: { additionalContext: "silently dropped by Claude Code" } };
console.log(JSON.stringify(out));
HOOK
jq -n --arg cmd "$(arg_carrying_command_for "stop-emits-additional-context.ts")" \
    '{hooks:{Stop:[{hooks:[{type:"command",command:$cmd}]}]}}' >"$stop_fixture/hooks.json"

case4_rc=0
case4_out=$(AUDIT_REPO_ROOT_OVERRIDE="$FIXTURE_ROOT/stop" bash "$STOP_AUDIT" 2>&1) || case4_rc=$?
assert_equals "audit exits non-zero on the injected emission" "$case4_rc" "1"
# The pre-migration parser resolved this command to `rules.d`, found no such
# source file, and aborted before ever printing a summary — the vacuous-gate
# signature. Asserting the SCAN COUNT is what distinguishes "clean" from
# "never looked".
assert_contains "exactly one pentad hook was actually scanned" "$case4_out" \
    "Total registered pentad-member hooks scanned: 1"
assert_contains "the emission is reported as a violation" "$case4_out" \
    "EMISSION-VIOLATION (silent-drop risk):         1"
assert_absent "the hook was not skipped as SOURCE-NOT-FOUND" "$case4_out" "SOURCE-NOT-FOUND"

echo
echo "── Case 5: orchestration-candidacy ranker groups by real basenames ──"

ranker_root="$FIXTURE_ROOT/ranker"
mkdir -p "$ranker_root/tasks/lib" "$ranker_root/plugins/fixtureplug/hooks"
cp "$PARSING_SSOT" "$ranker_root/tasks/lib/"
cp "$RANKER_AUDIT" "$ranker_root/tasks/ranker.sh"
jq -n \
    --arg a "$(arg_carrying_command_for "guard-alpha.ts")" \
    --arg b "$(arg_carrying_command_for "guard-beta.ts")" \
    --arg c "$(arg_carrying_command_for "guard-gamma.ts")" \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[
        {type:"command",command:$a},
        {type:"command",command:$b},
        {type:"command",command:$c}]}]}}' \
    >"$ranker_root/plugins/fixtureplug/hooks/hooks.json"

case5_out=$(bash "$ranker_root/tasks/ranker.sh" 2>&1)
assert_contains "all three distinct hook basenames appear in the group" "$case5_out" \
    "guard-alpha.ts,guard-beta.ts,guard-gamma.ts"
# Pre-migration this row read `guard-gamma.ts,rules.d,rules.d` — three distinct
# hooks collapsed onto one flag-value segment, which is garbage input to the
# orchestration decision the ranker exists to inform.
assert_absent "no flag-value segment is mistaken for a script" "$case5_out" "rules.d"

echo
echo "── Case 6: an unparseable command is reported, never silently dropped ──"

jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[
    {type:"command",command:"env -u AI_AGENT -u CLAUDECODE"}]}]}}' \
    >"$ranker_root/plugins/fixtureplug/hooks/hooks.json"
case6_out=$(bash "$ranker_root/tasks/ranker.sh" 2>&1)
assert_contains "ranker warns loudly on an unparseable command" "$case6_out" \
    "RANKER WARNING: could not parse hook command into a script path"
assert_contains "the unparseable entry is still counted, marked as such" "$case6_out" \
    "<UNPARSEABLE-COMMAND>"

echo
echo "── Case 7: settings shadow-hook check uses the same parse ──"

# Two UNRELATED hooks, both invoked through an absolute /usr/bin/env. The
# pre-migration JS parser took "the first whitespace token containing a /",
# i.e. `/usr/bin/env`, giving BOTH the basename `env` — a fabricated shadow.
cat >"$FIXTURE_ROOT/settings-no-shadow.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"/usr/bin/env -u AI_AGENT -u CLAUDECODE bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/pretooluse-git-worktree-guard.ts --rules /etc/claude/rules.d"},
  {"type":"command","command":"/usr/bin/env -u AI_AGENT -u CLAUDECODE bun $HOME/.claude/automation/totally-unrelated-third-party-hook.ts --rules /etc/claude/rules.d"}
]}]}}
JSON
cat >"$FIXTURE_ROOT/settings-real-shadow.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"/usr/bin/env -u AI_AGENT -u CLAUDECODE bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/pretooluse-git-worktree-guard.ts --rules /etc/claude/rules.d"},
  {"type":"command","command":"/usr/bin/env -u AI_AGENT -u CLAUDECODE bun $HOME/.claude/automation/pretooluse-git-worktree-guard.ts --rules /etc/claude/rules.d"}
]}]}}
JSON

cat >"$FIXTURE_ROOT/shadow-probe.mjs" <<PROBE
import { validateSettingsHookShadows } from "$PLUGIN_VALIDATOR";
const { errors } = validateSettingsHookShadows(process.argv[2]);
console.log(JSON.stringify({ count: errors.length, errors }));
PROBE

case7_no_shadow=$(bun "$FIXTURE_ROOT/shadow-probe.mjs" "$FIXTURE_ROOT/settings-no-shadow.json")
assert_contains "unrelated env-prefixed hooks are NOT reported as shadows" \
    "$case7_no_shadow" '"count":0'

case7_real_shadow=$(bun "$FIXTURE_ROOT/shadow-probe.mjs" "$FIXTURE_ROOT/settings-real-shadow.json")
assert_contains "a genuine same-basename shadow IS still reported" \
    "$case7_real_shadow" '"count":1'
assert_contains "the shadow is named by its real basename" \
    "$case7_real_shadow" "same basename 'pretooluse-git-worktree-guard.ts'"

echo
echo "── Case 8: no migrated site keeps a private copy of the parser ──"

assert_contains "wildcard audit sources the parsing SSoT" \
    "$(cat "$WILDCARD_AUDIT")" "lib/hook-command-parsing.sh"
assert_contains "stop audit sources the parsing SSoT" \
    "$(cat "$STOP_AUDIT")" "lib/hook-command-parsing.sh"
assert_contains "ranker sources the parsing SSoT" \
    "$(cat "$RANKER_AUDIT")" "lib/hook-command-parsing.sh"
assert_contains "async-true audit sources the parsing SSoT" \
    "$(cat "$ASYNC_AUDIT")" "lib/hook-command-parsing.sh"

# The specific inline shapes each site used before the migration, matched in
# CODE position (a `local` declaration, a jq expression, a JS expression) so
# the prose above cannot satisfy or trip these assertions.
assert_absent "wildcard audit no longer declares its own basename_with_args" \
    "$(cat "$WILDCARD_AUDIT")" 'local basename_with_args='
assert_absent "stop audit no longer declares its own basename_with_args" \
    "$(cat "$STOP_AUDIT")" 'local basename_with_args='
assert_absent "ranker no longer splits .command inside jq" \
    "$(cat "$RANKER_AUDIT")" '(.command | split("/")[-1])'
assert_absent "validate-plugins.mjs has no second, inline tokenizer" \
    "$(cat "$PLUGIN_VALIDATOR")" 'parts.find(p => p.includes("/"))'

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — tasks/lib/hook-command-parsing.sh is the sole parser; all four migrated sites resolve arg-carrying env-prefixed commands correctly and still gate"
else
    echo "✗ FAILED — $failures assertion(s)"
    exit 1
fi
