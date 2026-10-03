#!/usr/bin/env bash
# Regression: plugins/itp-hooks/scripts/proto-floor.sh, the check that replaced the `env -u AI_AGENT -u CLAUDECODE` hook prefix (2026-10-02). Fakes a proto-shimmed bun and a proto CLI at chosen versions and asserts the return code and that the SessionStart hook speaks only when the floor fails.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLOOR_LIB="$REPO_ROOT/plugins/itp-hooks/scripts/proto-floor.sh"
SESSION_HOOK="$REPO_ROOT/plugins/itp-hooks/hooks/sessionstart-proto-floor-check.sh"
WORK="$(mktemp -d /tmp/proto-floor-test.XXXXXX)"
trap 'cd /tmp && rm -rf "$WORK"' EXIT

passed=0
failed=0
check() { if [[ "$2" == "$3" ]]; then passed=$((passed+1)); echo "  ✓ $1"; else failed=$((failed+1)); echo "  ✗ $1 (expected '$3', got '$2')"; fi; }

make_home() { # $1 = name, $2 = proto version line ("" = no proto), $3 = shim|plain
    local home="$WORK/$1"
    mkdir -p "$home/.proto/shims" "$home/.proto/bin" "$home/plain"
    if [[ "$3" == shim ]]; then printf '#!/bin/sh\necho 1.4.2\n' >"$home/.proto/shims/bun"; chmod +x "$home/.proto/shims/bun"; fi
    if [[ "$3" == plain ]]; then printf '#!/bin/sh\necho 1.4.2\n' >"$home/plain/bun"; chmod +x "$home/plain/bun"; fi
    if [[ -n "$2" ]]; then printf '#!/bin/sh\necho "%s"\n' "$2" >"$home/.proto/bin/proto"; chmod +x "$home/.proto/bin/proto"; fi
    echo "$home"
}

run_floor() { # $1 = home
    local rc=0
    HOME="$1" PATH="$1/.proto/shims:$1/plain:/usr/bin:/bin" bash -c "source '$FLOOR_LIB'; proto_floor_check" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

echo "proto floor (>= 0.61.3 when bun is a proto shim)"
check "proto 0.62.3 passes"            "$(run_floor "$(make_home new 'proto 0.62.3' shim)")" 0
check "proto 0.61.3 (exact floor) passes" "$(run_floor "$(make_home exact 'proto 0.61.3' shim)")" 0
check "proto 0.61.2 fails"             "$(run_floor "$(make_home old 'proto 0.61.2' shim)")" 1
check "proto 0.57.4 fails"             "$(run_floor "$(make_home older 'proto 0.57.4' shim)")" 1
check "unreadable version returns 2"   "$(run_floor "$(make_home garbled 'proto ???' shim)")" 2
check "bun not a shim passes"          "$(run_floor "$(make_home plainbun 'proto 0.50.0' plain)")" 0

old_home="$(make_home hookold 'proto 0.57.4' shim)"
new_home="$(make_home hooknew 'proto 0.62.3' shim)"
hook_out_old="$(HOME="$old_home" PATH="$old_home/.proto/shims:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/itp-hooks" bash "$SESSION_HOOK")"
hook_out_new="$(HOME="$new_home" PATH="$new_home/.proto/shims:/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/itp-hooks" bash "$SESSION_HOOK")"
check "SessionStart hook warns on old proto" "$([[ "$hook_out_old" == *"below 0.61.3"* ]] && echo yes || echo no)" yes
check "SessionStart hook is silent on new proto" "$hook_out_new" ""

echo "  Summary — passed: $passed, failed: $failed"
(( failed == 0 ))
