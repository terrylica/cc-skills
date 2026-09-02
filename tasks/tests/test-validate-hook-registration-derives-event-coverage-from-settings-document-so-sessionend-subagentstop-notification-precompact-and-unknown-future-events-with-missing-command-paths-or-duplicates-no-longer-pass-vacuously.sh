#!/usr/bin/env bash
#MISE description="Regression: scripts/validate-hook-registration.sh derives its hook-event coverage from the settings document instead of two hardcoded six-event lists, so a nonexistent command path or a within-event duplicate under SessionEnd/SubagentStop/Notification/PreCompact (or any future event) is now an ERROR instead of an unqualified green"
#
# THE BUG THIS PINS (found 2026-09-02 by a vacuous-gate sweep)
# -----------------------------------------------------------
# validate-hook-registration.sh hardcoded the SAME six events TWICE — once in a
# jq filter for check 1 and once in a `for evt in …` for check 2:
#
#     PreToolUse PostToolUse Stop SessionStart UserPromptSubmit PermissionRequest
#
# SessionEnd, SubagentStop, Notification and PreCompact appeared in NEITHER.
# A settings.json containing only those four events, each pointing at a
# nonexistent script, exited 0 and printed "✓ All hook command paths exist".
# Two hardcoded copies of one list is how coverage drifts; a hardcoded list at
# all is how new Claude Code events get missed.
#
# WHAT THIS TEST ASSERTS — PRESENCE, NOT ABSENCE
# ----------------------------------------------
# docs/LESSONS.md (2026-06-10): an absence-only assertion ("no errors") passes
# just as happily when the feature is deleted. Every case below that feeds the
# gate a DELIBERATELY BAD fixture asserts the gate exits non-zero AND that the
# specific diagnostic text is present. Delete the derivation and cases 1, 2, 4
# and 5 fail immediately.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/validate-hook-registration.sh"
FIXTURE_ROOT="$(mktemp -d -t validate-hook-registration-event-coverage.XXXXXX)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

# A path that provably does not exist, inside the throwaway fixture dir.
MISSING="$FIXTURE_ROOT/definitely-absent"
# A path that provably DOES exist, for the negative-control case.
EXISTING="$FIXTURE_ROOT/present-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$EXISTING"
chmod +x "$EXISTING"

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

# run_case <name> <settings-json> <expected-exit> [required-substring …]
run_case() {
    local case_name="$1" settings_json="$2" expected_exit="$3"
    shift 3

    local case_dir="$FIXTURE_ROOT/$case_name"
    mkdir -p "$case_dir"
    printf '%s' "$settings_json" > "$case_dir/settings.json"

    local rc=0 output
    output=$(REPO_ROOT="$REPO_ROOT" SETTINGS="$case_dir/settings.json" \
        bash "$SCRIPT_UNDER_TEST" 2>&1) || rc=$?

    # Matching is done in-process on the captured string — no `| grep -q`
    # pipeline, whose SIGPIPE-killed producer inverts the boolean under
    # `set -o pipefail` (see the sigpipe-pipefail reminder hook).
    local flattened="${output//$'\n'/|}"

    if [[ "$rc" != "$expected_exit" ]]; then
        fail "$case_name" "expected exit $expected_exit, got $rc — output: ${flattened:0:400}"
        return
    fi

    local required
    for required in "$@"; do
        if [[ "$output" != *"$required"* ]]; then
            fail "$case_name" "output is missing required text: $required — output: ${flattened:0:400}"
            return
        fi
    done
    pass "$case_name"
}

# Build a settings.json whose ONLY events are the four the old hardcoded lists
# omitted, each with a bogus command path.
four_omitted_events_settings() {
    local command_prefix="$1"
    jq -nc --arg missing "$MISSING" --arg prefix "$command_prefix" '
        def entry($script): [{matcher: "*", hooks: [{type: "command", command: ($prefix + $script)}]}];
        {hooks: {
            SessionEnd:   entry($missing + "/session-end.ts"),
            SubagentStop: entry($missing + "/subagent-stop.ts"),
            Notification: entry($missing + "/notification.ts"),
            PreCompact:   entry($missing + "/pre-compact.ts")
        }}
    '
}

echo "→ validate-hook-registration.sh derived event coverage (vacuous-gate fix, 2026-09-02)"

# ---------------------------------------------------------------------------
# Case 1 — THE REPRODUCTION. Four events the hardcoded lists never named, four
# nonexistent command paths. Pre-fix: EXIT=0, "✓ All hook command paths exist".
# ---------------------------------------------------------------------------
run_case "bogus-paths-under-the-four-previously-unchecked-events" \
    "$(four_omitted_events_settings 'bun ')" 1 \
    "SessionEnd references missing file" \
    "SubagentStop references missing file" \
    "Notification references missing file" \
    "PreCompact references missing file" \
    "Hook registration validation FAILED"

# ---------------------------------------------------------------------------
# Case 2 — check 2 (duplicates) covered the same six events only. A duplicated
# command under SessionEnd must now be reported.
# ---------------------------------------------------------------------------
DUPLICATE_SETTINGS=$(jq -nc --arg existing "$EXISTING" '
    {hooks: {SessionEnd: [{matcher: "*", hooks: [
        {type: "command", command: ("bash " + $existing)},
        {type: "command", command: ("bash " + $existing)}
    ]}]}}
')
run_case "duplicate-command-within-sessionend" "$DUPLICATE_SETTINGS" 1 \
    "SessionEnd has duplicate command"

# ---------------------------------------------------------------------------
# Case 3 — NEGATIVE CONTROL. Same four events, paths that exist, no duplicates:
# the gate must stay green, and the green line must be QUALIFIED with how many
# commands it actually inspected (an unqualified "all paths exist" over zero
# inspected commands is exactly the bug).
# ---------------------------------------------------------------------------
CLEAN_SETTINGS=$(jq -nc --arg existing "$EXISTING" '
    def entry: [{matcher: "*", hooks: [{type: "command", command: ("bash " + $existing)}]}];
    {hooks: {SessionEnd: entry, SubagentStop: entry, Notification: entry, PreCompact: entry}}
')
run_case "clean-fixture-under-the-same-four-events-stays-green" "$CLEAN_SETTINGS" 0 \
    "All 4 resolvable hook command path(s) exist" \
    "SessionEnd" "PreCompact" \
    "Hook registration validation PASSED"

# ---------------------------------------------------------------------------
# Case 4 — the load-bearing `env -u AI_AGENT -u CLAUDECODE ` prefix. The old
# inline awk took token 1 as the interpreter, so an env-prefixed command
# resolved to the literal path "env" and the real missing script was never
# tested. Parsing now goes through tasks/lib/hook-command-parsing.sh.
# ---------------------------------------------------------------------------
run_case "env-prefixed-command-still-resolves-to-the-real-script-path" \
    "$(four_omitted_events_settings 'env -u AI_AGENT -u CLAUDECODE bun ')" 1 \
    "$MISSING/session-end.ts" \
    "SessionEnd references missing file"

# ---------------------------------------------------------------------------
# Case 5 — derivation, not a longer hardcoded list. An event name that does not
# exist in any list anywhere must still be inspected.
# ---------------------------------------------------------------------------
FUTURE_EVENT_SETTINGS=$(jq -nc --arg missing "$MISSING" '
    {hooks: {SomeFutureEventClaudeCodeHasNotShippedYet:
        [{matcher: "*", hooks: [{type: "command", command: ("bun " + $missing + "/future.ts")}]}]}}
')
run_case "unknown-future-event-name-is-covered-by-derivation" "$FUTURE_EVENT_SETTINGS" 1 \
    "SomeFutureEventClaudeCodeHasNotShippedYet references missing file"

# ---------------------------------------------------------------------------
# Case 6 — user-authored shapes must not crash the derivation (issue #103).
# ---------------------------------------------------------------------------
run_case "absent-hooks-key-warns-rather-than-claiming-coverage" '{"model":"opus"}' 0 \
    "declares no hook events"
run_case "null-hooks-key" '{"hooks":null}' 0 "declares no hook events"
run_case "non-object-hooks-key" '{"hooks":[]}' 0 "declares no hook events"
run_case "null-matcher-list-under-a-derived-event" '{"hooks":{"SessionEnd":null}}' 0 \
    "All 0 resolvable hook command path(s) exist"

# ---------------------------------------------------------------------------
# Case 7 — ${CLAUDE_PLUGIN_ROOT} stays unresolvable-by-design and must not be
# reported as missing (it is plugin-relative, resolved by Claude Code).
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # ${CLAUDE_PLUGIN_ROOT} must stay LITERAL — that is the fixture
PLUGIN_ROOT_SETTINGS='{"hooks":{"PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/x.ts"}]}]}}'
run_case "claude-plugin-root-command-is-skipped-not-flagged" "$PLUGIN_ROOT_SETTINGS" 0 \
    "All 0 resolvable hook command path(s) exist"

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — event coverage is derived from the settings document; the four formerly-unchecked events and unknown future events all gate"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
