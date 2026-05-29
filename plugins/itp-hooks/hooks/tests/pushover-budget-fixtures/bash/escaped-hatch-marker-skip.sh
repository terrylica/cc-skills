#!/usr/bin/env bash
# Pushover message already marked with escape hatch
set -euo pipefail

PUSHOVER_TOKEN="${PUSHOVER_TOKEN}"
PUSHOVER_USER="${PUSHOVER_USER}"

# This message is pre-approved by ops; skip nudge hook
TITLE="Critical Alert: Database Down"
MESSAGE="Database connection pool exhausted. PUSHOVER-BUDGET-OK"
PRIORITY=2

curl -s -X POST https://api.pushover.net/1/messages.json \
  --data-urlencode "token=$PUSHOVER_TOKEN" \
  --data-urlencode "user=$PUSHOVER_USER" \
  --data-urlencode "title=$TITLE" \
  --data-urlencode "message=$MESSAGE" \
  --data-urlencode "priority=$PRIORITY"
