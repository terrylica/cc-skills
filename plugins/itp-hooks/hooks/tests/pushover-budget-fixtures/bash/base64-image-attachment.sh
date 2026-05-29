#!/usr/bin/env bash
# Send Pushover notification with base64-encoded image attachment
set -euo pipefail

TITLE="Screenshot Alert"
MESSAGE="System resource usage graph attached"

# Encode PNG as base64
IMAGE_PATH="/tmp/metrics-dashboard.png"
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_B64=$(base64 -i "$IMAGE_PATH")
    
    # Send with image attachment
    curl -s -X POST "https://api.pushover.net/1/messages.json" \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$TITLE" \
      --form-string "message=$MESSAGE" \
      --form "image=@$IMAGE_PATH"
fi
