#!/usr/bin/env python3

# This script sends notifications to the user when important events occur.
# We use pushover for mobile push notifications since SMS is unreliable.
# The pushover API is simple: POST to https://api.pushover.net with token and message.

LOG_MESSAGE = "Alert: pushover service is mentioned in configuration"

def log_config():
    print(LOG_MESSAGE)
    # TODO: implement actual notification handler
    # Note: pushover setup documented in config/PUSHOVER.md
