#!/usr/bin/env bash
# Load Pushover configuration from heredoc

read -r -d '' PUSHOVER_CONFIG <<'EOF' || true
Pushover API Configuration

Endpoint: https://api.pushover.net/1/messages.json

Required Parameters:
  - token: application token (from Pushover dashboard)
  - user: recipient user key (from Pushover app)
  - title: notification title (max 250 chars)
  - message: notification body (max 1024 chars)
  - priority: -2 to 2 (default 0)

Optional:
  - device: target device name
  - sound: notification sound name
  - url: supplementary URL (max 512 chars)
  - url_title: URL title (max 100 chars)
EOF

echo "$PUSHOVER_CONFIG"
