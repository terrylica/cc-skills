#!/usr/bin/env bash
# test-hook-runtime-selftest.sh — Wave 5 A1 runtime hook self-test harness
#
# Verifies run_hook_runtime_selftest:
#   1. Passes on the real shipped plugin tree (all hooks invoke cleanly)
#   2. Detects a hook that crashes on invocation (synthetic broken hook)
#   3. Detects a missing hook file
#   4. Auto-resolves plugin_root from BASH_SOURCE when no arg given
#   5. Stays silent on success (no noise on stderr/stdout)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
source "$PLUGIN_DIR/scripts/hook-install-lib.sh"

# hook-install-lib.sh sets -euo pipefail; we need errexit OFF to capture
# nonzero exit codes from the function-under-test without aborting.
set +e

PASS=0
FAIL=0

ok()  { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
nok() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Hook Runtime Self-Test (Wave 5 A1)"
echo "========================================"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo ""
echo "[Case 1] Real plugin tree: all hooks pass cleanly"
out=$(run_hook_runtime_selftest "$PLUGIN_DIR" 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
  ok "real plugin: all hooks invoke cleanly"
else
  nok "real plugin: rc=$rc output: $out"
fi
if [ -z "$out" ]; then
  ok "real plugin: silent on success (no stderr noise)"
else
  nok "real plugin: stderr noise on success: $out"
fi

echo ""
echo "[Case 2] Synthetic broken hook: detected as failure"
# Build a fake plugin with a heartbeat-tick.sh that exits non-zero.
mkdir -p "$T/fake-plugin/hooks"
cat > "$T/fake-plugin/hooks/heartbeat-tick.sh" <<'EOF'
#!/bin/bash
echo "boom" >&2
exit 5
EOF
chmod +x "$T/fake-plugin/hooks/heartbeat-tick.sh"
# session-bind needs to exist too (well-formed) so the test reports only
# heartbeat-tick as the failure.
cat > "$T/fake-plugin/hooks/session-bind.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$T/fake-plugin/hooks/session-bind.sh"

out=$(run_hook_runtime_selftest "$T/fake-plugin" 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
  ok "broken hook: returns rc=1"
else
  nok "broken hook: expected rc=1 got rc=$rc"
fi
if echo "$out" | grep -q "heartbeat-tick.sh exited rc=5"; then
  ok "broken hook: surfaces failing hook name + exit code"
else
  nok "broken hook: missing diagnostic; got: $out"
fi

echo ""
echo "[Case 3] Missing hook file: reported as fail"
mkdir -p "$T/missing-plugin/hooks"
# heartbeat-tick.sh deliberately not created.
cat > "$T/missing-plugin/hooks/session-bind.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$T/missing-plugin/hooks/session-bind.sh"
out=$(run_hook_runtime_selftest "$T/missing-plugin" 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
  ok "missing hook: returns rc=1"
else
  nok "missing hook: expected rc=1 got rc=$rc"
fi
if echo "$out" | grep -q "heartbeat-tick.sh missing"; then
  ok "missing hook: surfaces clear missing-file diagnostic"
else
  nok "missing hook: diagnostic unclear; got: $out"
fi

echo ""
echo "[Case 4] Missing hooks dir entirely: reported as fail"
mkdir -p "$T/no-hooks-plugin"
out=$(run_hook_runtime_selftest "$T/no-hooks-plugin" 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
  ok "missing hooks dir: returns rc=1"
else
  nok "missing hooks dir: expected rc=1 got rc=$rc"
fi
if echo "$out" | grep -q "hooks dir not found"; then
  ok "missing hooks dir: clear diagnostic"
else
  nok "missing hooks dir: diagnostic unclear; got: $out"
fi

echo ""
echo "[Case 5] Default plugin_root (auto-derived) passes"
out=$(run_hook_runtime_selftest 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
  ok "default plugin_root resolves and passes"
else
  nok "default plugin_root failed rc=$rc output: $out"
fi

echo ""
echo "========================================"
echo "Result: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
