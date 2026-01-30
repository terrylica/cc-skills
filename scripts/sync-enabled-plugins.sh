#!/usr/bin/env bash
#
# Sync enabled plugins: auto-enable new cc-skills plugins in settings.json
#
# This script ensures all plugins registered in marketplace.json are enabled
# in ~/.claude/settings.json. Prevents the "plugin not found" issue when
# new plugins are added to the marketplace.
#
# Usage: ./scripts/sync-enabled-plugins.sh
#
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
MARKETPLACE_FILE=".claude-plugin/marketplace.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "  ⚠ Settings file not found: $SETTINGS_FILE"
    exit 0
fi

if [[ ! -f "$MARKETPLACE_FILE" ]]; then
    echo "  ⚠ Marketplace file not found: $MARKETPLACE_FILE"
    exit 0
fi

# Get all plugin names from marketplace.json
PLUGIN_NAMES=$(jq -r '.plugins[].name' "$MARKETPLACE_FILE")

# Track what we enable
ENABLED_COUNT=0
ALREADY_ENABLED=0

for PLUGIN in $PLUGIN_NAMES; do
    PLUGIN_KEY="${PLUGIN}@cc-skills"

    # Check if already in settings (either true or false)
    CURRENT=$(jq -r ".enabledPlugins[\"$PLUGIN_KEY\"] // \"missing\"" "$SETTINGS_FILE")

    if [[ "$CURRENT" == "missing" ]]; then
        # New plugin - add and enable it
        jq ".enabledPlugins[\"$PLUGIN_KEY\"] = true" "$SETTINGS_FILE" > /tmp/settings.json.tmp
        mv /tmp/settings.json.tmp "$SETTINGS_FILE"
        echo "  + Enabled new plugin: $PLUGIN_KEY"
        ((ENABLED_COUNT++))
    elif [[ "$CURRENT" == "true" ]]; then
        ((ALREADY_ENABLED++))
    fi
    # If false, respect user's choice to disable
done

if [[ $ENABLED_COUNT -gt 0 ]]; then
    echo "  ✓ Enabled $ENABLED_COUNT new plugin(s), $ALREADY_ENABLED already enabled"
else
    echo "  ✓ All $ALREADY_ENABLED plugins already enabled"
fi
