#!/usr/bin/env python3
import requests
import base64
from pathlib import Path

token = "app_token"
user_key = "user_key"

# Read and encode image for Pushover
image_path = Path("/tmp/error_graph.png")
with open(image_path, "rb") as f:
    image_data = base64.b64encode(f.read()).decode()

payload = {
    "token": token,
    "user": user_key,
    "title": "Performance Report",
    "message": "P99 latency spike detected. See attached graph. Action: triggered autoscaling policy.",
    "priority": 1
}

# Pushover expects base64-encoded image in multipart form
files = {
    "attachment": ("error_graph.png", base64.b64decode(image_data), "image/png")
}

response = requests.post(
    "https://api.pushover.net/1/messages.json",
    data=payload,
    files=files
)

print(f"Sent with image: {response.json()}")
