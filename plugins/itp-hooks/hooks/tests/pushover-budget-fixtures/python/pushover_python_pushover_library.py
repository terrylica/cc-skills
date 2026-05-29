#!/usr/bin/env python3
from pushover import Client

client = Client(
    "user_key",
    api_token="app_token"
)

# Create and send alert message
title = "Kubernetes Node Alert"
message = "Node 'worker-3' has been NotReady for 8 minutes. Attempting eviction of 23 pods. New node: us-west-2c. Check CloudWatch for details."
priority = 1

client.send_message(
    message=message,
    title=title,
    priority=priority,
    sound="siren"
)
