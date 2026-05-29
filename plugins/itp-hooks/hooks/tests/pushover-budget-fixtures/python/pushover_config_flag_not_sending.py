#!/usr/bin/env python3

config = {
    "pushover_enabled": True,
    "pushover_token": "app_token",
    "pushover_user_key": "user_key",
    "pushover_priority": 1,
    "pushover_sound": "siren",
    "logging_level": "INFO"
}

def should_notify():
    return config.get("pushover_enabled", False)

if should_notify():
    print("Notifications enabled")
