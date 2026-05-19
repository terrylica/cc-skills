#!/bin/bash
#
# tts-custom-test.sh — prompt user for arbitrary text via osascript dialog,
# then POST it through claude-hq-actions.sh to the companion's TTS endpoint.
# Invoked from the Claude HQ SwiftBar menu (✏️ Custom text…).
#
# SSoT: cc-skills/plugins/claude-tts-companion/swiftbar/tts-custom-test.sh
#
set -euo pipefail

USER_TEXT=$(/usr/bin/osascript -e '
tell application "System Events"
    display dialog "Enter text for TTS test:" default answer "" with title "Claude TTS Test"
    return text returned of result
end tell
' 2>/dev/null) || exit 0

# Exit if user cancelled or empty
[ -z "$USER_TEXT" ] && exit 0

# Resolve sibling action script through symlinks
_resolve_script_dir() {
    local src="${BASH_SOURCE[0]}"
    while [ -L "$src" ]; do
        local target
        target=$(/usr/bin/readlink "$src")
        case "$target" in
            /*) src="$target" ;;
            *)  src="$(cd "$(dirname "$src")" && pwd)/$target" ;;
        esac
    done
    cd "$(dirname "$src")" && pwd
}
SCRIPT_DIR="$(_resolve_script_dir)"
"$SCRIPT_DIR/claude-hq-actions.sh" test-tts "$USER_TEXT"
