#!/usr/bin/env bash
#MISE description="Regression: validateHookCommandHygiene() in scripts/validate-plugins.mjs errors on a hooks.json command whose script is NOT on disk (a permanently disarmed guard), and matches quoted / \$HOME-rooted / env-prefixed commands the old literal \${CLAUDE_PLUGIN_ROOT} regex silently skipped"
#
# THE BUG THIS PINS (found 2026-09-02 by a vacuous-gate sweep)
# -----------------------------------------------------------
# scripts/validate-plugins.mjs, validateHookCommandHygiene():
#
#     function shebangInterpreter(command, pluginDir) {
#       ...
#       if (!existsSync(scriptPath)) return null;   // ← "absent" == "not shimmed"
#
# The caller read that `null` as "not a shimmed tool" = clean, and NOTHING else
# in the validator looked at hook script existence. So a hooks.json could
# register a hook pointing at a file that does not exist and the validator
# printed "VALIDATION PASSED" — the guard is registered, Claude Code cannot
# execute it, the event still exits 0, and the guard is permanently disarmed.
#
# The match was also far too narrow: it gated on the literal regex
# /^\$\{?CLAUDE_PLUGIN_ROOT\}?\//, so a quoted token ("${CLAUDE_PLUGIN_ROOT}/…")
# or a $HOME-rooted path never even reached the shebang test.
#
# WHAT THIS TEST ASSERTS — PRESENCE, NOT ABSENCE
# ----------------------------------------------
# docs/LESSONS.md (2026-06-10): an absence-only assertion passes just as happily
# when the feature is deleted. Every bad fixture below asserts the SPECIFIC
# diagnostic is PRESENT in the validator's error list. Only the last case (the
# known-good fixture) asserts absence, and it exists purely to prove the bad
# cases are not being flagged by something unconditional.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-plugins.mjs"
WORK_ROOT="$(mktemp -d -t validate-plugins-hook-command-hygiene.XXXXXX)"
trap 'rm -rf "$WORK_ROOT"' EXIT

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

# ---------------------------------------------------------------------------
# Driver: import the validator as a MODULE and call the one function under test
# against a fixture tree. The validator's main IIFE self-skips when imported
# (import.meta.main === false), so this does not run the whole marketplace
# validation or process.exit() out from under us.
# ---------------------------------------------------------------------------
DRIVER="$WORK_ROOT/run-hygiene.mjs"
cat > "$DRIVER" <<'DRIVER_EOF'
const [, , validatorPath, fixtureRoot] = process.argv;
const mod = await import(validatorPath);
if (typeof mod.validateHookCommandHygiene !== "function") {
  process.stderr.write("validateHookCommandHygiene is not exported\n");
  process.exit(2);
}
const { errors, warnings } = await mod.validateHookCommandHygiene(fixtureRoot);
process.stdout.write(JSON.stringify({ errors, warnings }));
DRIVER_EOF

# make_fixture <case-name> <hook-command> — build a one-plugin fixture tree and
# return its root on stdout. Extra files are created by the caller afterwards.
make_fixture() {
    local case_name="$1" hook_command="$2"
    local fixture_root="$WORK_ROOT/$case_name"
    mkdir -p "$fixture_root/plugins/fixture-plugin/hooks"
    jq -n --arg cmd "$hook_command" '
        {hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}]}}
    ' > "$fixture_root/plugins/fixture-plugin/hooks/hooks.json"
    printf '%s' "$fixture_root"
}

# run_hygiene <fixture-root> — echo the validator's JSON result.
run_hygiene() {
    local fixture_root="$1"
    # HOME is pointed at the fixture so $HOME-rooted commands resolve inside it.
    HOME="$fixture_root" bun "$DRIVER" "$VALIDATOR" "$fixture_root"
}

# assert_error_contains <case-name> <fixture-root> <needle …>
assert_error_contains() {
    local case_name="$1" fixture_root="$2"
    shift 2

    local result errors_text
    if ! result=$(run_hygiene "$fixture_root" 2>&1); then
        fail "$case_name" "driver failed: ${result:0:400}"
        return
    fi
    errors_text=$(printf '%s' "$result" | jq -r '.errors[]?' || true)

    local needle
    for needle in "$@"; do
        if [[ "$errors_text" != *"$needle"* ]]; then
            fail "$case_name" "no ERROR containing: $needle — errors were: ${errors_text//$'\n'/ | }"
            return
        fi
    done
    pass "$case_name"
}

echo "→ validate-plugins.mjs hook-command hygiene: missing scripts + widened matching (vacuous-gate fix, 2026-09-02)"

# ---------------------------------------------------------------------------
# Case 1 — THE REPRODUCTION. A perfectly-formed, env-prefixed command naming a
# script that is not on disk. Pre-fix: zero errors, zero warnings, green.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # ${CLAUDE_PLUGIN_ROOT} must stay literal in the fixture
F1=$(make_fixture "missing-script-under-plugin-root" 'env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/this-guard-does-not-exist.ts')
assert_error_contains "registered-but-missing-hook-script-is-an-error" "$F1" \
    "registered hook script DOES NOT EXIST" \
    "this-guard-does-not-exist.ts" \
    "permanently disarmed"

# ---------------------------------------------------------------------------
# Case 2 — the same miss, but the path token is QUOTED. The old code took
# command.split()[0] and regex-tested it, so a quote defeated it outright.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
F2=$(make_fixture "missing-script-quoted-token" 'env -u AI_AGENT -u CLAUDECODE bun "${CLAUDE_PLUGIN_ROOT}/hooks/quoted-missing.ts"')
assert_error_contains "quoted-token-still-resolves-and-errors" "$F2" \
    "registered hook script DOES NOT EXIST" \
    "quoted-missing.ts"

# ---------------------------------------------------------------------------
# Case 3 — a $HOME-rooted marketplace-clone path whose in-repo equivalent is
# also absent. Resolution goes through the repo so the verdict is deterministic
# rather than "whatever this machine has installed".
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
F3=$(make_fixture "missing-script-home-marketplace-path" 'env -u AI_AGENT -u CLAUDECODE bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/fixture-plugin/hooks/absent-in-repo.ts')
assert_error_contains "home-rooted-marketplace-path-errors-with-in-repo-equivalent" "$F3" \
    "registered hook script DOES NOT EXIST" \
    "in-repo equivalent" \
    "absent-in-repo.ts"

# ---------------------------------------------------------------------------
# Case 4 — shimmed SHEBANG behind a QUOTED bare path. Script exists, no env
# prefix, shebang is `#!/usr/bin/env node` → proto banner risk. The old literal
# regex skipped it because of the leading quote character.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
F4=$(make_fixture "shimmed-shebang-quoted-bare-path" '"${CLAUDE_PLUGIN_ROOT}/hooks/quoted-shebang-guard.mjs"')
printf '#!/usr/bin/env node\nprocess.exit(0);\n' > "$F4/plugins/fixture-plugin/hooks/quoted-shebang-guard.mjs"
chmod +x "$F4/plugins/fixture-plugin/hooks/quoted-shebang-guard.mjs"
assert_error_contains "quoted-bare-path-with-node-shebang-is-flagged" "$F4" \
    "proto-shimmed tool (its shebang interpreter)" \
    "env -u AI_AGENT -u CLAUDECODE"

# ---------------------------------------------------------------------------
# Case 5 — shimmed SHEBANG behind a $HOME-rooted bare path. Never matched by the
# old CLAUDE_PLUGIN_ROOT-only regex under any spelling.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
F5=$(make_fixture "shimmed-shebang-home-rooted-bare-path" '$HOME/hooks/home-shebang-guard.mjs')
mkdir -p "$F5/hooks"
printf '#!/usr/bin/env bun\nprocess.exit(0);\n' > "$F5/hooks/home-shebang-guard.mjs"
chmod +x "$F5/hooks/home-shebang-guard.mjs"
assert_error_contains "home-rooted-bare-path-with-bun-shebang-is-flagged" "$F5" \
    "proto-shimmed tool (its shebang interpreter)"

# ---------------------------------------------------------------------------
# Case 6 — the ORIGINAL check must not regress: a bare `bun` with no env prefix,
# script present, is still an error.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016
F6=$(make_fixture "bare-bun-without-env-prefix" 'bun ${CLAUDE_PLUGIN_ROOT}/hooks/present.ts')
printf 'process.exit(0);\n' > "$F6/plugins/fixture-plugin/hooks/present.ts"
assert_error_contains "bare-shimmed-interpreter-still-errors" "$F6" \
    "proto-shimmed tool (\`bun\`)"

# ---------------------------------------------------------------------------
# Case 7 — NEGATIVE CONTROL. Correct env prefix, script present, plus a
# $HOME-rooted marketplace-clone path that DOES map to a real in-repo file:
# zero errors, zero warnings. Without this, cases 1-6 could be passing because
# something flags every command unconditionally.
# ---------------------------------------------------------------------------
F7="$WORK_ROOT/clean-fixture"
mkdir -p "$F7/plugins/fixture-plugin/hooks"
printf 'process.exit(0);\n' > "$F7/plugins/fixture-plugin/hooks/real-guard.ts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$F7/plugins/fixture-plugin/hooks/real-guard.sh"
chmod +x "$F7/plugins/fixture-plugin/hooks/real-guard.sh"
jq -n '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [
    {type: "command", command: "env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/real-guard.ts"},
    {type: "command", command: "${CLAUDE_PLUGIN_ROOT}/hooks/real-guard.sh"},
    {type: "command", command: "bash $HOME/.claude/plugins/marketplaces/cc-skills/plugins/fixture-plugin/hooks/real-guard.sh"}
]}]}}' > "$F7/plugins/fixture-plugin/hooks/hooks.json"

clean_result=$(run_hygiene "$F7" 2>&1) || clean_result="DRIVER FAILED: $clean_result"
clean_errors=$(printf '%s' "$clean_result" | jq -r '.errors | length' 2>/dev/null || echo "n/a")
clean_warnings=$(printf '%s' "$clean_result" | jq -r '.warnings | length' 2>/dev/null || echo "n/a")
if [[ "$clean_errors" == "0" && "$clean_warnings" == "0" ]]; then
    pass "known-good fixture (env prefix, bash shebang, marketplace-clone remap) stays silent"
else
    fail "known-good fixture (env prefix, bash shebang, marketplace-clone remap) stays silent" \
        "expected 0/0, got $clean_errors error(s) / $clean_warnings warning(s): ${clean_result:0:500}"
fi

# ---------------------------------------------------------------------------
# Case 8 — the real marketplace must be clean under the stricter gate. This is
# the check that would have surfaced any genuine violation in-repo.
# ---------------------------------------------------------------------------
live_result=$(bun "$DRIVER" "$VALIDATOR" "$REPO_ROOT" 2>&1) || live_result="DRIVER FAILED: $live_result"
live_errors=$(printf '%s' "$live_result" | jq -r '.errors | length' 2>/dev/null || echo "n/a")
if [[ "$live_errors" == "0" ]]; then
    pass "every real plugins/*/hooks/hooks.json command resolves to a script on disk"
else
    live_detail=$(printf '%s' "$live_result" | jq -r '.errors[]?' 2>/dev/null || printf '%s' "$live_result")
    fail "every real plugins/*/hooks/hooks.json command resolves to a script on disk" \
        "${live_detail//$'\n'/ | }"
fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — missing hook scripts error out, and quoted / \$HOME-rooted / env-prefixed commands are all matched"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
