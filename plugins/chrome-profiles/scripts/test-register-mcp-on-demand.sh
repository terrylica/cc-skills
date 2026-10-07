#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # assertions are single-quoted strings eval'd later; they read $out and $T
# Tests chrome-profile.sh register_mcp: on-demand file when present, user scope otherwise.
# Runs in a throwaway HOME with no `claude` on PATH, so nothing real is touched and the CLI fallback is exercised.
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)/chrome-profile.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
assert() { if eval "$1"; then :; else echo "FAIL: $2"; fail=1; fi; }
run() {  # run register_mcp <name> <json> in the sandbox
  HOME="$T" PATH="/usr/bin:/bin" bash -c '
    say() { printf "→ %s\n" "$*"; }
    eval "$(sed -n "/^MCP_ON_DEMAND_FILE=/,/^wait_for()/p" "$1" | sed "\$d")"
    register_mcp "$2" "$3"' _ "$S" "$1" "$2"
}
spec='{"type":"stdio","command":"npx","args":["-y","x"],"env":{}}'
mkdir -p "$T/.claude"

# 1. No on-demand file: user scope (~/.claude.json), as before.
echo '{"mcpServers":{}}' > "$T/.claude.json"
run alpha "$spec" >/dev/null
assert 'python3 -c "import json;assert \"alpha\" in json.load(open(\"$T/.claude.json\"))[\"mcpServers\"]"' "no file: alpha should be user scope"
assert '[ ! -f "$T/.claude/mcp-browser.json" ]' "no file: must not create the on-demand file"

# 2. On-demand file exists: written there; a same-named user-scope entry is reported (no claude CLI to remove it).
echo '{"mcpServers":{}}' > "$T/.claude/mcp-browser.json"
out=$(run alpha "$spec")
assert 'python3 -c "import json;assert \"alpha\" in json.load(open(\"$T/.claude/mcp-browser.json\"))[\"mcpServers\"]"' "file: alpha should be on demand"
assert 'printf "%s" "$out" | grep -q "ALSO registered for every session"' "file: duplicate user-scope entry must be reported"
assert 'printf "%s" "$out" | grep -q -- "--mcp-config"' "file: must say how to load it"

# 3. A new name with the file present stays out of ~/.claude.json.
run beta "$spec" >/dev/null
assert 'python3 -c "import json;assert \"beta\" not in json.load(open(\"$T/.claude.json\"))[\"mcpServers\"]"' "file: beta must not reach user scope"
assert '[ "$(stat -f %Lp "$T/.claude/mcp-browser.json")" = 600 ]' "file: mode must be 0600"

[ "$fail" = 0 ] && echo "register_mcp on-demand tests: all passed"
exit "$fail"
