#!/usr/bin/env bash
#
# Clear TCC grants belonging to applications that no longer exist, without
# touching the grants of applications that do.
#
# THE PROBLEM THIS SOLVES
# `tccutil reset <Service> <bundleid>` resolves the identifier through
# LaunchServices BEFORE it touches the database. Once the app is deleted the
# identifier no longer resolves, so every call fails with
#   -10814 kLSApplicationNotFoundErr   (exit 64)
# and the grant is stranded forever — macOS never garbage-collects these rows,
# and System Settings HIDES them (the row is not rendered precisely because the
# bundle will not resolve, so there is no "select it and press −" path either).
# The only Apple-native alternative is a service-wide `tccutil reset <Service>`,
# which also destroys every legitimate grant in that service.
#
# THE MECHANISM
# Stage one throwaway .app carrying the orphaned identifier, let LaunchServices
# register it, run `tccutil reset All <id>`, then unregister and delete it.
#
# 🔴 THE STUB MUST LIVE IN /Applications. Measured, with the other variables held
# constant: a stub in /private/tmp IS registered (it appears in `lsregister
# -dump`) and tccutil STILL returns -10814 — whether its executable is a 0-byte
# file, a real Mach-O, or ad-hoc signed. tccutil does not read the registration
# database; it calls an application-lookup API that only returns bundles from
# standard application directories. Moving the identical bundle to /Applications
# makes the same call succeed. Do not "simplify" this to a temp directory.
#
# USAGE
#   bash      tcc-clear-orphans.sh preview [user|system]
#   bash      tcc-clear-orphans.sh user       # user DB    — must NOT be sudo
#   sudo bash tcc-clear-orphans.sh system     # system DB  — must be sudo
#
# 🔴 TWO MODES, OPPOSITE PRIVILEGES. Accessibility / ScreenCapture /
# SystemPolicyAllFiles / ListenEvent / PostEvent live in the SYSTEM database
# (root). Camera / Microphone / AppleEvents / folder access live in the CONSOLE
# USER's database. Running either under the wrong uid reports success and
# changes nothing observable, so the script refuses.
#
# NEVER TOUCHED
#   - com.apple.*  : Apple's own XPC services. They are not apps, so the
#     resolver cannot find them and they LOOK orphaned. Clearing them can break
#     iCloud, Reminders, Passwords or Find My.
#   - client_type=1 (absolute path) rows: tccutil takes identifiers only.
#     Reported at the end, never silently dropped.
#   - anything that still resolves to a real bundle on disk.

set -uo pipefail

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null)"
[[ -n "$CONSOLE_USER" ]] || CONSOLE_USER="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -n "$USER_HOME" ]] || USER_HOME="$HOME"

SYS_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
USR_TCC="$USER_HOME/Library/Application Support/com.apple.TCC/TCC.db"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
STUB_APP="/Applications/tcc-cleanup-stub.app"
STUB_MADE=0

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
FAILED=0
CACHE="$(mktemp)"

hdr()  { printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
step() { printf '  %s\n' "$*"; }
ok()   { printf '  %sok%s     %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %swarn%s   %s\n' "$YEL" "$RST" "$*"; }
bad()  { printf '  %sFAIL%s   %s\n' "$RED" "$RST" "$*"; FAILED=1; }
die()  { printf '\n%sABORT%s  %s\n' "$RED" "$RST" "$*"; exit 2; }

# shellcheck disable=SC2329  # invoked indirectly by the EXIT trap
cleanup() {
  rm -f "$CACHE"
  if [[ "$STUB_MADE" -eq 1 && -d "$STUB_APP" ]]; then
    "$LSREGISTER" -u "$STUB_APP" >/dev/null 2>&1 || true
    case "$STUB_APP" in
      /Applications/tcc-cleanup-stub.app) rm -rf "$STUB_APP" ;;
      *) printf 'refusing to remove unexpected stub path: %s\n' "$STUB_APP" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

MODE="${1:-}"
case "$MODE" in preview|user|system) ;; *) die "mode required: preview [user|system] | user | system" ;; esac
case "$MODE" in
  user)   [[ "${EUID}" -ne 0 ]] || die "'user' must NOT run under sudo — it would target root's TCC database" ;;
  system) [[ "${EUID}" -eq 0 ]] || die "'system' edits the system TCC database — re-run with sudo" ;;
esac

TARGET="$MODE"
if [[ "$MODE" == "preview" ]]; then
  TARGET="${2:-user}"
  case "$TARGET" in user|system) ;; *) die "preview target must be 'user' or 'system'" ;; esac
fi
DB="$USR_TCC"; DBNAME="USER"
[[ "$TARGET" == "system" ]] && { DB="$SYS_TCC"; DBNAME="SYSTEM"; }
[[ -r "$DB" ]] || die "cannot read $DB — this terminal needs Full Disk Access"

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
rows_for() { sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM access WHERE auth_value=2 AND client='$1';" 2>/dev/null; }

hdr "Scanning the $DBNAME database"
ORPHANS=(); PATHS=(); APPLE=0; LIVE=0
while IFS='|' read -r client ctype; do
  [[ -n "$client" ]] || continue
  if [[ "$ctype" == "1" ]]; then
    [[ -e "$client" ]] || PATHS+=("$client")
    continue
  fi
  case "$client" in com.apple.*) APPLE=$((APPLE+1)); continue ;; esac
  if [[ "$(resolve "$client")" == "NOT_INSTALLED" ]]; then ORPHANS+=("$client"); else LIVE=$((LIVE+1)); fi
done < <(sqlite3 -readonly "$DB" "SELECT DISTINCT client, client_type FROM access WHERE auth_value=2;" 2>/dev/null)

step "identifiers still installed (untouched):        $LIVE"
step "com.apple.* internals (deliberately untouched): $APPLE"
step "absolute-path rows tccutil cannot address:      ${#PATHS[@]}"
step "ORPHANED third-party identifiers:               ${#ORPHANS[@]}"

if [[ "$MODE" == "preview" ]]; then
  hdr "Would clear"
  for c in ${ORPHANS[@]+"${ORPHANS[@]}"}; do printf '    %-52s %s row(s)\n' "$c" "$(rows_for "$c")"; done
  hdr "Absolute-path rows (not addressable by tccutil)"
  for p in ${PATHS[@]+"${PATHS[@]}"}; do printf '    %s\n' "$p"; done
  exit 0
fi

if [[ ${#ORPHANS[@]} -gt 0 ]]; then
  hdr "Clearing"
  [[ -e "$STUB_APP" ]] && die "$STUB_APP already exists — remove it and re-run"
  mkdir -p "$STUB_APP/Contents/MacOS" || die "cannot create $STUB_APP"
  STUB_MADE=1
  cp /bin/echo "$STUB_APP/Contents/MacOS/stub"
  chmod 755 "$STUB_APP/Contents/MacOS/stub"

  for c in "${ORPHANS[@]}"; do
    before="$(rows_for "$c")"; [[ -n "$before" ]] || before=0
    [[ "$before" == "0" ]] && continue
    cat > "$STUB_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$c</string>
  <key>CFBundleExecutable</key><string>stub</string>
  <key>CFBundleName</key><string>tcc-cleanup-stub</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST
    codesign --force --sign - "$STUB_APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -f "$STUB_APP" >/dev/null 2>&1 || true
    sleep 1
    out=""; rc=0
    out="$(/usr/bin/tccutil reset All "$c" 2>&1)" || rc=$?
    after="$(rows_for "$c")"; [[ -n "$after" ]] || after=1
    # Verify against the DATABASE. tccutil prints "Successfully reset" and exits
    # 0 even when it deleted nothing — its status is not evidence.
    if [[ "$after" == "0" ]]; then
      ok "cleared $c ($before row(s))"
    else
      warn "$c: $before -> $after row(s) (tccutil rc=$rc)"
      [[ -n "$out" ]] && printf '           said: %s\n' "$out"
    fi
    "$LSREGISTER" -u "$STUB_APP" >/dev/null 2>&1 || true
  done

  "$LSREGISTER" -u "$STUB_APP" >/dev/null 2>&1 || true
  rm -rf "$STUB_APP"; STUB_MADE=0
  if [[ -e "$STUB_APP" ]]; then bad "stub not removed: $STUB_APP"; else ok "stub removed"; fi
fi

hdr "Verify"
left=0
for c in ${ORPHANS[@]+"${ORPHANS[@]}"}; do
  n="$(rows_for "$c")"
  [[ "${n:-0}" != "0" ]] && { bad "still granted: $c ($n row(s))"; left=$((left+1)); }
done
[[ $left -eq 0 ]] && ok "every orphaned identifier cleared from the $DBNAME database"
tot="$(sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM access WHERE auth_value=2;" 2>/dev/null)"
[[ -n "$tot" ]] && step "granted rows remaining in the $DBNAME database: $tot"

if [[ ${#PATHS[@]} -gt 0 ]]; then
  hdr "Not addressable by tccutil"
  for p in "${PATHS[@]}"; do printf '    %s\n' "$p"; done
  step "These need a direct TCC.db writer (e.g. jacobsalmela/tccutil, GPL-2.0)."
  step "MEASURED: such writes SUCCEED against the USER database with SIP on, and"
  step "are REFUSED by the SYSTEM database (\"you probably need to disable SIP\")"
  step "— and the tool still exits 0, so verify against the database."
fi

hdr "Result"
if [[ $FAILED -eq 0 ]]; then printf '  %sall steps succeeded%s\n' "$GRN" "$RST"
else printf '  %sone or more steps FAILED%s\n' "$RED" "$RST"; fi
exit $(( FAILED == 0 ? 0 : 1 ))
