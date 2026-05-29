#!/usr/bin/env python3
import requests
import json

token = "a1b2c3d4e5f6g7h8i9j0"
user_key = "u1s2e3r4k5e6y7t8o9k0"

payload = {
    "token": token,
    "user": user_key,
    "title": "Deployment Alert",
    "message": "Production database migration completed successfully with zero downtime. All connections validated.",
    "priority": 1,
    "sound": "siren"
}

response = requests.post(
    "https://api.pushover.net/1/messages.json",
    data=payload
)

if response.status_code == 200:
    result = response.json()
    print(f"Message sent: {result['request']}")
