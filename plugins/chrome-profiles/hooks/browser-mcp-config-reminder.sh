#!/usr/bin/env bash
# Browser MCP reminder — advisory, never blocks (exit 0 always). Shipped by the chrome-profiles plugin
# (hooks/hooks.json), so every host with the plugin gets it; it moved here from a private ~/.claude hook.
#
# The signed-in Chrome profile servers (chrome-<name>, from `chrome-profile.sh setup <email>`) are
# registered ON DEMAND in ~/.claude/mcp-browser.json, so a session sees them only when started as
#     claude --mcp-config ~/.claude/mcp-browser.json
# Without that, an agent asked to "use the browser" falls back to attaching over CDP to the running
# Chrome (connectOverCDP / DevToolsActivePort / chrome-main --autoConnect), and Chrome then shows an
# "Allow remote debugging?" dialog on EVERY new connection — the operator has to click Allow again
# and again (measured 2026-10-12 during an API-key setup in a signed-in profile).
#
# Modes (argv[1]):
#   prompt    UserPromptSubmit — prompt mentions browser/Chrome work AND this session was not
#             started with --mcp-config → stdout becomes context for Claude.
#   pretool   PreToolUse(Bash) — the command takes the Allow-dialog route → additionalContext.
# Each mode speaks at most once per session. Every invocation appends a trace line first.
set -euo pipefail

mode="${1:-prompt}"
state_dir="$HOME/.claude/hooks/state/browser-mcp-config-reminder"
mkdir -p "$state_dir"
input="$(cat)"
session_id="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)"
printf '%s mode=%s session=%s\n' "$(date -u +%FT%TZ)" "$mode" "$session_id" >>"$state_dir/trace.log"

# Was this Claude Code process started with --mcp-config <…mcp-browser.json>? Walk the ancestry.
launched_with_browser_config() {
  local pid=$PPID args
  for _ in 1 2 3 4 5 6; do
    [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || return 1
    # Test seam: the walk stops at this pid, so a test is not affected by how ITS parent Claude was started.
    [ "$pid" != "${BROWSER_MCP_REMINDER_STOP_PID:-}" ] || return 1
    args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
    # Match only the claude process itself: a parent shell's `-c` text can merely MENTION the flag
    # (caught 2026-10-12 — a Bash tool command quoting it made the reminder go silent).
    if [[ "$args" =~ ^([^[:space:]]*/)?claude([[:space:]]|$) && "$args" =~ --mcp-config[=[:space:]][^[:space:]]*mcp-browser\.json ]]; then return 0; fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  done
  return 1
}

once() { # once <key> → 0 the first time this session, 1 afterwards; no session id → always speak
  [ -n "$session_id" ] || return 0
  local f="$state_dir/${session_id}.$1"
  [ -e "$f" ] && return 1
  : >"$f"
  return 0
}

# shellcheck disable=SC2016  # backticks/\$(…) are literal text shown to Claude
msg_fallback='No restart needed as a fallback: drive the on-demand server from Bash with the shipped client, never a hand-written one — `bun "$(cc-plugin-root chrome-profiles)/scripts/mcp-drive.ts" ext <account-email> steps.json`. It rides the profile'"'"'s extension token (no Allow dialog; if `playwright-mcp` says no token is stored, run `chrome-profile.sh setup <email>` instead of clicking the extension'"'"'s connect page), closes its own tab and any tab the run opened. Leftover tabs from anything else: `chrome-profile.sh tabs list` then `tabs close --id <tabId>`. Never print secrets read from a page: pipe them to `vault set --stdin`.'

case "$mode" in
  prompt)
    prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null || true)"
    shopt -s nocasematch
    if [[ "$prompt" =~ browser|chrome|playwright|dashboard|signed[-\ ]in|log\ ?in\ to|web\ ?ui|profile\ of\ [a-z0-9._%+-]+@ ]]; then
      launched_with_browser_config && exit 0
      once prompt || exit 0
      cat <<EOF
[browser-mcp-config-reminder] This session was NOT started with \`claude --mcp-config ~/.claude/mcp-browser.json\`, so the zero-click signed-in Chrome servers (chrome-<name>, one per account email; list them with \`bash "\$(cc-plugin-root chrome-profiles)/scripts/chrome-profile.sh" doctor\`) are not loaded. Do NOT attach over CDP / chrome-main: Chrome then asks the operator to click "Allow remote debugging?" on every connection. Tell the operator in one line that future browser sessions should start with \`claude --mcp-config ~/.claude/mcp-browser.json\`. ${msg_fallback}
EOF
    fi
    ;;
  pretool)
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)"
    # Speak only for a command that may attach. A search or VCS command that merely mentions these words
    # (rg/grep over the plugin source) is not an attach; it used to trigger this (2026-10-27).
    first="${cmd#"${cmd%%[![:space:]]*}"}"; first="${first%%[[:space:]]*}"; first="${first##*/}"
    case "$first" in rg|grep|egrep|ugrep|ag|git|gh|find|fd|sed|awk|less|head|tail|wc|diff|jq) exit 0 ;; esac
    if [[ "$cmd" =~ connectOverCDP|connect_over_cdp|DevToolsActivePort|--autoConnect|remote-debugging-port ]]; then
      once pretool || exit 0
      # shellcheck disable=SC2016  # literal text shown to Claude
      jq -n --arg c "[browser-mcp-config-reminder] This command attaches to Chrome over CDP; against the operator's everyday Chrome that pops an \"Allow remote debugging?\" dialog on EVERY connection. Prefer the profile's on-demand extension server (start Claude Code with \`claude --mcp-config ~/.claude/mcp-browser.json\`). ${msg_fallback}" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
    fi
    ;;
esac
exit 0
