#!/usr/bin/env bash
# Regression test for hooks/browser-mcp-config-reminder.sh. Run: bash plugins/chrome-profiles/hooks/tests/test-browser-mcp-config-reminder.sh
set -euo pipefail
H="$(cd "$(dirname "$0")/.." && pwd)/browser-mcp-config-reminder.sh"
S="selftest-$$"; fail=0
export HOME; HOME="$(mktemp -d)"   # private state dir: the hook writes under $HOME/.claude/hooks/state
trap 'rm -rf "$HOME"' EXIT
run() { local out; out="$(printf '%s' "$2" | bash "$H" "$1")"; printf '%s' "$out"; }
expect() { # expect <name> <want: speak|quiet> <out>
  local got=quiet; [ -n "$3" ] && got=speak
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (want $2, got $got)"; fail=1; fi
}
pre() { run pretool "{\"session_id\":\"$S-$1\",\"tool_input\":{\"command\":$(jq -Rn --arg c "$2" '$c')}}"; }

expect "prompt: browser request speaks"   speak "$(run prompt "{\"session_id\":\"$S\",\"prompt\":\"use your browser ability on the Chrome profile\"}")"
expect "prompt: once per session"         quiet "$(run prompt "{\"session_id\":\"$S\",\"prompt\":\"browser again\"}")"
expect "prompt: unrelated stays quiet"    quiet "$(run prompt "{\"session_id\":\"$S-b\",\"prompt\":\"fix the typo in README\"}")"
expect "pretool: CDP attach speaks"       speak "$(pre c 'node x.mjs # connectOverCDP')"
expect "pretool: other Bash quiet"        quiet "$(pre d 'ls -la')"
expect "pretool: rg mentioning CDP quiet" quiet "$(pre e "rg -l -e 'connect_over_cdp|connectOverCDP' plugins")"
expect "pretool: git grep quiet"          quiet "$(pre f 'git grep -n remote-debugging-port')"
expect "pretool: npx autoConnect speaks"  speak "$(pre g 'npx -y chrome-devtools-mcp@latest --autoConnect')"
expect "pretool: leading spaces + path"   speak "$(pre h '  /usr/bin/env python3 -c "connect_over_cdp"')"
j="$(pre i 'cat DevToolsActivePort')"
if jq -e '.hookSpecificOutput.hookEventName=="PreToolUse" and (.hookSpecificOutput.additionalContext|test("mcp-drive.ts"))' <<<"$j" >/dev/null; then echo "ok   pretool: valid JSON naming mcp-drive.ts"; else echo "FAIL pretool JSON"; fail=1; fi
if grep -q "small JSON-RPC client" "$H"; then echo "FAIL hook still tells agents to hand-write a client"; fail=1; else echo "ok   no hand-written client advice"; fi
# A parent shell whose -c text merely mentions "claude --mcp-config ~/.claude/mcp-browser.json" must not silence it:
expect "prompt: mention in parent shell ignored" speak "$(bash -c 'printf "%s" "$1" | bash "$2" prompt # claude --mcp-config ~/.claude/mcp-browser.json' _ "{\"session_id\":\"$S-z\",\"prompt\":\"open chrome\"}" "$H")"
exit "$fail"
