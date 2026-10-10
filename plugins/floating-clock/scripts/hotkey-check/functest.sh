#!/usr/bin/env bash
# functest.sh — live end-to-end test of FloatingClock's whole-clock hide toggle.
#
# Observes REAL on-screen windows (CGWindowList via `wins`), never app-internal
# state. Drives the default chord ⌃⌥⇧⌘H through System Events (the terminal
# running this needs Accessibility), the --hide/--show/--toggle CLI, a debounce
# double-press, 20 stress cycles, several frontmost apps, and a relaunch.
# INVASIVE by design: it hides/shows the clock ~60 times, activates the apps in
# FRONT_APPS, and kills + relaunches FloatingClock. The previously frontmost
# app is re-activated at the end.
#
#   make hotkey-tools && scripts/hotkey-check/functest.sh
#   FRONT_APPS="Finder,Safari" scripts/hotkey-check/functest.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
W=${WINS:-$HERE/../../build/hotkey-check/wins}
BIN=${FC_BIN:-/Applications/FloatingClock.app/Contents/MacOS/floating-clock}
IFS=',' read -r -a APPS <<< "${FRONT_APPS:-Finder}"
[ -x "$W" ] || { echo "missing $W — run: make hotkey-tools"; exit 2; }
ORIG_FRONT=$(osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true')
pass=0; fail=0
count() { "$W" floating | wc -l | tr -d ' '; }
frames() { "$W" floating | cut -f4 | sort; }
press() { osascript -e 'tell application "System Events" to key code 4 using {control down, option down, shift down, command down}'; }
check() { # name expected-count
  local got; got=$(count)
  if [ "$got" = "$2" ]; then pass=$((pass+1)); echo "PASS $1 (windows=$got)"; else fail=$((fail+1)); echo "FAIL $1 (windows=$got want $2)"; fi
}
wait_count() { # want, timeout-s: poll so we also measure latency
  local want=$1 t0; t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  for _ in $(seq 1 40); do [ "$(count)" = "$want" ] && break; sleep 0.05; done
  perl -MTime::HiRes=time -e "printf \"%.0f ms\", (time-$t0)*1000"
}

SHOWN=$(count); [ "$SHOWN" -ge 1 ] || { echo "clock not visible at start"; exit 2; }
BEFORE=$(frames)
echo "start: $SHOWN clock windows"

press; echo "  hide latency $(wait_count 0)"; check "hotkey hides clock + all rails" 0
sleep 3; check "stays hidden across 3 ticks" 0
press; echo "  show latency $(wait_count "$SHOWN")"; check "hotkey shows it again" "$SHOWN"
sleep 1.2
if [ "$(frames)" = "$BEFORE" ]; then pass=$((pass+1)); echo "PASS frames identical after round trip"; else fail=$((fail+1)); echo "FAIL frames moved:"; diff <(echo "$BEFORE") <(frames) || true; fi

"$BIN" --hide; sleep 0.4; check "CLI --hide" 0
"$BIN" --hide; sleep 0.4; check "CLI --hide is idempotent" 0
"$BIN" --show; sleep 0.4; check "CLI --show" "$SHOWN"
"$BIN" --show; sleep 0.4; check "CLI --show is idempotent" "$SHOWN"
"$BIN" --toggle; sleep 0.4; check "CLI --toggle (hide)" 0
"$BIN" --toggle; sleep 0.4; check "CLI --toggle (show)" "$SHOWN"
[ "$(pgrep -x floating-clock | wc -l | tr -d ' ')" = 1 ] && { pass=$((pass+1)); echo "PASS CLI never starts a second clock"; } || { fail=$((fail+1)); echo "FAIL extra clock process"; }

# Debounce: two presses ~50 ms apart must flip ONCE.
osascript -e 'tell application "System Events"
  key code 4 using {control down, option down, shift down, command down}
  delay 0.05
  key code 4 using {control down, option down, shift down, command down}
end tell'
sleep 0.5; check "double-press within 250 ms flips once" 0
press; sleep 0.5; check "recover after debounce test" "$SHOWN"

# Stress: 20 full cycles.
bad=0
for i in $(seq 1 20); do
  press; sleep 0.35; [ "$(count)" = 0 ] || bad=$((bad+1))
  press; sleep 0.35; [ "$(count)" = "$SHOWN" ] || bad=$((bad+1))
done
[ "$bad" = 0 ] && { pass=$((pass+1)); echo "PASS 20 hide/show cycles, 40/40 transitions"; } || { fail=$((fail+1)); echo "FAIL stress: $bad bad transitions"; }

# Works whatever app is frontmost.
for app in "${APPS[@]}"; do
  osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1; sleep 1
  press; sleep 0.5; h=$(count); press; sleep 0.5; s=$(count)
  if [ "$h" = 0 ] && [ "$s" = "$SHOWN" ]; then pass=$((pass+1)); echo "PASS toggle with $app frontmost"; else fail=$((fail+1)); echo "FAIL with $app frontmost (hidden=$h shown=$s)"; fi
done

# A relaunch must always bring the clock back.
press; sleep 0.5; check "hidden before relaunch" 0
kill "$(pgrep -x floating-clock)"; for _ in $(seq 1 20); do pgrep -x floating-clock >/dev/null || break; sleep 0.25; done
open -a /Applications/FloatingClock.app; sleep 3
check "relaunch shows the clock (state not persisted)" "$SHOWN"
press; sleep 0.5; check "hotkey live again after relaunch" 0
press; sleep 0.5; check "and back" "$SHOWN"

# Hand focus back to whatever was frontmost when the suite started.
osascript -e "tell application id \"$ORIG_FRONT\" to activate" >/dev/null 2>&1 || true
echo "RESULT pass=$pass fail=$fail (restored front: $ORIG_FRONT)"
[ "$fail" = 0 ]
