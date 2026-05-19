#!/bin/bash
#
# claude-hq-actions.sh — action handler for the Claude HQ SwiftBar plugin.
# Invoked via `bash=` from claude-hq.10s.sh menu items. Performs the actual
# HTTP POST against the claude-tts-companion control plane on [::1]:8780.
#
# SSoT: cc-skills/plugins/claude-tts-companion/swiftbar/claude-hq-actions.sh
# Renamed 2026-05-18 from nc-action.sh (the name predated curl-based impl).
#
set -euo pipefail

UID_VAL=$(id -u)
LOG="$HOME/.local/state/swiftbar/actions.jsonl"
mkdir -p "$(dirname "$LOG")"

API_BASE="http://[::1]:8780"

# Structured JSONL telemetry -- pure bash, no python3 dependency
log_event() {
  local action="$1" status="$2" detail="${3:-}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Escape any double quotes in detail string
  detail="${detail//\"/\\\"}"
  printf '{"ts":"%s","action":"%s","status":"%s","detail":"%s","uid":%s,"pid":%s}\n' \
    "$ts" "$action" "$status" "$detail" "$UID_VAL" "$$" >> "$LOG"
}

svc_pid() {
  launchctl list 2>/dev/null | awk -F'\t' -v lbl="$1" '$3==lbl { pid=$1+0; print (pid>0 ? pid : 0); found=1 } END { if(!found) print 0 }'
}

case "$1" in
  svc-stop)
    label="${2:-com.terryli.claude-tts-companion}"
    before=$(svc_pid "$label")
    if launchctl bootout "gui/$UID_VAL/$label" 2>&1; then
      log_event "svc-stop:$label" "ok" "was_pid:$before"
    else
      log_event "svc-stop:$label" "FAIL" "was_pid:$before,exit:$?"
    fi ;;
  svc-start)
    label="${2:-com.terryli.claude-tts-companion}"
    plist="$HOME/Library/LaunchAgents/$label.plist"
    if launchctl bootstrap "gui/$UID_VAL" "$plist" 2>&1; then
      sleep 1
      after=$(svc_pid "$label")
      log_event "svc-start:$label" "ok" "new_pid:$after"
    else
      log_event "svc-start:$label" "FAIL" "exit:$?"
    fi ;;
  svc-restart)
    label="${2:-com.terryli.claude-tts-companion}"
    before=$(svc_pid "$label")
    if launchctl kickstart -k "gui/$UID_VAL/$label" 2>&1; then
      sleep 1
      after=$(svc_pid "$label")
      log_event "svc-restart:$label" "ok" "pid:$before->$after"
    else
      log_event "svc-restart:$label" "FAIL" "was_pid:$before,exit:$?"
    fi ;;
  set-subtitle)
    FIELD="$2"
    VALUE="$3"
    if [ "$VALUE" = "toggle" ] && [ "$FIELD" = "karaokeEnabled" ]; then
      # Boolean toggle: read current via jq (outputs true/false), post opposite
      CUR=$(/usr/bin/curl -sf --max-time 2 "$API_BASE/settings" | /usr/bin/jq -r '.subtitle.karaokeEnabled') || CUR="true"
      [ "$CUR" = "true" ] && NEW="false" || NEW="true"
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"karaokeEnabled\":$NEW}" "$API_BASE/settings/subtitle" >/dev/null; then
        log_event "set-subtitle:$FIELD" "ok" "toggled:$CUR->$NEW"
      else
        log_event "set-subtitle:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    elif [ "$VALUE" = "toggle-bionic" ] && [ "$FIELD" = "displayMode" ]; then
      # Toggle between karaoke and bionic display modes
      CUR=$(/usr/bin/curl -sf --max-time 2 "$API_BASE/settings" | /usr/bin/jq -r '.subtitle.displayMode') || CUR="karaoke"
      [ "$CUR" = "bionic" ] && NEW="karaoke" || NEW="bionic"
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"displayMode\":\"$NEW\"}" "$API_BASE/settings/subtitle" >/dev/null; then
        log_event "set-subtitle:$FIELD" "ok" "toggled:$CUR->$NEW"
      else
        log_event "set-subtitle:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    elif [ "$FIELD" = "bionicSuffixOpacity" ]; then
      # Opacity is a float -- pass as JSON number, not string
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"bionicSuffixOpacity\":$VALUE}" "$API_BASE/settings/subtitle" >/dev/null; then
        log_event "set-subtitle:$FIELD" "ok" "value:$VALUE"
      else
        log_event "set-subtitle:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    else
      # String field: fontSize, position, screen, subtitleScope
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"$FIELD\":\"$VALUE\"}" "$API_BASE/settings/subtitle" >/dev/null; then
        log_event "set-subtitle:$FIELD" "ok" "value:$VALUE"
      else
        log_event "set-subtitle:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    fi ;;
  set-tts)
    FIELD="$2"
    VALUE="$3"
    if [ "$VALUE" = "toggle" ] && [ "$FIELD" = "enabled" ]; then
      # Boolean toggle: read current via jq (outputs true/false), post opposite
      CUR=$(/usr/bin/curl -sf --max-time 2 "$API_BASE/settings" | /usr/bin/jq -r '.tts.enabled') || CUR="true"
      [ "$CUR" = "true" ] && NEW="false" || NEW="true"
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"enabled\":$NEW}" "$API_BASE/settings/tts" >/dev/null; then
        log_event "set-tts:$FIELD" "ok" "toggled:$CUR->$NEW"
      else
        log_event "set-tts:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    elif [ "$FIELD" = "speed" ]; then
      # Speed is a float -- pass as JSON number, not string
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"speed\":$VALUE}" "$API_BASE/settings/tts" >/dev/null; then
        log_event "set-tts:speed" "ok" "value:$VALUE"
      else
        log_event "set-tts:speed" "FAIL" "api_unreachable_or_error"
      fi
    elif [ "$FIELD" = "paragraphBudget" ]; then
      # paragraphBudget is an int -- pass as JSON number
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"paragraphBudget\":$VALUE}" "$API_BASE/settings/tts" >/dev/null; then
        log_event "set-tts:paragraphBudget" "ok" "value:$VALUE"
      else
        log_event "set-tts:paragraphBudget" "FAIL" "api_unreachable_or_error"
      fi
    else
      # Other string fields: voice, etc.
      if /usr/bin/curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
        -d "{\"$FIELD\":\"$VALUE\"}" "$API_BASE/settings/tts" >/dev/null; then
        log_event "set-tts:$FIELD" "ok" "value:$VALUE"
      else
        log_event "set-tts:$FIELD" "FAIL" "api_unreachable_or_error"
      fi
    fi ;;
  test-tts)
    TEXT="${2:-}"
    if [ -n "$TEXT" ]; then
      # Use jq to safely encode arbitrary text as JSON string (handles quotes, newlines, unicode)
      JSON=$(/usr/bin/jq -n --arg t "$TEXT" '{"text":$t}')
    else
      JSON='{"text":"This is a test of the Claude TTS companion."}'
    fi
    # User-initiated TTS blocks until playback completes — use generous timeout (60s)
    if /usr/bin/curl -sf --max-time 60 -X POST \
        -H 'Content-Type: application/json' \
        -H 'X-TTS-Priority: user-initiated' \
        -d "$JSON" "$API_BASE/tts/speak" >/dev/null; then
      log_event "test-tts" "ok" "sent"
    else
      log_event "test-tts" "FAIL" "api_unreachable_or_timeout"
    fi ;;
  tts-stop)
    if /usr/bin/curl -sf --max-time 5 -X POST "$API_BASE/tts/stop" >/dev/null 2>&1; then
      log_event "tts-stop" "ok" "stopped"
    else
      log_event "tts-stop" "FAIL" "api_unreachable"
    fi ;;
  toggle-captions)
    # Show caption history panel (close via window's red button)
    if /usr/bin/curl -sf --max-time 3 -X POST "$API_BASE/captions/panel/show" >/dev/null 2>&1; then
      log_event "toggle-captions" "ok" "show"
    else
      log_event "toggle-captions" "FAIL" "api_unreachable"
    fi ;;
  *)
    log_event "unknown:${1:-empty}" "FAIL" "args:$*"
    exit 1 ;;
esac
