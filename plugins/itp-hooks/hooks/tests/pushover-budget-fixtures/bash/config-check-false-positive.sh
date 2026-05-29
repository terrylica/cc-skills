#!/usr/bin/env bash
# Configuration file for deployment pipeline

# Feature flags
DEBUG=true
VERBOSE=false
pushover_enabled=true  # Enable Pushover notifications for this deployment
slack_enabled=false

# This is just a config flag, not an actual message send
echo "Configuration loaded:"
echo "  Debug: $DEBUG"
echo "  Pushover enabled: $pushover_enabled"
echo "  Slack enabled: $slack_enabled"
