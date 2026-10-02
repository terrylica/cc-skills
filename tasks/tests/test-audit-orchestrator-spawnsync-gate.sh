#!/usr/bin/env bash
# Regression (#142): the Bun.spawnSync orchestrator audit is a GATE in repo:check, so it must be able
# to fail. Before #142 it ran nowhere, and two of its branches exited 0 without checking anything.
#
# Hermetic: the audit derives REPO_ROOT from its own location, so it is copied into a throwaway tree
# holding a synthetic orchestrator (one classifier import) and that classifier.
#   clean classifier               → exit 0
#   Bun.spawnSync( in a classifier → exit 1, and the file is named
#   same line with SPAWN-SYNC-OK   → exit 0 (reasoned escape)
#   orchestrator file missing      → exit 2 (cannot run; previously exit 0)
#   no classifier import parsed    → exit 2 (cannot run; previously exit 0)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT="$REPO_ROOT/tasks/hook-lint/orchestrator-spawnsync.sh"
ORCH_NAME="posttooluse-write-edit-orchestrator.ts"
FIXTURE="$(mktemp -d -t spawnsync-gate.XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT

failures=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n     %s\n' "$1" "$2"; failures=$((failures + 1)); }

HOOKS="$FIXTURE/plugins/itp-hooks/hooks"
mkdir -p "$FIXTURE/tasks/hook-lint" "$HOOKS"
cp "$AUDIT" "$FIXTURE/tasks/hook-lint/audit.sh"

write_orchestrator() {
    printf '%s\n' 'import { classifyFixtureForPostToolUseOrchestrator } from "./posttooluse-fixture.ts";' >"$HOOKS/$ORCH_NAME"
}
write_classifier() {
    printf 'export async function classifyFixtureForPostToolUseOrchestrator() {\n%s\n  return {};\n}\n' "$1" >"$HOOKS/posttooluse-fixture.ts"
}
run_audit() {
    rc=0
    out="$(bash "$FIXTURE/tasks/hook-lint/audit.sh" 2>&1)" || rc=$?
}

write_orchestrator
write_classifier '  const proc = Bun.spawn(["true"]);'
run_audit
if [[ $rc -eq 0 ]]; then pass "clean classifier passes (exit 0)"; else fail "clean classifier passes" "rc=$rc"; fi

write_classifier '  const r = Bun.spawnSync(["true"]);'
run_audit
if [[ $rc -eq 1 && $out == *"posttooluse-fixture.ts"* ]]; then
    pass "Bun.spawnSync in a classifier fails (exit 1) and names the file"
else
    fail "violation fails" "rc=$rc"
fi

write_classifier '  const r = Bun.spawnSync(["true"]); // SPAWN-SYNC-OK: fixture proving the reasoned escape'
run_audit
if [[ $rc -eq 0 ]]; then pass "SPAWN-SYNC-OK with a reason is honoured"; else fail "reasoned escape" "rc=$rc"; fi

rm -f "$HOOKS/$ORCH_NAME"
run_audit
if [[ $rc -eq 2 ]]; then pass "missing orchestrator fails as cannot-run (exit 2), not a pass"; else fail "missing orchestrator" "rc=$rc"; fi

printf '%s\n' 'import { somethingElse } from "./posttooluse-fixture.ts";' >"$HOOKS/$ORCH_NAME"
run_audit
if [[ $rc -eq 2 ]]; then pass "zero parsed classifier imports fails as cannot-run (exit 2)"; else fail "zero imports" "rc=$rc"; fi

echo
if [[ $failures -eq 0 ]]; then
    echo "✓ PASSED — the spawnSync gate can fail, cannot pass vacuously, and honours a reasoned escape"
else
    echo "✗ FAILED — $failures case(s)"
    exit 1
fi
