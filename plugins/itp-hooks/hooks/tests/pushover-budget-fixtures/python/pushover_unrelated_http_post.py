#!/usr/bin/env python3
import requests

def send_webhook():
    """Send data to unrelated webhook endpoint (not Pushover)."""
    response = requests.post(
        "https://webhook.example.com/events",
        json={
            "event_type": "deployment",
            "service": "pushover-cli-tool",
            "status": "success",
            "timestamp": "2026-05-29T14:23:00Z"
        }
    )
    return response.json()

send_webhook()
