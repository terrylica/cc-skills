#!/usr/bin/env bash
#
# Enumerate everything that persists on a Mac. READ-ONLY.
#
# WHY ENUMERATE INSTEAD OF SEARCH. Hunting persistence by product name
# (`grep -i <vendor>`) answers "is X here?" and can never answer "what is
# here?". A real cleanup that grepped for five remote-access product names
# missed a root LaunchDaemon that was running the entire time, simply because
# nobody thought to type its name. Every section below lists what exists.
#
# It also covers the mechanisms that are easiest to get wrong:
#   - launchd Label vs FILENAME. launchctl addresses a job by the Label INSIDE
#     the plist. A vendor plist named com.vendor.vendor_service.plist can carry
#     Label com.vendor.service, so `launchctl bootout system/<filename>` returns
#     ESRCH, prints "not loaded", and you then delete a root binary out from
#     under a live KeepAlive job. This script prints BOTH and flags mismatches.
#   - Audio HAL plug-ins load into coreaudiod and appear in NO launchd listing.
#   - SecurityAgentPlugins wire into the login authorization chain; a bad edit
#     there locks you out of the machine.
#
# USAGE
#   bash persistence-inventory.sh          # everything readable as you
#   sudo bash persistence-inventory.sh     # adds the root-only sections

set -uo pipefail

YEL=$'\033[33m'; BLD=$'\033[1m'; DIM=$'\033[2m'; RST=$'\033[0m'

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null)"
[[ -n "$CONSOLE_USER" ]] || CONSOLE_USER="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -n "$USER_HOME" ]] || USER_HOME="$HOME"

sec()  { printf '\n%s== %s ==%s\n' "$BLD" "$1" "$RST"; }
note() { printf '%s   %s%s\n' "$DIM" "$1" "$RST"; }

sec "1. launchd — daemons and agents (Label vs filename)"
note "Label is what launchctl addresses. A filename that differs is the trap."
for d in /Library/LaunchDaemons /Library/LaunchAgents "$USER_HOME/Library/LaunchAgents"; do
  [[ -d "$d" ]] || continue
  printf '  %s\n' "$d"
  shopt -s nullglob
  for f in "$d"/*.plist; do
    base="$(basename "$f" .plist)"
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$f" 2>/dev/null)" || label=""
    prog="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$f" 2>/dev/null)" || prog=""
    [[ -n "$prog" ]] || prog="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$f" 2>/dev/null)" || prog=""
    ka="$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$f" 2>/dev/null)" || ka=""
    flags=""; [[ -n "$ka" ]] && flags="KeepAlive "
    mismatch=""; [[ -n "$label" && "$label" != "$base" ]] && mismatch="${YEL}LABEL!=FILENAME${RST} "
    missing="";  [[ -n "$prog" && ! -e "$prog" ]] && missing="${YEL}PROGRAM MISSING${RST} "
    printf '    %-48s label=%-38s %s%s%s\n' "$base" "$label" "$mismatch" "$missing" "$flags"
  done
  shopt -u nullglob
done

sec "2. Background Task Management (login items + legacy daemons)"
note "sfltool dumpbtm — the modern registry; nothing else shows these."
if out="$(sfltool dumpbtm 2>&1)"; then
  printf '  records: %s\n' "$(grep -c '^ #' <<< "$out")"
  awk '
    /^ *Name: /            { n=$0; sub(/^ *Name: /,"",n) }
    /^ *Developer Name: /  { d=$0; sub(/^ *Developer Name: /,"",d) }
    /^ *Executable Path: / { e=$0; sub(/^ *Executable Path: /,"",e)
                             if (e != "") printf "    %-26s %-24s %s\n", substr(n,1,26), substr(d,1,24), e }
  ' <<< "$out"
else
  printf '  %s\n' "$out"
fi

sec "3. System extensions"
systemextensionsctl list 2>&1 | sed 's/^/  /'

sec "4. Audio HAL plug-ins (load into coreaudiod, invisible to launchd)"
for d in /Library/Audio/Plug-Ins/HAL "$USER_HOME/Library/Audio/Plug-Ins/HAL"; do
  [[ -d "$d" ]] || continue
  printf '  %s\n' "$d"
  shopt -s nullglob
  found=0
  for p in "$d"/*; do
    team="$(codesign -dv --verbose=2 "$p" 2>&1 | awk -F'=' '/^TeamIdentifier=/{print $2; exit}')"
    printf '    %-40s %s\n' "$(basename "$p")" "$team"
    found=1
  done
  [[ $found -eq 0 ]] && printf '    (empty)\n'
  shopt -u nullglob
done

sec "5. SecurityAgentPlugins + the login authorization chain"
note "A bad edit here can lock you out. Keep a terminal open and an SSH route ready."
if [[ -d /Library/Security/SecurityAgentPlugins ]]; then
  shopt -s nullglob
  found=0
  for p in /Library/Security/SecurityAgentPlugins/*; do printf '  plugin: %s\n' "$(basename "$p")"; found=1; done
  [[ $found -eq 0 ]] && printf '  no third-party SecurityAgentPlugins\n'
  shopt -u nullglob
fi
chain="$(security authorizationdb read system.login.console 2>/dev/null)"
if [[ -n "$chain" ]]; then
  printf '  system.login.console mechanisms:\n'
  awk '/<array>/{a=1;next} /<\/array>/{a=0} a' <<< "$chain" | sed -E 's/.*<string>(.*)<\/string>.*/    \1/'
else
  printf '  could not read system.login.console\n'
fi

sec "6. Privileged helper tools (SMJobBless)"
if [[ -d /Library/PrivilegedHelperTools ]]; then
  shopt -s nullglob
  found=0
  for p in /Library/PrivilegedHelperTools/*; do printf '  %s\n' "$(basename "$p")"; found=1; done
  [[ $found -eq 0 ]] && printf '  (empty)\n'
  shopt -u nullglob
else
  printf '  directory does not exist\n'
fi

sec "7. Configuration profiles"
profiles list 2>&1 | sed 's/^/  /'

sec "8. Third-party kernel extensions"
note "Anything NOT com.apple.* is third-party code running in the kernel."
kext_out="$(kmutil showloaded 2>&1)"
case "$kext_out" in
  *Error*|*"not permitted"*|*superuser*) printf '  %s\n' "$kext_out" ;;
  *) awk '!/com\.apple\./ && NF>2 && ++n<=20 {print "  "$0}' <<< "$kext_out" ;;
esac

sec "9. Login/logout hooks and cron"
for k in LoginHook LogoutHook; do
  v="$(defaults read com.apple.loginwindow "$k" 2>/dev/null)" || v=""
  if [[ -n "$v" ]]; then printf '  %s: %s\n' "$k" "$v"; else printf '  %s: not set\n' "$k"; fi
done
ct="$(crontab -l 2>/dev/null)" || ct=""
if [[ -n "$ct" ]]; then printf '  crontab:\n%s\n' "$ct"; else printf '  crontab: empty\n'; fi

sec "10. Listening sockets — the live remote-access surface"
note "A '*:' bind accepts connections from ANY interface, not just loopback."
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null |
  awk '(NR==1 || !seen[$1$9]++) && ++n<=30 {printf "  %-14s %-10s %s\n", $1, $3, $9}'

sec "11. Application firewall"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
"$FW" --getglobalstate 2>&1 | sed 's/^/  /'
"$FW" --getstealthmode 2>&1 | sed 's/^/  /'
note "If the firewall is disabled, every '*:' bind above is reachable from the LAN."
