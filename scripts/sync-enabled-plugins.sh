#!/usr/bin/env bash
#
# Sync enabled plugins: auto-enable NEW cc-skills plugins in settings.json
#
# Every plugin registered in marketplace.json gets an `enabledPlugins` key in
# ~/.claude/settings.json, so a plugin added to the marketplace is usable
# without a manual enable. A key that already exists is never rewritten:
# `true` stays `true`, and `false` (the user switched the plugin off) stays
# `false`.
#
# Presence is tested with jq's `has()`, never with the `//` alternative
# operator. `//` yields its right-hand side for `false` as well as for null
# and absent, so `.enabledPlugins[$key] // "missing"` reports a plugin the
# user disabled as "missing". This script used that expression from its first
# version, and so every release switched every disabled cc-skills plugin back
# on: 18 of them in one run, two minutes after they had been disabled, while
# the disabled plugins of other marketplaces in the same file kept `false`.
# Regression test: tasks/tests/test-sync-enabled-plugins-respects-disabled.sh
#
# The file is rewritten at most once per run, only when a key is added, and by
# renaming a temporary file made next to it, so another reader never sees a
# half-written settings.json.
#
# Usage: ./scripts/sync-enabled-plugins.sh   (from the repository root)
#
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
MARKETPLACE_FILE=".claude-plugin/marketplace.json"
readonly MARKETPLACE_SUFFIX="@cc-skills"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "  ⚠ Settings file not found: $SETTINGS_FILE"
    exit 0
fi

if [[ ! -f "$MARKETPLACE_FILE" ]]; then
    echo "  ⚠ Marketplace file not found: $MARKETPLACE_FILE"
    exit 0
fi

# A settings.json is user-authored: `enabledPlugins` may be absent or null
# (treated as empty), or something that is not an object (malformed input this
# script must not rewrite).
ENABLED_PLUGINS_TYPE=$(jq -r '.enabledPlugins | type' "$SETTINGS_FILE")
if [[ "$ENABLED_PLUGINS_TYPE" != "object" && "$ENABLED_PLUGINS_TYPE" != "null" ]]; then
    echo "  ⚠ enabledPlugins in $SETTINGS_FILE is a $ENABLED_PLUGINS_TYPE, not an object — leaving it untouched"
    exit 0
fi

# One line per marketplace plugin: "<state>\t<key>", where state is `missing`
# (no key at all), `enabled` (true), `disabled` (false) or `other` (a key with
# any other value, which is also left alone).
# shellcheck disable=SC2016  # $enabled, $marketplace, $suffix and $key are jq variables
readonly JQ_CLASSIFY_MARKETPLACE_PLUGINS='
    (.enabledPlugins // {}) as $enabled
    | $marketplace[0].plugins[].name
    | (. + $suffix) as $key
    | (if ($enabled | has($key)) | not then "missing"
       elif $enabled[$key] == true then "enabled"
       elif $enabled[$key] == false then "disabled"
       else "other"
       end) + "\t" + $key
'

CLASSIFIED=$(jq -r --slurpfile marketplace "$MARKETPLACE_FILE" --arg suffix "$MARKETPLACE_SUFFIX" \
    "$JQ_CLASSIFY_MARKETPLACE_PLUGINS" "$SETTINGS_FILE")

MISSING_KEYS=()
ALREADY_ENABLED=0
LEFT_DISABLED=0
while IFS=$'\t' read -r STATE PLUGIN_KEY; do
    case "$STATE" in
        missing) MISSING_KEYS+=("$PLUGIN_KEY") ;;
        enabled) ALREADY_ENABLED=$((ALREADY_ENABLED + 1)) ;;
        disabled) LEFT_DISABLED=$((LEFT_DISABLED + 1)) ;;
        *) ;;
    esac
done <<< "$CLASSIFIED"

DISABLED_NOTE=""
if [[ $LEFT_DISABLED -gt 0 ]]; then
    DISABLED_NOTE=", $LEFT_DISABLED disabled by you and left off"
fi

if [[ ${#MISSING_KEYS[@]} -eq 0 ]]; then
    echo "  ✓ All $ALREADY_ENABLED plugins already enabled$DISABLED_NOTE"
    exit 0
fi

# Add every missing key in one pass. The temporary file starts as a copy of
# the original so it keeps the original's permissions, and lives in the same
# directory so the final rename stays on one filesystem.
SETTINGS_TMP=$(mktemp "${SETTINGS_FILE}.sync-enabled.XXXXXX")
trap 'rm -f "$SETTINGS_TMP"' EXIT
cp -p "$SETTINGS_FILE" "$SETTINGS_TMP"

# shellcheck disable=SC2016  # $ARGS and $key are jq variables
readonly JQ_ENABLE_MISSING_KEYS='
    .enabledPlugins = (reduce $ARGS.positional[] as $key (.enabledPlugins // {}; .[$key] = true))
'

jq "$JQ_ENABLE_MISSING_KEYS" --args "${MISSING_KEYS[@]}" < "$SETTINGS_FILE" > "$SETTINGS_TMP"

if ! jq -e 'type == "object"' "$SETTINGS_TMP" >/dev/null 2>&1; then
    echo "  ⚠ Enabling new plugins produced invalid JSON — leaving settings.json untouched"
    exit 1
fi

mv "$SETTINGS_TMP" "$SETTINGS_FILE"

for PLUGIN_KEY in "${MISSING_KEYS[@]}"; do
    echo "  + Enabled new plugin: $PLUGIN_KEY"
done
echo "  ✓ Enabled ${#MISSING_KEYS[@]} new plugin(s), $ALREADY_ENABLED already enabled$DISABLED_NOTE"
