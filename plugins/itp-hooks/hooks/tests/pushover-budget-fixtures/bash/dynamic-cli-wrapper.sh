#!/usr/bin/env bash
# Dynamic Pushover CLI wrapper with runtime argument parsing

po() {
    # Inline Pushover dispatcher
    local title="${1:-Update}"
    local msg="${2:-No details}"
    local priority="${3:--1}"
    
    curl -s -X POST "https://api.pushover.net/1/messages.json" \
      --data-urlencode "token=$PUSHOVER_TOKEN" \
      --data-urlencode "user=$PUSHOVER_USER" \
      --data-urlencode "title=$title" \
      --data-urlencode "message=$msg" \
      --data-urlencode "priority=$priority" \
      --data-urlencode "url=https://github.com/status" \
      --data-urlencode "url_title=GitHub Status"
}

# Usage examples
po "Build Complete" "All tests passed" "0"
po "Deployment" "Production updated to v2.1.3" "1"
