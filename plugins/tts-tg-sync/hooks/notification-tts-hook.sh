#!/bin/bash
# notification-tts-hook.sh — Trigger TTS for Claude Code notifications
# Fires when Claude Code is waiting for user input (including plan mode approval)
#
# Input (stdin JSON): { message, title?, notification_type, session_id, cwd, transcript_path }
# notification_type values: permission_prompt, idle_prompt, auth_success, elicitation_dialog

set -euo pipefail
export PATH="/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

LOG="/tmp/notification-tts-hook.log"
TTS_API="http://localhost:8780"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

# Read stdin JSON
INPUT=$(cat)
log "Notification hook fired: $INPUT"

# Parse fields
NOTIFICATION_TYPE=$(echo "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('notification_type','unknown'))" 2>/dev/null) || NOTIFICATION_TYPE="unknown"
MESSAGE=$(echo "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null) || MESSAGE=""
SESSION_ID=$(echo "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null) || SESSION_ID=""
CWD=$(echo "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null) || CWD=""
TRANSCRIPT_PATH=$(echo "$INPUT" | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null) || TRANSCRIPT_PATH=""

log "Type=$NOTIFICATION_TYPE Message='${MESSAGE:0:100}' CWD=$CWD Session=$SESSION_ID"

# Only trigger TTS for these notification types:
# - idle_prompt: Claude is done and waiting (includes plan mode approval)
# - permission_prompt: Claude needs permission to proceed
case "$NOTIFICATION_TYPE" in
    idle_prompt|permission_prompt)
        log "Actionable notification — writing for TTS companion"
        
        # Check if TTS companion is running
        if ! /usr/bin/curl -sf --max-time 2 "$TTS_API/health" >/dev/null 2>&1; then
            log "TTS companion not running — skipping"
            exit 0
        fi
        
        # Write notification file for companion to pick up
        NOTIF_DIR="$HOME/.claude/notifications"
        mkdir -p "$NOTIF_DIR"
        
        # Extract project name from CWD
        PROJECT=$(basename "$CWD" 2>/dev/null || echo "unknown")
        
        /usr/bin/python3 -c "
import json, sys, os
from datetime import datetime, timezone

notif = {
    'sessionId': '$SESSION_ID',
    'cwd': '$CWD',
    'slug': 'notification',
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'transcriptPath': '$TRANSCRIPT_PATH',
    'notificationType': '$NOTIFICATION_TYPE',
    'message': '''$MESSAGE''',
    'source': 'notification-hook'
}

path = os.path.join('$NOTIF_DIR', '$SESSION_ID' + '.json')
with open(path, 'w') as f:
    json.dump(notif, f, indent=2)
print(f'Wrote notification to {path}', file=sys.stderr)
" 2>>"$LOG"
        
        log "Notification file written for session $SESSION_ID"
        ;;
    *)
        log "Ignoring notification type: $NOTIFICATION_TYPE"
        ;;
esac
