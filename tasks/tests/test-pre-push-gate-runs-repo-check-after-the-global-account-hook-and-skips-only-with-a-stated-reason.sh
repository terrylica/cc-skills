#!/usr/bin/env bash
# Regression: the pre-push gate (#142) runs `moon run repo:check` after the global account hook,
# blocks the push when the check fails, and skips only for deletions, tags, or a stated reason.
#
# Hermetic: a throwaway git repo receives copies of scripts/install-hooks.sh and
# tasks/hooks/pre-push-gate; `moon` is a PATH stub whose exit code each case chooses; HOME points
# at the fixture so the machine's gate-slot limiter is not picked up; init.templateDir points at
# a fake global hook that never reads stdin (the SIGPIPE shape a pipe-based dispatcher would hit).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d -t pre-push-gate.XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

REPO="$FIXTURE/repo"
mkdir -p "$REPO/scripts" "$REPO/tasks/hooks" "$FIXTURE/bin" "$FIXTURE/template/hooks" "$FIXTURE/home"
cp "$REPO_ROOT/scripts/install-hooks.sh" "$REPO/scripts/"
cp "$REPO_ROOT/tasks/hooks/pre-push-gate" "$REPO/tasks/hooks/"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" config init.templateDir "$FIXTURE/template"

# Fake global hook: records that it ran and its args, never reads stdin.
cat > "$FIXTURE/template/hooks/pre-push" <<EOF
#!/usr/bin/env bash
echo "\$1 \$2" > "$FIXTURE/global-ran"
exit \${FAKE_GLOBAL_EXIT:-0}
EOF
chmod +x "$FIXTURE/template/hooks/pre-push"

# moon stub: records its argv, exits with FAKE_MOON_EXIT.
cat > "$FIXTURE/bin/moon" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$FIXTURE/moon-ran"
env | grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|PREFIX)=' > "$FIXTURE/moon-git-env" || true
exit \${FAKE_MOON_EXIT:-0}
EOF
chmod +x "$FIXTURE/bin/moon"

HOME="$FIXTURE/home" bash "$REPO/scripts/install-hooks.sh" >/dev/null
HOOK="$REPO/.git/hooks/pre-push"
if grep -qF "cc-skills pre-push dispatcher" "$HOOK"; then
    pass "installer writes the dispatcher"
else
    fail "installer writes the dispatcher" "sentinel missing from $HOOK"
fi

SHA="$(git -C "$REPO" rev-parse HEAD)"
ZERO=0000000000000000000000000000000000000000
BRANCH_PUSH="refs/heads/main $SHA refs/heads/main $ZERO"

# run_push <stdin> [env assignments...] → sets rc; clears markers first
run_push() {
    local refs="$1"; shift
    rm -f "$FIXTURE/global-ran" "$FIXTURE/moon-ran"
    rc=0
    (cd "$REPO" && env -u PREPUSH_GATE_OK HOME="$FIXTURE/home" PATH="$FIXTURE/bin:$PATH" "$@" \
        "$HOOK" origin https://example.invalid/repo.git <<<"$refs" >"$FIXTURE/out" 2>&1) || rc=$?
}

run_push "$BRANCH_PUSH" FAKE_MOON_EXIT=0
if [[ $rc -eq 0 && -f "$FIXTURE/global-ran" && "$(cat "$FIXTURE/moon-ran" 2>/dev/null)" == "run repo:check" ]]; then
    pass "branch push: global hook runs, then moon run repo:check, exit 0"
else
    fail "branch push passes" "rc=$rc; $(tail -3 "$FIXTURE/out")"
fi
if [[ "$(cat "$FIXTURE/global-ran" 2>/dev/null)" == "origin https://example.invalid/repo.git" ]]; then
    pass "global hook receives the remote name and URL"
else
    fail "global hook args" "$(cat "$FIXTURE/global-ran" 2>/dev/null)"
fi

run_push "$BRANCH_PUSH" FAKE_MOON_EXIT=1
if [[ $rc -ne 0 ]]; then
    pass "failing repo:check blocks the push (exit $rc)"
else
    fail "failing repo:check blocks the push" "exit 0"
fi

run_push "$BRANCH_PUSH" FAKE_GLOBAL_EXIT=1
if [[ $rc -ne 0 && ! -f "$FIXTURE/moon-ran" ]]; then
    pass "a failing account check blocks before the gate runs"
else
    fail "account check failure blocks first" "rc=$rc"
fi

run_push "refs/heads/old $ZERO refs/heads/old $SHA" FAKE_MOON_EXIT=1
if [[ $rc -eq 0 && ! -f "$FIXTURE/moon-ran" ]]; then
    pass "deletion-only push skips the gate"
else
    fail "deletion skips" "rc=$rc"
fi

run_push "refs/tags/v1.0.0 $SHA refs/tags/v1.0.0 $ZERO" FAKE_MOON_EXIT=1
if [[ $rc -eq 0 && ! -f "$FIXTURE/moon-ran" ]]; then
    pass "tag-only push skips the gate"
else
    fail "tag skips" "rc=$rc"
fi

run_push "$BRANCH_PUSH" FAKE_MOON_EXIT=1 PREPUSH_GATE_OK="hotfix, gate verified by hand"
if [[ $rc -eq 0 && ! -f "$FIXTURE/moon-ran" ]] && grep -q 'skipped: PREPUSH_GATE_OK' "$FIXTURE/out"; then
    pass "PREPUSH_GATE_OK with a reason skips, and says so"
else
    fail "reasoned bypass" "rc=$rc"
fi

run_push "$BRANCH_PUSH" FAKE_MOON_EXIT=0 PREPUSH_GATE_OK="x"
if [[ $rc -ne 0 && ! -f "$FIXTURE/moon-ran" ]]; then
    pass "PREPUSH_GATE_OK without a real reason is refused"
else
    fail "short reason refused" "rc=$rc"
fi

# git exports GIT_DIR & co. into hooks; repo:check must not inherit them, or every test that runs
# git in a throwaway repo operates on THIS repository instead (observed 2026-09-30).
run_push "$BRANCH_PUSH" FAKE_MOON_EXIT=0 GIT_DIR="$REPO/.git" GIT_INDEX_FILE="$REPO/.git/index"
if [[ $rc -eq 0 && -f "$FIXTURE/moon-ran" && ! -s "$FIXTURE/moon-git-env" ]]; then
    pass "repo:check runs with git's hook env cleared (no GIT_DIR / GIT_INDEX_FILE)"
else
    fail "hook env cleared before repo:check" "rc=$rc leaked: $(cat "$FIXTURE/moon-git-env" 2>/dev/null)"
fi

if grep -q 'export PREPUSH_GATE_OK="release push:' "$REPO_ROOT/tasks/release/version"; then
    pass "tasks/release/version declares its push to the gate"
else
    fail "release declares bypass" "export missing"
fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — pre-push gate runs after the account check, blocks on failure, skips only with a reason"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
