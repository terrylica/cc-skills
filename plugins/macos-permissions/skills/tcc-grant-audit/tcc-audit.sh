#!/usr/bin/env bash
#
# Audit macOS TCC (Transparency, Consent and Control) privacy grants.
#
# READ-ONLY. Changes nothing, ever. Run this before any cleanup.
#
# Covers all THREE permission stores, because System Settings shows you a
# fraction of one of them:
#   1. system  /Library/Application Support/com.apple.TCC/TCC.db
#   2. user    ~/Library/Application Support/com.apple.TCC/TCC.db
#   3. Sequoia ~/Library/Group Containers/group.com.apple.replayd/
#              ScreenCaptureApprovals.plist   (no CLI, no UI, tccutil cannot
#              address it at any scope)
#
# Requires Full Disk Access on the calling terminal to read the databases.

set -uo pipefail

RED=$'\033[31m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'

# Works correctly under sudo, where $HOME is root's.
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null)"
[[ -n "$CONSOLE_USER" ]] || CONSOLE_USER="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -n "$USER_HOME" ]] || USER_HOME="$HOME"

SYS_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
USR_TCC="$USER_HOME/Library/Application Support/com.apple.TCC/TCC.db"
SCA="$USER_HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"

CACHE="$(mktemp)"; trap 'rm -f "$CACHE"' EXIT

hdr()  { printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
step() { printf '  %s\n' "$*"; }

usage() {
  cat <<'USAGE'
usage: tcc-audit.sh [orphans|live|fda|sequoia|all]

  orphans  grants whose application no longer exists, per store  (default)
  live     grants backed by a real app: signer, Team ID, running, granted-when
  fda      Full Disk Access holders only — the most powerful grant
  sequoia  the Sequoia screen-capture store tccutil cannot reach
  all      every section
USAGE
}

# ---------------------------------------------------------------------------
# Resolve a bundle identifier to an installed path, via the API LaunchServices
# itself exposes. Replaces hand-built Info.plist scans (which miss helper
# bundles outside /Applications), lsregister -dump parsing (whose records go
# stale), and mdfind (which returns false negatives).
#
# 🔴 ONE BLIND SPOT: it cannot resolve non-app bundles, so every com.apple.*
# XPC service reports NOT_INSTALLED and looks orphaned. Callers MUST exclude
# com.apple.* before acting. Clearing those can break iCloud, Reminders,
# Passwords or Find My.
# ---------------------------------------------------------------------------
resolve() {
  local c="$1" hit jxa
  hit="$(awk -F'\t' -v id="$c" '$1==id {print $2; exit}' "$CACHE" 2>/dev/null)"
  [[ -n "$hit" ]] && { printf '%s' "$hit"; return; }
  # shellcheck disable=SC2016  # $.NSWorkspace is JavaScript, not shell
  jxa='ObjC.import("AppKit"); var u=$.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier($("'"$c"'")); u.isNil()?"NOT_INSTALLED":ObjC.unwrap(u.path)'
  hit="$(/usr/bin/osascript -l JavaScript -e "$jxa" 2>/dev/null)"
  [[ -n "$hit" ]] || hit="NOT_INSTALLED"
  printf '%s\t%s\n' "$c" "$hit" >> "$CACHE"
  printf '%s' "$hit"
}

installed() {   # $1 = client, $2 = client_type -> 0 installed, 1 gone
  if [[ "$2" == "1" ]]; then [[ -e "$1" ]]; return; fi
  [[ "$(resolve "$1")" != "NOT_INSTALLED" ]]
}

check_readable() {
  if [[ ! -r "$SYS_TCC" ]]; then
    printf '%sCannot read %s%s\n' "$RED" "$SYS_TCC" "$RST"
    printf 'Grant Full Disk Access to this terminal in System Settings > Privacy & Security.\n'
    exit 2
  fi
}

# ---------------------------------------------------------------------------
section_orphans() {
  local db label apple=0 live=0 dead=0
  for pair in "SYSTEM|$SYS_TCC" "USER|$USR_TCC"; do
    label="${pair%%|*}"; db="${pair#*|}"
    hdr "$label store — granted rows whose app is GONE"
    [[ -r "$db" ]] || { step "cannot read $db"; continue; }
    apple=0; live=0; dead=0
    while IFS='|' read -r svc client ctype; do
      [[ -n "$client" ]] || continue
      case "$client" in com.apple.*) apple=$((apple+1)); continue ;; esac
      if installed "$client" "$ctype"; then live=$((live+1)); continue; fi
      dead=$((dead+1))
      printf '  %-40s %s\n' "${svc#kTCCService}" "$client"
    done < <(sqlite3 -readonly "$db" \
        "SELECT service, client, client_type FROM access WHERE auth_value=2 ORDER BY service, client;" 2>/dev/null)
    step "--- orphaned: $dead   live: $live   com.apple.* skipped: $apple"
  done
}

# ---------------------------------------------------------------------------
section_live() {
  local db label
  for pair in "SYSTEM|$SYS_TCC" "USER|$USR_TCC"; do
    label="${pair%%|*}"; db="${pair#*|}"
    hdr "$label store — LIVE grants (this is where real attack surface is)"
    [[ -r "$db" ]] || { step "cannot read $db"; continue; }
    printf '  %-28s %-34s %-9s %s\n' SERVICE CLIENT RUNNING GRANTED
    while IFS='|' read -r svc client ctype ts; do
      [[ -n "$client" ]] || continue
      case "$client" in com.apple.*) continue ;; esac
      installed "$client" "$ctype" || continue
      local path running
      if [[ "$ctype" == "1" ]]; then path="$client"; else path="$(resolve "$client")"; fi
      if pgrep -f "^${path}/Contents/MacOS/" >/dev/null 2>&1 || pgrep -xf "$path" >/dev/null 2>&1; then
        running="RUNNING"
      else
        running="-"
      fi
      printf '  %-28s %-34s %-9s %s\n' "${svc#kTCCService}" "$(basename "$client")" "$running" "$ts"
    done < <(sqlite3 -readonly "$db" \
        "SELECT service, client, client_type, datetime(last_modified,'unixepoch','localtime')
           FROM access WHERE auth_value=2 ORDER BY last_modified DESC;" 2>/dev/null)
  done
  hdr "Decode a grant's code requirement (csreq) — what it actually pins"
  step "csreq pins the SIGNING IDENTITY, not the bundle name, so a renamed"
  step "binary inherits NOTHING from an orphaned row. Verify it yourself:"
  step ""
  step "  sqlite3 \"\$SYS_TCC\" \"SELECT hex(csreq) FROM access WHERE client='<id>' LIMIT 1;\" \\"
  step "    | xxd -r -p | /usr/bin/csreq -r- -t"
}

# ---------------------------------------------------------------------------
section_fda() {
  hdr "Full Disk Access holders — the most powerful grant in TCC"
  while IFS='|' read -r client ctype; do
    [[ -n "$client" ]] || continue
    if installed "$client" "$ctype"; then
      printf '  present   %s\n' "$client"
    else
      printf '  %sORPHANED%s  %s\n' "$RED" "$RST" "$client"
    fi
  done < <(sqlite3 -readonly "$SYS_TCC" \
      "SELECT client, client_type FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2 ORDER BY client;" 2>/dev/null)
}

# ---------------------------------------------------------------------------
section_sequoia() {
  hdr "Sequoia screen-capture store (tccutil cannot address this)"
  if [[ ! -e "$SCA" ]]; then step "not present (pre-Sequoia, or never used)"; return; fi
  step "file: $SCA"
  # Keyed by BUNDLE IDENTIFIER, not by path. Grepping for quoted paths finds
  # nothing and looks like an empty file.
  local total=0 ghosts=0
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    total=$((total+1))
    if [[ "$(resolve "$c")" == "NOT_INSTALLED" ]]; then
      printf '  %sGHOST%s  %s\n' "$RED" "$RST" "$c"; ghosts=$((ghosts+1))
    fi
  done < <(plutil -p "$SCA" 2>/dev/null | awk -F'"' '/^  "/ {print $2}')
  step "--- $ghosts ghost(s) of $total entries"
}

# ---------------------------------------------------------------------------
section_leftovers() {
  hdr "Disabled-job registry (no uninstaller clears this)"
  step "labels remembered by launchd; inert without a matching plist"
  /bin/launchctl print-disabled "user/$(id -u "$CONSOLE_USER")" 2>/dev/null |
    awk -F'"' '/=>/ {print "    " $2}' | sort | awk 'NR<=40'
}

check_readable
case "${1:-orphans}" in
  orphans) section_orphans ;;
  live)    section_live ;;
  fda)     section_fda ;;
  sequoia) section_sequoia ;;
  all)     section_orphans; section_fda; section_sequoia; section_live; section_leftovers ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac

hdr "Reminder"
step "${YEL}Nothing above was changed.${RST} To clear orphans: tcc-clear-orphans.sh preview"
step "Verify any change against the DATABASE, never a tool's exit code —"
step "tccutil prints \"Successfully reset\" and exits 0 having deleted nothing."
