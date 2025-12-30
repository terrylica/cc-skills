#!/bin/bash
# One-time migration: rssi-*.json → ralph-*.json
# Run this script after upgrading to the Ralph-renamed version
#
# Usage: ./scripts/migrate-rssi-to-ralph.sh
#
# This script preserves 99 iterations of learning data accumulated
# in the RSSI state files by renaming them to the new Ralph naming.

set -euo pipefail

STATE_DIR="$HOME/.claude/automation/loop-orchestrator/state"

echo "Migrating RSSI state files to Ralph naming..."
echo "State directory: $STATE_DIR"
echo ""

# Check if state directory exists
if [[ ! -d "$STATE_DIR" ]]; then
    echo "State directory does not exist. No migration needed."
    exit 0
fi

MIGRATED=0

# Migrate knowledge file
if [[ -f "$STATE_DIR/rssi-knowledge.json" ]]; then
    if [[ -f "$STATE_DIR/ralph-knowledge.json" ]]; then
        echo "⚠ ralph-knowledge.json already exists, skipping rssi-knowledge.json"
    else
        mv "$STATE_DIR/rssi-knowledge.json" "$STATE_DIR/ralph-knowledge.json"
        echo "✓ Migrated rssi-knowledge.json → ralph-knowledge.json"
        MIGRATED=$((MIGRATED + 1))
    fi
else
    echo "• rssi-knowledge.json not found (may already be migrated)"
fi

# Migrate evolution file
if [[ -f "$STATE_DIR/rssi-evolution.json" ]]; then
    if [[ -f "$STATE_DIR/ralph-evolution.json" ]]; then
        echo "⚠ ralph-evolution.json already exists, skipping rssi-evolution.json"
    else
        mv "$STATE_DIR/rssi-evolution.json" "$STATE_DIR/ralph-evolution.json"
        echo "✓ Migrated rssi-evolution.json → ralph-evolution.json"
        MIGRATED=$((MIGRATED + 1))
    fi
else
    echo "• rssi-evolution.json not found (may already be migrated)"
fi

echo ""
if [[ $MIGRATED -gt 0 ]]; then
    echo "Migration complete. $MIGRATED file(s) migrated."
    echo "All accumulated learning data has been preserved."
else
    echo "No files needed migration."
fi
