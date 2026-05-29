#!/usr/bin/env python3
import urllib.request
import urllib.parse

token = "app_token_secret"
user_key = "user_key_secret"

# Minimal Pushover send: title only, empty message
params = urllib.parse.urlencode({
    "token": token,
    "user": user_key,
    "title": "Health Check Passed",
    "message": "",  # empty message field
    "priority": -1
})

url = f"https://api.pushover.net/1/messages.json?{params}"
with urllib.request.urlopen(url) as response:
    print(response.read())
