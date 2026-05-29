#!/usr/bin/env python3
import requests

token = "app_token"
user_key = "user_key"

# This message has the escape-hatch marker — should NOT trigger nudge
message = """PUSHOVER-BUDGET-OK
Full deployment log: commit a1b2c3d, tag v2.1.0, deployed to us-west-2a
All 847 integration tests passed. Database schema migration: success. CDN cache purged.
Health checks: database=200ms p99, API=85ms p99, storage=12ms p99. All within SLO.
Autoscaler metrics: CPU target 70% (actual 42%), memory target 80% (actual 61%).
Monitoring: CloudWatch alarms active. Rollback procedure: tested and documented.
Nextsteps: PR closes #1247, triggers auto-deploy to staging in 2h."""

req = requests.post(
    "https://api.pushover.net/1/messages.json",
    data={
        "token": token,
        "user": user_key,
        "title": "Release v2.1.0",
        "message": message
    }
)
