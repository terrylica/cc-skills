#!/bin/bash
# TTS Read Clipboard Wrapper — the BetterTouchTool entry point for ⌥S ("TTS speak English").
#
# WHY THIS FILE EXISTS AS A WRAPPER
# ---------------------------------
# BTT executes shell actions from an XPC service
# (BetterTouchToolShellScriptRunner.xpc) whose environment is NOT the login
# shell's. Measured 2026-08-18 via `ps eww` on the live runner:
#
#     PATH=/usr/bin:/bin:/usr/sbin:/sbin
#
# Nothing under mise, homebrew, or ~/.local/bin is reachable. This silently
# broke ⌥S: tts_read_clipboard.sh guards on `command -v uv`, uv lives only at
# ~/.local/share/mise/installs/uv/..., the guard tripped, and the script exited
# 1 before speaking. BTT's "Result:" box showed nothing because the failure
# path writes to stderr/notification, not stdout.
#
# So the wrapper's job is: establish a sane environment, pick the cheapest
# working engine, and make every failure loud.
#
# ENGINE ORDER (cheapest first)
# -----------------------------
#   1. Kokoro via claude-tts-companion (http://[::1]:8780)
#      A resident native Swift service in front of a resident MLX-Metal Kokoro
#      server. Models are already in GPU memory, so a keypress costs one curl.
#      This is the project's documented "Kokoro-only policy" path — see the
#      error text at tts_read_clipboard.sh:242.
#   2. Supertonic (local, on-demand)
#      Fallback only. Spawns uv + Python and loads ~260 MB of ONNX per press.
#
# Set TTS_ENGINE=supertonic to force (2); TTS_ENGINE=kokoro to force (1).

set -euo pipefail

# Restore a usable PATH. Order matters: system dirs first (BTT-guaranteed),
# then the operator's tool dirs. Everything tts_kokoro.sh needs — curl, awk,
# pbpaste, jq, shlock, date, sed — resolves from /usr/bin alone.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin"

LOG="/tmp/kokoro-tts.log"
log() { printf '[%s] wrapper: %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; }

# Surface the real reason for any unexpected death, instead of exiting mute.
on_error() {
    rc=$?
    log "FAILED (exit $rc) at line ${BASH_LINENO[0]}"
    exit "$rc"
}
trap on_error ERR

# Resolve this script's real directory so sibling scripts are found whether we
# were invoked through ~/.local/bin/<symlink> or directly in the repo.
SELF="$0"
if RESOLVED=$(readlink -f "$0" 2>/dev/null); then
    SELF="$RESOLVED"
fi
SCRIPT_DIR=$(cd "$(dirname "$SELF")" && pwd)

# --- Speech rate from the BTT persistent variable (default 220 WPM) ----------
# bttcli may be absent, may fail, or may hand back a non-numeric string; any of
# those must fall back rather than poison the arithmetic in the callee.
BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
SPEECH_RATE=""
if [[ -x "$BTTCLI" ]]; then
    SPEECH_RATE=$("$BTTCLI" get_string_variable variable_name=TTS_SPEECH_RATE 2>/dev/null) || SPEECH_RATE=""
fi
if ! [[ "$SPEECH_RATE" =~ ^[0-9]+$ ]] || ((SPEECH_RATE < 90 || SPEECH_RATE > 500)); then
    SPEECH_RATE=220
fi
export SPEECH_RATE

# --- Wait for the clipboard ---------------------------------------------------
# The BTT trigger fires ⌘C and then this script with NO delay between them.
# Measured: bash spawn -> pbpaste is 10-15 ms, but a browser/Electron app takes
# 50-300 ms to actually write the pasteboard. Reading immediately therefore
# yields the PREVIOUS selection — a stale read, which an "is it empty?" check
# cannot detect because stale data is non-empty.
#
# Correct primitive: NSPasteboard.changeCount, a monotonic counter bumped on
# every write. We sample it, then wait for it to move. Because we start well
# inside the app's 50-300 ms window, the sample is the PRE-copy value and the
# increment is a positive confirmation that this copy landed.
#
# If it never moves we proceed anyway: that means either the app wrote before
# we sampled (very fast source) or nothing was selected. In both cases the
# current clipboard is the best available answer, so we degrade rather than
# refuse. The whole wait happens inside ONE osascript process, so the common
# case costs a single spawn and exits the moment the copy lands.
await_clipboard() {
    osascript - <<'OSA' >/dev/null 2>&1 || true
use framework "AppKit"
use scripting additions
set pb to current application's NSPasteboard's generalPasteboard()
set c0 to pb's changeCount() as integer
repeat 60 times
    delay 0.01
    if (pb's changeCount() as integer) > c0 then exit repeat
end repeat
OSA
}

await_clipboard

CLIP=$(pbpaste 2>/dev/null) || CLIP=""

if [[ -z "$CLIP" ]]; then
    log "clipboard empty after 0.6s wait — nothing to speak"
    osascript -e 'display notification "Clipboard is empty" with title "TTS" sound name "Basso"' 2>/dev/null || true
    exit 1
fi

# --- Engine selection --------------------------------------------------------
TTS_ENGINE="${TTS_ENGINE:-auto}"
COMPANION="http://[::1]:8780"

companion_up() {
    curl -s --max-time 2 "${COMPANION}/health" >/dev/null 2>&1
}

if [[ "$TTS_ENGINE" == "kokoro" ]] || { [[ "$TTS_ENGINE" == "auto" ]] && companion_up; }; then
    log "engine=kokoro (resident companion) chars=${#CLIP} rate=${SPEECH_RATE}"
    # NOTE: deliberately NOT `| exec ...`. In a pipeline, `exec` replaces the
    # pipeline's subshell, not this script, so execution would fall through
    # into the Supertonic fallback below after Kokoro had already spoken.
    # Capture the real status and exit on it instead.
    rc=0
    printf '%s' "$CLIP" | "$SCRIPT_DIR/tts_kokoro.sh" - || rc=$?
    if ((rc != 0)); then
        log "ERROR: kokoro path failed (exit $rc)"
    fi
    exit "$rc"
fi

# --- Fallback: Supertonic ----------------------------------------------------
# Needs uv, which is NOT on BTT's PATH. Resolve it through the operator's
# stable mise entrypoint (~/.local/bin/mise) rather than hardcoding an install
# path that moves whenever mise or homebrew reshuffles.
log "companion down or forced — falling back to Supertonic"

UV=""
if [[ -x "${HOME}/.local/bin/mise" ]]; then
    UV=$("${HOME}/.local/bin/mise" which uv 2>/dev/null) || UV=""
fi
if [[ -z "$UV" ]]; then
    UV=$(command -v uv 2>/dev/null) || UV=""
fi

if [[ -z "$UV" || ! -x "$UV" ]]; then
    log "ERROR: no TTS engine available (companion down AND uv unresolvable)"
    osascript -e 'display notification "No TTS engine available. Start claude-tts-companion." with title "TTS Error" sound name "Basso"' 2>/dev/null || true
    exit 1
fi

# Put the resolved uv on PATH so the callee's `command -v uv` guard passes.
# Declaration split from assignment so dirname's exit status is not masked.
UV_DIR=""
UV_DIR=$(dirname "$UV")
export PATH="${UV_DIR}:${PATH}"
log "engine=supertonic uv=$UV chars=${#CLIP} rate=${SPEECH_RATE}"

exec "$SCRIPT_DIR/tts_read_clipboard.sh" "$@"
