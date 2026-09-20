#!/usr/bin/env bash
#
# Two closing items from the 2026-09-20 session that are unrelated to each other
# except in timing, and which need OPPOSITE privileges.
#
# USAGE
#   bash      finish-hardening.sh preview
#   sudo bash finish-hardening.sh firewall     # enable the application firewall
#   bash      finish-hardening.sh ghosts       # prune the Sequoia screen-capture store (NO sudo)
#
# 1. FIREWALL. If the macOS application firewall is off, every service bound to
#    *: is reachable from the local network and from any VPN/mesh interface —
#    including anything that holds Accessibility and Screen Recording. That is
#    LIVE surface, unlike a dormant permission row. Expect per-app allow prompts
#    afterwards; that is the firewall working. Verify reachability FROM ANOTHER
#    HOST: connecting to your own address routes over loopback and never
#    crosses the filter, so a self-test proves nothing.
#
# 2. GHOSTS. macOS Sequoia keeps a SECOND screen-capture store at
#    ~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist,
#    keyed by bundle identifier. tccutil cannot address it at any scope and it
#    has no System Settings UI, so nothing else will ever clean it. Entries
#    routinely accumulate for applications that no longer exist.
#    It is a user-owned plist, so this needs NO root — running it
#    under sudo would target root's container instead.

set -uo pipefail

# Resolve the console user's home explicitly: under sudo, $HOME is root's.
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null)"
[[ -n "$CONSOLE_USER" ]] || CONSOLE_USER="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -n "$USER_HOME" ]] || USER_HOME="$HOME"

SCA="$USER_HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"
BACKUP_DIR="$USER_HOME/.local/state/tcc-backups"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw

RED=$'\033[31m'; GRN=$'\033[32m'; BLD=$'\033[1m'; RST=$'\033[0m'
FAILED=0
hdr()  { printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
step() { printf '  %s\n' "$*"; }
ok()   { printf '  %sok%s     %s\n' "$GRN" "$RST" "$*"; }
# Defined late in review: an earlier revision CALLED warn() without defining it,
# so the one path that warns about replayd still running printed
# "warn: command not found" to stderr and no warning at all.
warn() { printf '  %swarn%s   %s\n' "$YEL" "$RST" "$*"; }
bad()  { printf '  %sFAIL%s   %s\n' "$RED" "$RST" "$*"; FAILED=1; }
die()  { printf '\n%sABORT%s  %s\n' "$RED" "$RST" "$*"; exit 2; }

resolve() {   # bundle id -> path or NOT_INSTALLED
  local c="$1" jxa
  # shellcheck disable=SC2016  # $.NSWorkspace is JavaScript, not shell
  jxa='ObjC.import("AppKit"); var u=$.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier($("'"$c"'")); u.isNil()?"NOT_INSTALLED":ObjC.unwrap(u.path)'
  /usr/bin/osascript -l JavaScript -e "$jxa" 2>/dev/null
}

MODE="${1:-}"
case "$MODE" in preview|firewall|ghosts) ;; *) die "mode required: preview | firewall | ghosts" ;; esac
case "$MODE" in
  firewall) [[ "${EUID}" -eq 0 ]] || die "'firewall' needs sudo" ;;
  ghosts)   [[ "${EUID}" -ne 0 ]] || die "'ghosts' must NOT run under sudo — it would target root's container, not yours" ;;
esac

# --------------------------------------------------------------------------
if [[ "$MODE" == "preview" || "$MODE" == "firewall" ]]; then
  hdr "Application firewall"
  step "current: $("$FW" --getglobalstate 2>&1)"
  step "stealth: $("$FW" --getstealthmode 2>&1)"
  step "listeners currently bound to ALL interfaces:"
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null |
    awk '$9 ~ /^\*:/ && !seen[$1$9]++ {printf "    %-12s %s\n", $1, $9}'
  if [[ "$MODE" == "firewall" ]]; then
    # if/then/else, not `A && B || C`: with the && || form, C also runs when A
    # succeeded but B returned non-zero — so a success can print a failure.
    rc=0; "$FW" --setglobalstate on >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then ok "firewall enabled"; else bad "could not enable firewall (rc=$rc)"; fi
    rc=0; "$FW" --setstealthmode on >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then ok "stealth mode enabled (stops replying to probes)"; else bad "could not enable stealth mode (rc=$rc)"; fi
    step "verify: $("$FW" --getglobalstate 2>&1) / $("$FW" --getstealthmode 2>&1)"
    step "NOTE: signed apps are auto-allowed by default, so most of the listeners"
    step "above keep working. Review them in System Settings > Network > Firewall."
  else
    step "(preview: would run --setglobalstate on and --setstealthmode on)"
  fi
fi

# --------------------------------------------------------------------------
if [[ "$MODE" == "preview" || "$MODE" == "ghosts" ]]; then
  hdr "Sequoia screen-capture approvals store"
  if [[ ! -e "$SCA" ]]; then
    step "not present: $SCA"
  else
    # Keyed by BUNDLE IDENTIFIER. An earlier attempt grepped for quoted PATHS
    # and reported zero entries on a file that has 22.
    ids="$(plutil -p "$SCA" 2>/dev/null | awk -F'"' '/^  "/ {print $2}')"
    total=0; ghosts=()
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      total=$((total+1))
      [[ "$(resolve "$c")" == "NOT_INSTALLED" ]] && ghosts+=("$c")
    done <<< "$ids"
    step "entries: $total    ghosts: ${#ghosts[@]}"
    for g in ${ghosts[@]+"${ghosts[@]}"}; do step "  ghost: $g"; done

    if [[ "$MODE" == "ghosts" && ${#ghosts[@]} -gt 0 ]]; then
      # This mode runs as the console user, but BACKUP_DIR may already exist
      # root:wheel 0700 because a sudo script created it first — in which case a
      # write here fails with "Permission denied" (measured 2026-09-20). Pick a
      # directory this uid can actually write rather than assuming.
      if [[ -d "$BACKUP_DIR" && ! -w "$BACKUP_DIR" ]]; then
        BACKUP_DIR="$USER_HOME/.local/state/tcc-backups-user"
        step "shared backup dir is not writable by this user; using $BACKUP_DIR"
      fi
      mkdir -p "$BACKUP_DIR" || die "cannot create $BACKUP_DIR"
      chmod 700 "$BACKUP_DIR"
      dest="$BACKUP_DIR/ScreenCaptureApprovals.plist.$(date +%Y%m%d-%H%M%S)"
      cp "$SCA" "$dest" || die "backup failed — refusing to edit without one"
      chmod 600 "$dest"
      ok "backed up to $dest"

      # 🔴 replayd OWNS this file and holds it in memory. MEASURED 2026-09-20:
      # a PlistBuddy edit verified clean, and replayd later flushed its
      # cached dictionary over the file ~8 minutes later, restoring every
      # deleted entry. Editing underneath a live daemon does not work;
      # the daemon wins, minutes later, silently.
      # Stop it first. launchd restarts it on demand and it re-reads from disk.
      if pgrep -x replayd >/dev/null 2>&1; then
        killall replayd 2>/dev/null || true
        sleep 2
        if pgrep -x replayd >/dev/null 2>&1; then
          warn "replayd is still running; the edit may be overwritten again"
        else
          ok "stopped replayd (launchd will restart it on demand)"
        fi
      fi
      for g in "${ghosts[@]}"; do
        rc=0
        /usr/libexec/PlistBuddy -c "Delete :$g" "$SCA" >/dev/null 2>&1 || rc=$?
        if [[ $rc -eq 0 ]]; then ok "removed $g"; else bad "could not remove $g (rc=$rc)"; fi
      done
      after="$(plutil -p "$SCA" 2>/dev/null | awk -F'"' '/^  "/ {print $2}' | wc -l | tr -d ' ')"
      step "entries remaining: $after (was $total)"
      if [[ "$after" -eq $(( total - ${#ghosts[@]} )) ]]; then
        ok "exactly the ghosts were removed — no collateral"
      else
        bad "unexpected entry count after edit"
      fi
      step "restore with: cp '$dest' '$SCA'"

      # An immediate read proves only that the write landed in the file — not
      # that it survives. Wait, then re-read, before claiming success.
      step "waiting to see whether the edit SURVIVES a daemon flush..."
      sleep 20
      settled="$(plutil -p "$SCA" 2>/dev/null | awk -F'"' '/^  "/ {print $2}' | wc -l | tr -d ' ')"
      if [[ "$settled" -eq "$after" ]]; then
        ok "still $settled entries after settling — the change held"
      else
        bad "entry count went $after -> $settled: a daemon rewrote the file"
        step "replayd restarted and restored its cached copy. Re-run, or accept"
        step "that these entries are not removable while the daemon is alive."
      fi
    fi
  fi
fi

hdr "Result"
if [[ $FAILED -eq 0 ]]; then printf '  %sall steps succeeded%s\n' "$GRN" "$RST"
else printf '  %sone or more steps FAILED%s\n' "$RED" "$RST"; fi
exit $(( FAILED == 0 ? 0 : 1 ))
