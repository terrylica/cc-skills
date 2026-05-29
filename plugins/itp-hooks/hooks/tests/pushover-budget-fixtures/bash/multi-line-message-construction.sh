#!/usr/bin/env bash
# Build a Pushover message across multiple lines
set -euo pipefail

SERVICE_NAME="database-backup"
BACKUP_SIZE="2.4GB"
DURATION="45m"
LAST_SUCCESS="2026-05-28T14:32:00Z"

# Assemble the message body in stages
MSG_HEADER="Backup complete"
MSG_DETAILS="Size: $BACKUP_SIZE\nDuration: $DURATION\nLast: $LAST_SUCCESS"
MSG_FOOTER="All critical tables verified."

# Combine into full body
MESSAGE_BODY="${MSG_HEADER}\n\n${MSG_DETAILS}\n\n${MSG_FOOTER}"

# Send via curl to Pushover
curl -X POST https://api.pushover.net/1/messages.json \
  -d "token=${PUSHOVER_TOKEN}" \
  -d "user=${PUSHOVER_USER}" \
  -d "title=Database Backup Report" \
  -d "message=${MESSAGE_BODY}"
