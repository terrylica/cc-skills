#!/usr/bin/env bash
# alert_state_gate.sh — decide whether a monitor should actually notify a human.
#
# THE PROBLEM THIS SOLVES
#   A scheduled monitor that alerts on every failing tick does not report a
#   problem; it reports a clock. Measured on one machine 2026-09-01: a client
#   pipeline monitor on a 1777-second interval sent 186 Pushover alerts over
#   twelve days. Five of those days accounted for 169 of them, at 41, 47, 48,
#   16 and 17 per day. 86400/1777 = 48.6, so "48 alerts" was not 48 problems —
#   it was ONE unbroken failure re-announced on every tick for twenty-four
#   hours. The signal was intact; the human had stopped reading.
#
#   The cure is to notify on TRANSITIONS rather than on states: say something
#   when the world changes, and otherwise stay quiet.
#
# WHAT THIS IS NOT
#   This is not a debounce. A debounce collapses duplicate alerts that arrive
#   within seconds of each other — the thundering-herd case, where several
#   concurrent instances of the same job all trip the same wire at once. That
#   is a different problem with a different fix (a short fixed time window,
#   keyed by title), and it is deliberately NOT folded in here. If you are
#   tempted to merge the two: a debounce with a 30-second window would not have
#   suppressed a single one of those 186 alerts, because they were 1777 seconds
#   apart. Conversely this gate would not stop four alerts landing in the same
#   second, because they carry the same fingerprint and the first one through
#   legitimately reports a change. They are complements, not duplicates.
#
# THE MODEL
#   The caller reduces its check results to a FINGERPRINT string:
#     - "OK"                         when everything passed
#     - "FAILED:door,drift,deid"     a stable, sorted-by-construction list of
#                                    which invariants are currently failing
#   The fingerprint must be a pure function of the CURRENT state — never
#   include a timestamp, a duration, a count or an error message, or every tick
#   produces a "new" state and the flood returns wearing a disguise.
#
#   This gate compares that fingerprint against the last one it recorded and
#   classifies the transition:
#     first-failure  no prior state, now failing        -> NOTIFY
#     failed         was OK (or a different set), now failing
#                                                       -> NOTIFY
#     changed        was failing, still failing, but the SET of failing
#                    invariants moved                   -> NOTIFY
#     recovered      was failing, now OK                -> NOTIFY
#     unchanged      identical fingerprint to last time -> STAY QUIET
#     still-ok       was OK, still OK                   -> STAY QUIET
#
#   "changed" earns a notification on purpose: a second invariant failing on
#   top of the first is new information a human wants, even mid-outage.
#
# USAGE
#   gate=$(alert_state_gate.sh <state-file> <fingerprint>)
#   transition=$(printf '%s' "$gate" | sed -n 's/.*"transition":"\([^"]*\)".*/\1/p')
#   should=$(printf '%s'     "$gate" | sed -n 's/.*"should_notify":\([a-z]*\).*/\1/p')
#
#   Emits one line of JSON on stdout and ALWAYS exits 0 on a successful
#   classification, so the caller reads a field rather than a status. Exit
#   codes are reserved for the gate itself malfunctioning. This is deliberate:
#   encoding "suppress" as a nonzero exit invites `set -e` to kill the monitor
#   at exactly the moment it decided everything was fine.
#
#   --peek   classify without recording, so a caller can look before it leaps
#   --reset  forget the recorded state (next call reports a first transition)

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: alert_state_gate.sh [--peek] <state-file> <fingerprint>
       alert_state_gate.sh --reset <state-file>

  <fingerprint>  "OK", or "FAILED:<comma-separated invariant keys>".
                 Must depend ONLY on current state — no timestamps, counts,
                 durations or messages, or every tick looks like a change.

emits: {"previous":"...","current":"...","transition":"...","should_notify":true|false}
exit : 0 on successful classification (read should_notify, do not read $?)
       2 on usage error, 3 if the state file cannot be written
EOF
}

PEEK=false
RESET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --peek)  PEEK=true;  shift ;;
        --reset) RESET=true; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "alert_state_gate: unknown flag $1" >&2; usage; exit 2 ;;
        *) break ;;
    esac
done

STATE_FILE="${1:-}"
[[ -n "$STATE_FILE" ]] || { usage; exit 2; }

if [[ "$RESET" == true ]]; then
    rm -f -- "$STATE_FILE"
    printf '{"previous":null,"current":null,"transition":"reset","should_notify":false}\n'
    exit 0
fi

CURRENT="${2:-}"
[[ -n "$CURRENT" ]] || { usage; exit 2; }

# A newline in the fingerprint would corrupt the single-line state file and make
# every subsequent comparison meaningless. Refuse rather than silently mangle.
case "$CURRENT" in
    *$'\n'*) echo "alert_state_gate: fingerprint must be a single line" >&2; exit 2 ;;
esac

state_dir=$(dirname -- "$STATE_FILE")
mkdir -p -- "$state_dir" 2>/dev/null || true

# A missing or unreadable state file is treated as "no prior state", which is
# the safe direction: it produces a notification rather than swallowing one.
PREVIOUS=""
if [[ -r "$STATE_FILE" ]]; then
    PREVIOUS=$(head -n 1 -- "$STATE_FILE" 2>/dev/null || printf '')
fi

is_ok() { [[ "$1" == "OK" ]]; }

if [[ -z "$PREVIOUS" ]]; then
    if is_ok "$CURRENT"; then
        transition="first-ok";      should=false
    else
        transition="first-failure"; should=true
    fi
elif [[ "$PREVIOUS" == "$CURRENT" ]]; then
    if is_ok "$CURRENT"; then
        transition="still-ok";  should=false
    else
        transition="unchanged"; should=false
    fi
elif is_ok "$CURRENT"; then
    transition="recovered"; should=true
elif is_ok "$PREVIOUS"; then
    transition="failed";    should=true
else
    transition="changed";   should=true
fi

if [[ "$PEEK" != true ]]; then
    # Atomic replace: a monitor killed mid-write must never leave a truncated
    # fingerprint behind, because a corrupt state reads as "changed" forever.
    tmp=$(mktemp "${STATE_FILE}.XXXXXX") || { echo "alert_state_gate: cannot create temp file beside $STATE_FILE" >&2; exit 3; }
    printf '%s\n' "$CURRENT" >"$tmp" || { rm -f -- "$tmp"; echo "alert_state_gate: cannot write $tmp" >&2; exit 3; }
    mv -f -- "$tmp" "$STATE_FILE" || { rm -f -- "$tmp"; echo "alert_state_gate: cannot replace $STATE_FILE" >&2; exit 3; }
fi

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

if [[ -z "$PREVIOUS" ]]; then prev_json=null; else prev_json="\"$(json_escape "$PREVIOUS")\""; fi
printf '{"previous":%s,"current":"%s","transition":"%s","should_notify":%s}\n' \
    "$prev_json" "$(json_escape "$CURRENT")" "$transition" "$should"
