#!/usr/bin/env bash
# chrome-debug-port-control.sh — open/close/status the CDP debug port for agent browser work.
#
# WHY THIS EXISTS: Chrome >=136 refuses --remote-debugging-port on the DEFAULT user-data-dir
# (hardening against infostealers). The failure is not a flag error — it is a hang on a blank
# page, or a connect that reports healthy and does nothing. This script pins a non-default
# profile so that failure mode cannot occur, and gives `down` an explicit counterpart to `up`
# so the port does not silently stay open.
#
# SECURITY: an open port lets ANY local process drive that browser and read every cookie in
# the profile. Closed by default; open per task; close when done. Loopback only — never bind
# --remote-debugging-address outward.
#
# Doctrine: ../skills/browser-automation/ (SKILL.md, references/doctrine.md). For your EVERYDAY Chrome use
# chrome-profile.sh instead; this script is for a separate, throwaway or sign-in-once profile on a port.
# CHROME-DEBUG-PORT-OK: pins a non-default --user-data-dir, which is exactly what the guard requires.

set -euo pipefail

readonly PORT="${CHROME_DEBUG_PORT:-9222}"
readonly PROFILE="${CHROME_DEBUG_PROFILE:-$HOME/.local/share/chrome-debug-profile}"
# CHROME_DEBUG_BINARY lets a caller run a Chromium from a DIFFERENT app bundle, e.g.
# Playwright's "Google Chrome for Testing.app". A second instance of your own Google
# Chrome.app (same bundle id, other --user-data-dir) collides with it in LaunchServices:
# links opened from other apps land in the wrong instance. A separate bundle cannot collide.
readonly CHROME="${CHROME_DEBUG_BINARY:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
readonly LOG="${TMPDIR:-/tmp}/chrome-debug-${PORT}.log"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

port_live() {
  # 🔴 /json/version is NOT sufficient. Chrome 144+ can serve remote debugging
  # from the DEFAULT profile via the chrome://inspect/#remote-debugging toggle,
  # and that endpoint serves NO HTTP discovery at all - measured on Chrome 153:
  # /json, /json/list and /json/version all return nothing while the
  # port is open and CDP works fine over the WebSocket. Probing only /json/version
  # therefore reports CLOSED against a perfectly live browser, which is the
  # confidently-wrong answer this script's header was rewritten to eliminate.
  # So: HTTP discovery first (classic endpoint), then a plain TCP check.
  curl -s --max-time 3 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1 && return 0
  nc -z -G 3 127.0.0.1 "${PORT}" >/dev/null 2>&1
}

cmd_up() {
  if port_live; then
    printf 'already up on %s (profile: %s)\n' "$PORT" "$PROFILE"
    return 0
  fi
  [ -x "$CHROME" ] || die "Chrome not found at $CHROME"

  # A non-default profile dir is MANDATORY on Chrome >=136. Never point this at the default.
  case "$PROFILE" in
    "$HOME/Library/Application Support/Google/Chrome") die "refusing: that is the DEFAULT profile; Chrome >=136 will refuse the port" ;;
  esac
  mkdir -p "$PROFILE"

  nohup "$CHROME" \
    --remote-debugging-port="$PORT" \
    --user-data-dir="$PROFILE" \
    --no-first-run --no-default-browser-check \
    about:blank >"$LOG" 2>&1 &

  local waited=0
  until port_live; do
    waited=$((waited + 1))
    [ "$waited" -gt 30 ] && die "port $PORT did not come up in 15s; see $LOG"
    sleep 0.5
  done
  printf 'up on %s (profile: %s)\n' "$PORT" "$PROFILE"
  curl -s "http://127.0.0.1:${PORT}/json/version"
  printf '\n'
}

cmd_down() {
  # Match on the exact port flag so this can never reap your everyday Chrome.
  local pids
  pids="$(pgrep -f -- "--remote-debugging-port=${PORT}" || true)"
  if [ -z "$pids" ]; then
    printf 'nothing listening on %s\n' "$PORT"
    return 0
  fi
  printf 'terminating pids: %s\n' "$(printf '%s' "$pids" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 2
  if port_live; then
    printf 'still up after SIGTERM; escalating\n'
    pids="$(pgrep -f -- "--remote-debugging-port=${PORT}" || true)"
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
  fi
  printf 'closed %s\n' "$PORT"
}

# Report the profile ACTUALLY attached to the port, read from the live process
# argv — not the profile this script happens to be configured with.
#
# Printing this script's own configured profile would be a claim, not a measurement:
# another Chrome can hold the port with a DIFFERENT --user-data-dir. The safety argument
# ("the attached profile is a dedicated automation profile") needs the real answer.
attached_profile() {
  # pgrep (not `ps | grep`) for the pid, then ps for that pid's argv. No pipeline
  # feeds an early-exiting reader, so `pipefail` cannot turn a SIGPIPE into a
  # false failure; sed prints the first match on a single-line input on its own.
  local pids first args
  pids="$(pgrep -f -- "--remote-debugging-port=${PORT}" 2>/dev/null || true)"
  [ -n "$pids" ] || return 0
  first="${pids%%$'\n'*}"
  args="$(ps -p "$first" -o args= 2>/dev/null || true)"
  [ -n "$args" ] || return 0
  printf '%s' "$args" | sed -n 's/.*--user-data-dir=\([^ ]*\).*/\1/p'
}

cmd_status() {
  if ! port_live; then
    printf 'CLOSED port=%s\n' "$PORT"
    return 0
  fi
  local actual
  actual="$(attached_profile)"
  if [ -z "$actual" ]; then
    printf 'OPEN  port=%s profile=UNKNOWN (port answers but no owning process found — a tunnel, or another user)\n' "$PORT"
  else
    printf 'OPEN  port=%s profile=%s\n' "$PORT" "$actual"
    if [ "$actual" != "$PROFILE" ]; then
      printf '      NOTE: differs from this script configured profile (%s).\n' "$PROFILE"
      printf '      "down" WILL still close it — down matches on the port, not the profile.\n'
    fi
  fi
  curl -s "http://127.0.0.1:${PORT}/json/version"
  printf '\n'
}

case "${1:-status}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  *) die "usage: $(basename "$0") {up|down|status}" ;;
esac
