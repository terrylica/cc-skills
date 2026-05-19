#!/usr/bin/env bash
#
# fda-grant-walkthrough.sh — interactive helper for granting macOS Full Disk Access (FDA)
# to a launchd-spawned binary that needs to read sandbox-protected paths.
#
# Iter 21 (2026-05-19). Closes the 16-iter chronic-failure pattern that
# caught maccy-backup: a launchd job spawns a binary; the binary tries to
# read ~/Library/Containers/<app>/Data/...; macOS TCC denies because the
# launchd-spawned binary isn't in the FDA allowlist; the user has known
# about the failure for weeks but never made the manual grant happen
# because the click-path is buried.
#
# What FDA means: Full Disk Access — the permission category in
# System Settings → Privacy & Security → Full Disk Access. Apps in that
# list can read files in macOS-sandboxed locations (Containers, Mail,
# Messages, Safari, etc.). Outside the list, even your own scripts fail
# silently or with "operation not permitted" errors.
#
# Why TCC is involved: TCC (Transparency, Consent, Control) is the
# underlying subsystem; FDA is one specific permission category within
# TCC. We cannot grant TCC programmatically — Apple's design — the
# user must physically click through System Settings while authenticated
# with Touch ID or password.
#
# Usage:
#   fda-grant-walkthrough <binary-path>           # full walkthrough
#   fda-grant-walkthrough --check <binary-path>   # check current grant state, exit only
#   fda-grant-walkthrough --help                  # this help
#
# Exit codes:
#   0 = binary already has FDA (or walkthrough launched successfully)
#   1 = usage error
#   2 = binary not found or not executable
#   3 = (--check only) binary does NOT have FDA
#

set -euo pipefail

CHECK_ONLY=0
BIN_PATH=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)
            CHECK_ONLY=1; shift
            ;;
        --help|-h)
            /bin/cat <<'USAGE_EOF'
fda-grant-walkthrough — open System Settings to the FDA pane + walk through granting

USAGE:
  fda-grant-walkthrough <binary-path>           Full walkthrough (opens UI + copies path)
  fda-grant-walkthrough --check <binary-path>   Check grant state without opening UI

  Exit 0 = already granted; exit 3 = not granted (--check mode);
  exit 2 = binary missing or not executable.

EXAMPLES:
  # Grant FDA to maccy-backup-runner
  fda-grant-walkthrough ~/eon/iterm2-scripts/bin/maccy-backup/maccy-backup-runner

  # Just check whether something is granted (useful in scripts)
  if fda-grant-walkthrough --check /path/to/binary; then
      echo "ready to run"
  else
      echo "needs FDA grant"
  fi

NOTES:
  - macOS does not allow programmatic FDA grants. This script automates
    everything possible (opens the right Settings pane, copies the path
    to clipboard) but the final click + Touch ID is yours.
  - The `--check` mode reads /Library/Application Support/com.apple.TCC/TCC.db,
    which itself requires FDA. The first time you run it, FDA may not yet
    be granted to your shell — so --check can produce a false negative.
    The walkthrough mode is safe regardless.
USAGE_EOF
            exit 0
            ;;
        *)
            BIN_PATH="$1"; shift
            ;;
    esac
done

[ -z "$BIN_PATH" ] && { echo "fda-grant-walkthrough: error — binary path required (--help for usage)" >&2; exit 1; }
[ ! -e "$BIN_PATH" ] && { echo "fda-grant-walkthrough: error — does not exist: $BIN_PATH" >&2; exit 2; }
[ ! -x "$BIN_PATH" ] && { echo "fda-grant-walkthrough: error — not executable: $BIN_PATH" >&2; exit 2; }

# Resolve to absolute path (System Settings list uses absolute paths)
ABS_PATH=$(cd "$(dirname "$BIN_PATH")" && pwd)/$(basename "$BIN_PATH")

# Try to read TCC.db (requires FDA on the reader process; fail-soft if denied)
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
GRANTED=""
if [ -r "$TCC_DB" ]; then
    GRANTED=$(/usr/bin/sqlite3 "$TCC_DB" \
        "SELECT 1 FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND client='$ABS_PATH' AND auth_value=2 LIMIT 1;" 2>/dev/null || echo "")
fi

if [ -n "$GRANTED" ]; then
    echo "✓ Full Disk Access already granted: $ABS_PATH"
    exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    # In --check mode we can't open UI; just report and exit 3
    if [ -r "$TCC_DB" ]; then
        echo "✗ Full Disk Access NOT granted: $ABS_PATH" >&2
    else
        # Reader lacks FDA itself — can't authoritatively check
        echo "? Unable to verify (this shell lacks FDA to read TCC.db): $ABS_PATH" >&2
    fi
    exit 3
fi

# Walkthrough mode
echo "═══════════════════════════════════════════════════════════════════"
echo "  macOS Full Disk Access — grant walkthrough"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Target binary:"
echo "    $ABS_PATH"
echo ""

# Copy path to clipboard for easy paste-into-Finder
if command -v pbcopy >/dev/null 2>&1; then
    echo -n "$ABS_PATH" | /usr/bin/pbcopy
    echo "  ✓ Path copied to clipboard"
fi

echo ""
echo "  Opening System Settings → Privacy & Security → Full Disk Access..."
/usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null

echo ""
echo "  Manual steps (Settings is now open):"
echo "    1. Click the '+' button under the Full Disk Access list"
echo "    2. Press Cmd+Shift+G  (Go to folder)"
echo "    3. Cmd+V to paste the binary path"
echo "    4. Press Enter, then select the binary, click Open"
echo "    5. Toggle the new entry ON"
echo "    6. Authenticate with Touch ID / password if prompted"
echo ""
echo "  After grant, verify with:"
echo "    $0 --check '$ABS_PATH'"
echo ""
echo "  Then restart the launchd job (if applicable):"
echo "    launchctl kickstart -p gui/\$(id -u)/<service-label>"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
