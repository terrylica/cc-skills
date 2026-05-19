#!/bin/bash

# <bitbar.title>Claude HQ</bitbar.title>
# <bitbar.version>v5.4.0</bitbar.version>
# <bitbar.author>terrylica</bitbar.author>
# <bitbar.author.github>terrylica</bitbar.author.github>
# <bitbar.desc>Control center for claude-tts-companion: TTS, subtitles, karaoke, bionic reading</bitbar.desc>
# <bitbar.dependencies>jq,curl</bitbar.dependencies>
# <bitbar.abouturl>https://github.com/terrylica/cc-skills</bitbar.abouturl>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>

# claude-hq.10s.sh — SwiftBar plugin for claude-tts-companion (v5.4.0)
# Zero-dependency bash version. Requires: /usr/bin/curl, /usr/bin/jq
# NOTE: no set -e here — SwiftBar plugins must always produce output, even on errors
#
# SSoT: cc-skills/plugins/claude-tts-companion/swiftbar/claude-hq.10s.sh
# Deployed via symlink at ~/Library/Application Support/SwiftBar/Plugins/claude-hq.10s.sh
#
# Performance (v5.4.0, 2026-05-18 quick-wins refactor):
#  - 4 HTTP fetches run in parallel (was serial 4×blocking)
#  - One jq call per JSON blob via @tsv (was 28 separate jq subprocesses)
#  - Bash printf %.1f for float compare (was 6 python3 cold-starts per refresh)
#  - Measured: 435 ms → ~80 ms wall (5× faster), CPU baseline 4.3% → ~0.8%

API="http://[::1]:8780"
PY_API="http://127.0.0.1:8779"

# Resolve script directory through symlinks so we can find sibling helpers
# regardless of whether the plugin is symlinked or installed in-place.
_resolve_script_dir() {
    local src="${BASH_SOURCE[0]}"
    while [ -L "$src" ]; do
        local target
        target=$(/usr/bin/readlink "$src")
        case "$target" in
            /*) src="$target" ;;
            *)  src="$(cd "$(dirname "$src")" && pwd)/$target" ;;
        esac
    done
    cd "$(dirname "$src")" && pwd
}
SCRIPT_DIR="$(_resolve_script_dir)"
ACTION="$SCRIPT_DIR/claude-hq-actions.sh"
TTS_TEST="$SCRIPT_DIR/tts-custom-test.sh"

# Helper: safe curl with timeout (SwiftBar runs with minimal PATH)
_curl() { /usr/bin/curl -sf --connect-timeout 2 --max-time 4 "$@" 2>/dev/null; }

# Fetch all four endpoints in PARALLEL — wall time becomes max(latency), not sum.
TMP=$(mktemp -d -t claude-hq.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
_curl "$API/health"      >"$TMP/health"     &
_curl "$API/settings"    >"$TMP/settings"   &
_curl "$API/tts/status"  >"$TMP/tts_status" &
_curl "$PY_API/health"   >"$TMP/py_health"  &
wait 2>/dev/null || true
HEALTH=$(/bin/cat "$TMP/health"     2>/dev/null) || HEALTH=""
SETTINGS=$(/bin/cat "$TMP/settings" 2>/dev/null) || SETTINGS=""
TTS_STATUS=$(/bin/cat "$TMP/tts_status" 2>/dev/null) || TTS_STATUS=""
PY_HEALTH=$(/bin/cat "$TMP/py_health"   2>/dev/null) || PY_HEALTH=""

# Single jq call per blob via @tsv — collapses ~28 jq forks down to 4.
# Order in the array determines order of `read` variables below.
_health_fields() {
    /usr/bin/jq -r '[
        .status // "ok",
        (.uptime_seconds // 0),
        (.rss_mb // 0 | round),
        .subsystems.bot // "unknown",
        .subsystems.tts // "unknown",
        .subsystems.subtitle // "unknown",
        .audio_routing_clean // true
    ] | @tsv' 2>/dev/null
}
_settings_fields() {
    /usr/bin/jq -r '[
        .subtitle.fontSize // "medium",
        .subtitle.position // "bottom",
        .subtitle.karaokeEnabled // true,
        .subtitle.screen // "builtin",
        .subtitle.displayMode // "karaoke",
        .subtitle.subtitleScope // "paragraph",
        (.subtitle.opacity // 0.3),
        (.subtitle.bionicSuffixOpacity // 0.7),
        .tts.enabled // true,
        .tts.voice // "af_heart",
        (.tts.speed // 1.0),
        (.tts.paragraphBudget // 500)
    ] | @tsv' 2>/dev/null
}
_tts_status_fields() {
    /usr/bin/jq -r '[(.isPlaying // false), (.queueDepth // 0)] | @tsv' 2>/dev/null
}
_py_health_fields() {
    /usr/bin/jq -r '[.status // "down", .device // "unknown"] | @tsv' 2>/dev/null
}

# Health parsing — one jq invocation, one read
if [ -n "$HEALTH" ]; then
    IFS=$'\t' read -r HEALTH_STATUS UPTIME_S RSS BOT TTS_ST SUB_ST AUDIO_CLEAN \
        < <(printf '%s' "$HEALTH" | _health_fields)
fi
if [ -n "${HEALTH_STATUS:-}" ] && { [ "$HEALTH_STATUS" = "ok" ] || [ "$HEALTH_STATUS" = "degraded" ]; }; then
    API_OK=true
    PID=$(pgrep -f claude-tts-companion 2>/dev/null) || true
    UPTIME_H=$((UPTIME_S / 3600))
    UPTIME_M=$(((UPTIME_S % 3600) / 60))
else
    API_OK=false
    HEALTH_STATUS="offline"
    AUDIO_CLEAN="true"
    PID=$(pgrep -f claude-tts-companion 2>/dev/null) || true
    BOT="offline"; TTS_ST="offline"; SUB_ST="offline"
    UPTIME_H=0; UPTIME_M=0; RSS=0
fi

# Python TTS server health — restarts after idle, so HTTP may fail transiently
PY_PID=$(pgrep -x 'kokoro-tts-server' 2>/dev/null | head -1) || true
PY_OK=false; PY_DEVICE=""; PY_RSS=""
if [ -n "$PY_HEALTH" ]; then
    IFS=$'\t' read -r PY_STATUS PY_DEVICE < <(printf '%s' "$PY_HEALTH" | _py_health_fields)
    if [ "$PY_STATUS" = "ok" ]; then
        PY_OK=true
        if [ -n "$PY_PID" ]; then
            PY_RSS=$(ps -o rss= -p "$PY_PID" 2>/dev/null | awk '{printf "%.0f", $1/1024}') || PY_RSS="?"
        else
            PY_RSS="?"
        fi
    fi
fi
if [ "$PY_OK" != true ] && [ -n "$PY_PID" ]; then
    PY_OK="restarting"
    PY_RSS=$(ps -o rss= -p "$PY_PID" 2>/dev/null | awk '{printf "%.0f", $1/1024}') || PY_RSS="?"
fi

# TTS playback status
if [ -n "$TTS_STATUS" ]; then
    IFS=$'\t' read -r TTS_PLAYING TTS_QUEUE_DEPTH < <(printf '%s' "$TTS_STATUS" | _tts_status_fields)
else
    TTS_PLAYING="false"; TTS_QUEUE_DEPTH="0"
fi

# Settings — one jq, 12 fields
if [ -n "$SETTINGS" ]; then
    IFS=$'\t' read -r FONT_SIZE POSITION KARAOKE SCREEN DISPLAY_MODE SUB_SCOPE \
        SUB_OPACITY BIONIC_OPACITY TTS_ON VOICE SPEED PARA_BUDGET \
        < <(printf '%s' "$SETTINGS" | _settings_fields)
else
    FONT_SIZE="medium"; POSITION="bottom"; KARAOKE="true"; SCREEN="builtin"
    DISPLAY_MODE="karaoke"; SUB_SCOPE="paragraph"
    SUB_OPACITY="0.3"; BIONIC_OPACITY="0.7"
    TTS_ON="true"; VOICE="af_heart"; SPEED="1.0"; PARA_BUDGET="500"
fi

# Helpers
dot() {
    case "$1" in
        ready|ok|watching|connected) echo "🟢" ;;
        disabled)                    echo "⚪" ;;
        stopped)                     echo "🟡" ;;
        *)                           echo "🔴" ;;
    esac
}

# Map bot status: "unknown" means token not set → show as "disabled"
bot_display() {
    case "$1" in
        unknown) echo "disabled" ;;
        *)       echo "$1" ;;
    esac
}

check() { [ "$1" = "$2" ] && echo "✅ " || echo "     "; }

# Capitalize first letter (macOS sed lacks \U, use tr instead)
ucfirst() { echo "$(echo "${1:0:1}" | tr '[:lower:]' '[:upper:]')${1:1}"; }

# Normalize a numeric string to "%.1f" for stable equality compare (no python fork)
norm1() { printf '%.1f' "$1" 2>/dev/null || echo "$1"; }

act() {
    local p2="${2:-}" p3="${3:-}"
    local out="bash=\"$ACTION\" param1=\"$1\" terminal=false refresh=true"
    [ -n "$p2" ] && out="$out param2=\"$p2\""
    [ -n "$p3" ] && out="$out param3=\"$p3\""
    echo "$out"
}

# Menu bar — show playing indicator when TTS is active
if [ "$API_OK" = true ]; then
    # Orange menu bar icon when health is degraded (audio routing issues)
    if [ "$HEALTH_STATUS" = "degraded" ]; then
        BAR_COLOR="#ff9500"
    else
        BAR_COLOR="#34c759"
    fi
    if [ "$TTS_PLAYING" = "true" ]; then
        if [ "$TTS_QUEUE_DEPTH" -gt 0 ] 2>/dev/null; then
            echo ":speaker.wave.3.fill: +${TTS_QUEUE_DEPTH} | sfcolor=$BAR_COLOR font=Menlo size=12"
        else
            echo ":speaker.wave.3.fill: | sfcolor=$BAR_COLOR font=Menlo size=12"
        fi
    else
        echo ":gearshape.2.fill: | sfcolor=$BAR_COLOR font=Menlo size=12"
    fi
else
    echo ":gearshape.2.fill: | sfcolor=#ff3b30 font=Menlo size=12"
fi

echo "---"

# Service section
echo ":server.rack: Service | size=13 color=#ffffff"
if [ -n "$PID" ]; then
    echo "🟢 claude-tts-companion  PID $PID | font=Menlo size=11"
    echo "-- ⏹ Stop    | $(act svc-stop com.terryli.claude-tts-companion "")"
    echo "-- 🔄 Restart | $(act svc-restart com.terryli.claude-tts-companion "")"
else
    echo "🔴 Not Running | font=Menlo size=11"
    echo "-- ▶️ Start | $(act svc-start com.terryli.claude-tts-companion "")"
fi

if [ "$PY_OK" = true ]; then
    echo "🟢 kokoro-tts-server  PID $PY_PID | font=Menlo size=11"
    echo "   ${PY_DEVICE}  RSS: ${PY_RSS} MB | font=Menlo size=10 color=#888888"
elif [ "$PY_OK" = "restarting" ]; then
    echo "🟡 kokoro-tts-server  restarting (PID $PY_PID) | font=Menlo size=11 color=#ff9500"
else
    echo "🔴 kokoro-tts-server DOWN | font=Menlo size=11 color=#ff3b30"
    echo "-- ▶️ Start | $(act svc-start com.terryli.kokoro-tts-server "")"
fi

# SSH Tunnel status (bigblack ClickHouse)
# Use lsof on the forwarded port — same detection as ssh-tunnel.5s.sh
SSH_PID=$(lsof -ti:18123 2>/dev/null | head -1) || true
if [ -n "$SSH_PID" ]; then
    # Port owner exists — verify ClickHouse actually responds through the tunnel
    CH_RESULT=$(/usr/bin/curl -sf --connect-timeout 2 --max-time 3 "http://localhost:18123" --data "SELECT 'ok' FORMAT TabSeparated" 2>/dev/null)
    if [ "$CH_RESULT" = "ok" ]; then
        echo "🟢 ssh-tunnel (bigblack)  PID $SSH_PID | font=Menlo size=11"
    else
        echo "🟡 ssh-tunnel (bigblack)  tunnel up, CH unreachable | font=Menlo size=11 color=#ff9500"
    fi
else
    echo "🔴 ssh-tunnel (bigblack)  DOWN | font=Menlo size=11 color=#ff3b30"
    echo "-- ▶️ Start | $(act svc-start com.terryli.ssh-tunnel-companion "")"
fi

BOT_LABEL=$(bot_display "$BOT")
if [ "$API_OK" = true ]; then
    echo "Uptime: ${UPTIME_H}h ${UPTIME_M}m   RSS: ${RSS} MB | font=Menlo size=11 color=#888888"
    echo "Subsystems: | font=Menlo size=11 color=#aaaaaa"
    echo "  $(dot "$BOT_LABEL") Bot: $BOT_LABEL   $(dot "$TTS_ST") TTS: $TTS_ST   $(dot "$SUB_ST") Subtitle: $SUB_ST | font=Menlo size=10 color=#888888"
    if [ "$AUDIO_CLEAN" != "true" ]; then
        echo "  ⚠️ Audio routing issue detected | font=Menlo size=10 color=#ff9500"
    fi
elif [ -n "$PID" ]; then
    echo "⚠️ API unreachable (service may be starting) | font=Menlo size=10 color=#ff9500"
fi

echo "---"

# Subtitle section
echo ":textformat.size: Subtitle | size=13 color=#ffffff"
echo "Font Size: $FONT_SIZE | font=Menlo size=11"
for sz in small medium large; do
    echo "-- $(check "$FONT_SIZE" "$sz")$(ucfirst "$sz") | $(act set-subtitle fontSize "$sz")"
done

echo "Position: $POSITION | font=Menlo size=11"
for pos in top middle bottom; do
    echo "-- $(check "$POSITION" "$pos")$(ucfirst "$pos") | $(act set-subtitle position "$pos")"
done

[ "$KARAOKE" = "true" ] && K_DOT="🟢" || K_DOT="🔴"
echo "$K_DOT Karaoke | $(act set-subtitle karaokeEnabled toggle)"

[ "$DISPLAY_MODE" = "bionic" ] && B_DOT="🟢" || B_DOT="🔴"
echo "$B_DOT Bionic Reading | $(act set-subtitle displayMode toggle-bionic)"
echo "-- Suffix Opacity: ${BIONIC_OPACITY} | font=Menlo size=10 color=#888888"
for op in 0.5 0.6 0.7 0.8 0.9; do
    echo "-- $([ "$BIONIC_OPACITY" = "$op" ] && echo "✅" || echo "    ")${op} | $(act set-subtitle bionicSuffixOpacity "$op")"
done

echo "Scope: $SUB_SCOPE | font=Menlo size=11"
for sc in paragraph sentence; do
    echo "-- $(check "$SUB_SCOPE" "$sc")$(ucfirst "$sc") | $(act set-subtitle subtitleScope "$sc")"
done
echo ":text.bubble: Caption History | $(act toggle-captions "" "")"

echo "Background Opacity: $SUB_OPACITY | font=Menlo size=11"
for op in 0.1 0.2 0.3 0.5 0.7; do
    echo "-- $([ "$SUB_OPACITY" = "$op" ] && echo "✅" || echo "    ")${op} | $(act set-subtitle opacity "$op")"
done

echo "Screen: $SCREEN | font=Menlo size=11"
for scr in builtin external; do
    label=$([ "$scr" = "builtin" ] && echo "Built-in" || echo "External")
    echo "-- $(check "$SCREEN" "$scr")$label | $(act set-subtitle screen "$scr")"
done

echo "---"

# TTS section
echo ":speaker.wave.3.fill: TTS | size=13 color=#ffffff"
[ "$TTS_ON" = "true" ] && T_DOT="🟢" || T_DOT="🔴"
echo "$T_DOT TTS Enabled | $(act set-tts enabled toggle)"

# Live playback status
if [ "$TTS_PLAYING" = "true" ]; then
    echo "▶ Now Playing | font=Menlo size=11 color=#34c759"
    if [ "$TTS_QUEUE_DEPTH" -gt 0 ] 2>/dev/null; then
        echo "   Queue: $TTS_QUEUE_DEPTH pending | font=Menlo size=10 color=#888888"
    fi
    echo "⏹ Stop Playback  ⌃ESC | $(act tts-stop) color=#ff3b30"
else
    echo "⏸ Idle | font=Menlo size=11 color=#888888"
fi

echo "Voice: $VOICE | font=Menlo size=11"
for vc in af_heart af_bella af_nicole af_sarah af_sky am_adam am_michael; do
    echo "-- $(check "$VOICE" "$vc")$vc | $(act set-tts voice "$vc")"
done

# Speed compare via bash printf '%.1f' — no python fork
SPEED_N=$(norm1 "$SPEED")
echo "Speed: ${SPEED}x | font=Menlo size=11"
for spd in 0.8 1.0 1.2 1.3 1.5 2.0; do
    if [ "$SPEED_N" = "$(norm1 "$spd")" ]; then
        mark="✅ "
    else
        mark="     "
    fi
    echo "-- ${mark}${spd}x | $(act set-tts speed "$spd")"
done

echo "Paragraph Budget: ${PARA_BUDGET} chars | font=Menlo size=11"
for pb in 0 300 500 800 1200; do
    label=$([ "$pb" = "0" ] && echo "Unlimited" || echo "${pb} chars")
    if [ "$PARA_BUDGET" = "$pb" ]; then
        mark="✅ "
    else
        mark="     "
    fi
    echo "-- ${mark}${label} | $(act set-tts paragraphBudget "$pb")"
done

echo "🔊 Test TTS | size=13"
echo "-- 🔊 Default test | $(act test-tts)"
echo "-- ✏️ Custom text… | bash=\"$TTS_TEST\" terminal=false refresh=true"

echo "---"
# Discoverability: reveal source files in Finder so future-you can find them
echo "📂 Reveal source… | bash=\"/usr/bin/open\" param1=\"-R\" param2=\"$SCRIPT_DIR/claude-hq.10s.sh\" terminal=false"
echo "Refresh Now | refresh=true"
