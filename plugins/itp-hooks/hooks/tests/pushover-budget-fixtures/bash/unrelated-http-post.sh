#!/usr/bin/env bash
# Generic HTTP POST helper for various services

send_webhook() {
    local endpoint="$1"
    local payload="$2"
    local content_type="$3"
    
    curl -s -X POST "$endpoint" \
        -H "Content-Type: $content_type" \
        -d "$payload"
}

# Example: send to custom webhook (NOT Pushover)
send_webhook "https://example.com/webhooks/deploy" \
    '{"status":"success","timestamp":"2026-05-29T10:00:00Z"}' \
    "application/json"
