"""Cal.com → Pushover webhook relay.

Receives Cal.com booking webhooks and sends Pushover emergency alerts
with a configurable custom sound (default: "dune").

Deployed as GCP Cloud Run service. Secrets injected via environment variables.

Environment variables:
  PUSHOVER_TOKEN  — Pushover application token (required)
  PUSHOVER_USER   — Pushover user key (required)
  PUSHOVER_SOUND  — Custom sound name (optional, default: "dune")
  PORT            — HTTP port (optional, default: 8080)
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PUSHOVER_API = "https://api.pushover.net/1/messages.json"
PORT = int(os.environ.get("PORT", 8080))
DEFAULT_SOUND = os.environ.get("PUSHOVER_SOUND", "dune")


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            payload = json.loads(body) if body else {}
        except json.JSONDecodeError:
            payload = {}

        trigger_event = payload.get("triggerEvent", "unknown")
        booking = payload.get("payload", {})
        title = booking.get("title", "New Booking")
        attendee_name = ""
        attendees = booking.get("attendees", [])
        if attendees:
            attendee_name = attendees[0].get("name", "")
        start_time = booking.get("startTime", "")
        end_time = booking.get("endTime", "")

        message = f"{title}"
        if attendee_name:
            message += f"\nWith: {attendee_name}"
        if start_time:
            message += f"\nStart: {start_time}"
        if end_time:
            message += f"\nEnd: {end_time}"

        pushover_token = os.environ.get("PUSHOVER_TOKEN", "")
        pushover_user = os.environ.get("PUSHOVER_USER", "")

        if not pushover_token or not pushover_user:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'{"error": "missing pushover credentials"}')
            return

        if trigger_event in ("BOOKING_CREATED", "BOOKING_RESCHEDULED"):
            pushover_title = "Cal.com: New Booking!"
            priority = 2
        elif trigger_event == "BOOKING_CANCELLED":
            pushover_title = "Cal.com: Booking Cancelled"
            priority = 0
        else:
            pushover_title = f"Cal.com: {trigger_event}"
            priority = 0

        data = urllib.parse.urlencode({
            "token": pushover_token,
            "user": pushover_user,
            "title": pushover_title,
            "message": message,
            "priority": priority,
            "sound": DEFAULT_SOUND,
            **({"retry": 30, "expire": 300} if priority == 2 else {}),
        }).encode()

        try:
            req = urllib.request.Request(PUSHOVER_API, data=data, method="POST")
            with urllib.request.urlopen(req) as resp:
                result = resp.read().decode()
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
            result = str(e)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "status": "ok",
            "trigger": trigger_event,
            "pushover": result,
        }).encode())

    def do_GET(self):
        """Health check endpoint."""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status": "healthy", "service": "calcom-pushover-webhook"}')


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), WebhookHandler)
    print(f"Webhook server listening on port {PORT}")
    server.serve_forever()
