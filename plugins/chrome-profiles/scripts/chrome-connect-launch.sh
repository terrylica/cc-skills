#!/usr/bin/env bash
# chrome-connect-launch — the Chrome "executable" that chrome-profile.sh hands to `@playwright/mcp --extension`
# (its --executable-path), so the extension token does not sit on a long-lived command line.
#
# WHY. In extension mode the MCP relay opens the extension's connect page by spawning the browser binary with
# `--profile-directory=<dir> chrome-extension://<id>/connect.html?…&token=<token>` (playwright-core,
# CDPRelayServer._openConnectPageInBrowser). The extension reads the token only from that URL, and a launch with
# --profile-directory is the only way to open a page in one chosen profile, so the token has to cross one argv.
# Every user's `ps` can read argv. Two cases:
#   - Chrome already running: the spawned process forwards the URL to the running browser and exits (sub-second).
#   - Chrome NOT running: the spawned process BECOMES the browser, and the token stays on its command line until
#     Chrome quits (seen 2026-10-16: a relay reopened Chrome after a restart and the token stayed visible).
# This launcher is meant to avoid the second case in the normal path (not yet measured) and shortens the first:
#   stage 1: put the arguments on an anonymous pipe (fd 3) and re-exec itself with none, so that after the re-exec
#            its own argv no longer holds them;
#   stage 2: if Chrome is not running, start it WITHOUT any URL (as the Dock does) and wait until it accepts
#            hand-offs; then exec the real binary with the arguments, which forwards them and exits.
# What remains: the forwarding process's argv (about 0.2 s, measured with Chrome running), the stage 1 process and
# its printf subshell (duration not measured), and a race: if Chrome quits between the check and the hand-off, or
# has not started listening after the 1 s wait, the final process can still become the browser with the token on
# its command line. Removing these needs the relay to stop passing the token in the URL it launches (an upstream
# change).
#
# Bash 3.2 compatible (macOS /bin/bash). Env: CHROME_BIN (real binary), CHROME_USER_DATA_DIR,
# CHROME_CONNECT_WAIT (seconds to wait for a cold start, default 30).
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

if [ "${1:-}" != "--stage2" ]; then
  # Stage 1. The forked printf subshell carries the same argv as this process, and both end as soon as the
  # (small) arguments are in the pipe buffer.
  exec 3< <(printf '%s\0' "$@")
  exec "$SELF" --stage2
fi

args=()
while IFS= read -r -d '' a; do args+=("$a"); done <&3
exec 3<&-
[ "${#args[@]}" -gt 0 ] || { echo "chrome-connect-launch: no arguments" >&2; exit 2; }

CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
APP="${CHROME_BIN%%.app/*}.app"
ROOT="${CHROME_USER_DATA_DIR:-$HOME/Library/Application Support/Google/Chrome}"
WAIT="${CHROME_CONNECT_WAIT:-30}"

chrome_up() {
  # The browser process is named after its binary; helpers are "Google Chrome Helper …", so -x excludes them.
  pgrep -x "$(basename "$CHROME_BIN")" >/dev/null 2>&1 && [ -e "$ROOT/SingletonSocket" ]
}

if ! chrome_up; then
  open -a "$APP"
  i=0
  until chrome_up; do
    i=$((i + 1))
    [ "$i" -le $((WAIT * 4)) ] || { echo "chrome-connect-launch: Chrome did not start within ${WAIT}s" >&2; exit 1; }
    sleep 0.25
  done
  sleep 1   # the singleton socket exists slightly before the browser listens on it
fi

exec "$CHROME_BIN" "${args[@]}"
