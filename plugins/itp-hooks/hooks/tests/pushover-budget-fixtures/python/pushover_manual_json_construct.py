#!/usr/bin/env python3
import json
import urllib.request

token = "abc123def456"
user_key = "xyz789uv123"

# Build message via dict, then JSON encode
message_dict = {
    "token": token,
    "user": user_key,
    "title": "Critical System Alert",
    "message": "CPU utilization 95%. Memory utilization 88%. Disk write latency 450ms. Investigate ASAP. Service: database-primary. Region: us-east-1a.",
    "priority": 2,
    "retry": 30,
    "expire": 600
}

json_payload = json.dumps(message_dict)

# Send via raw HTTP request
req = urllib.request.Request(
    "https://api.pushover.net/1/messages.json",
    data=json_payload.encode(),
    headers={"Content-Type": "application/json"}
)

with urllib.request.urlopen(req) as response:
    result = json.loads(response.read())
    print(f"Response: {result['status']}")
