#!/usr/bin/env bash
# Regression: renamed operator env knobs still honour their ITER###_ names, with a deprecation notice (issue #224)
#
# The release and commits tooling renamed 23 env knobs from iteration numbers to descriptive names.
# Old names must keep working: shell profiles set them, and the commit-msg hook is copied into
# other repositories. Checked here at every layer that resolves them: the shared bash helper
# (scripts/lib/env-knob.sh), one real script end to end, the copied hook's inline fallback, and the
# inline Python helper.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }
expect() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi; }

echo "→ renamed env knobs keep their old names working (issue #224)"

# ── 1. The shared bash helper ────────────────────────────────────────────────────────────────
helper() { # helper NEW_VAL OLD_VAL -> "value|stderr"
    # shellcheck disable=SC2016 # the single-quoted program is expanded by the child bash, on purpose
    env -u NEW_KNOB -u OLD_KNOB ${1:+NEW_KNOB="$1"} ${2:+OLD_KNOB="$2"} \
        bash -c 'source "$0"; cc_knob v NEW_KNOB OLD_KNOB dflt 2>/tmp/env-knob-err.$$; printf "%s|%s" "$v" "$(cat /tmp/env-knob-err.$$)"; rm -f /tmp/env-knob-err.$$' \
        "$REPO_ROOT/scripts/lib/env-knob.sh"
}
expect "helper: neither set -> default, no notice" "$(helper "" "")" "dflt|"
expect "helper: new name set -> new value, no notice" "$(helper new "")" "new|"
expect "helper: both set -> new name wins, no notice" "$(helper new old)" "new|"
expect "helper: only old name set -> old value plus a notice naming the replacement" \
    "$(helper "" old)" "old|OLD_KNOB is deprecated; use NEW_KNOB (cc-skills #224)"

# ── 2. A real script, set through its old name ───────────────────────────────────────────────
err=$(cd "$REPO_ROOT" && ITER150_COMMIT_COUNT_TO_DISPLAY=1 bash scripts/iter150-readable-git-log.sh 2>&1 >/dev/null || true)
case "$err" in
    *"ITER150_COMMIT_COUNT_TO_DISPLAY is deprecated; use RELEASE_HISTORY_COUNT"*) pass "iter150 renderer honours its old name and says so" ;;
    *) fail "iter150 renderer honours its old name and says so" "stderr: ${err:0:200}" ;;
esac

# ── 3. The copied commit-msg hook (inline fallback, no helper available) ─────────────────────
msg=$(mktemp)
echo "feat: x" > "$msg"
hook="$REPO_ROOT/scripts/iter157-commit-msg-hook.sh"
rc=0; env -u COMMITS_HOOK_FAIL_MODE -u COMMITS_HOOK_CC_SKILLS_PATH \
    ITER157_COMMIT_MSG_HOOK_CC_SKILLS_REPO_PATH_OVERRIDE=/nonexistent-cc-skills \
    ITER157_COMMIT_MSG_HOOK_FAIL_MODE_ON_ADVISOR_NOT_FOUND=closed \
    bash "$hook" "$msg" >/dev/null 2>&1 || rc=$?
expect "hook: old path + old fail-mode names -> advisor missing, fail closed (exit 1)" "$rc" "1"
rc=0; env -u ITER157_COMMIT_MSG_HOOK_FAIL_MODE_ON_ADVISOR_NOT_FOUND -u ITER157_COMMIT_MSG_HOOK_CC_SKILLS_REPO_PATH_OVERRIDE \
    COMMITS_HOOK_CC_SKILLS_PATH=/nonexistent-cc-skills COMMITS_HOOK_FAIL_MODE=closed \
    bash "$hook" "$msg" >/dev/null 2>&1 || rc=$?
expect "hook: new names -> fail closed (exit 1)" "$rc" "1"
rc=0; env -u COMMITS_HOOK_FAIL_MODE -u ITER157_COMMIT_MSG_HOOK_FAIL_MODE_ON_ADVISOR_NOT_FOUND \
    COMMITS_HOOK_CC_SKILLS_PATH=/nonexistent-cc-skills \
    bash "$hook" "$msg" >/dev/null 2>&1 || rc=$?
expect "hook: no fail mode set -> fail open (exit 0)" "$rc" "0"
rm -f "$msg"

# ── 4. The inline Python helper ──────────────────────────────────────────────────────────────
py=$(cd "$REPO_ROOT" && env -u NEW_KNOB OLD_KNOB=old python3 - 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("iter144_parser", "scripts/iter144-release-step-timing-parser.py")
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod  # dataclasses resolve their module through sys.modules
spec.loader.exec_module(mod)
print(mod.cc_knob("NEW_KNOB", "OLD_KNOB", "dflt"))
PY
)
case "$py" in
    *"OLD_KNOB is deprecated; use NEW_KNOB"*old) pass "python helper: old name -> old value plus a notice" ;;
    *) fail "python helper: old name -> old value plus a notice" "output: ${py:0:200}" ;;
esac

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — old names honoured at every layer, new names win"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
