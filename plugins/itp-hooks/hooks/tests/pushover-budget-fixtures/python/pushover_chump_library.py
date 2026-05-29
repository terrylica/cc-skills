#!/usr/bin/env python3
from chump import Application

app = Application("app_token_from_1password")
user = app.get_user("user_key_from_1password")

message = user.send_message(
    title="Server Memory Alert",
    message="RAM utilization exceeded 90% threshold (1847 MB / 2048 MB). Investigation required. Check runaway processes with top.",
    priority=1,
    sound="siren"
)

if message.is_receipt:
    print(f"Emergency message sent, receipt: {message.receipt}")
