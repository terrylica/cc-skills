# shellcheck shell=bash
# orca-cli.sh — find the Orca IDE's CLI. Sourced (never run) by the orca-tools scripts; bash 3.2 compatible.
#
# Order: $ORCA_CLI (an explicit choice: an error if it is not Orca's), $ORCA_CLI_BIN_DIR/orca (Orca exports it into its
# own terminals), `orca` on PATH if it is the IDE's, `orca-ide` (the CLI's name on Linux, measured on Orca 1.4.224:
# /opt/Orca/resources/bin/orca-ide, symlinked as ~/.local/bin/orca-ide), then the IDE's own shim locations. On Linux
# desktops /usr/bin/orca is often the GNOME screen reader, so a bare `orca` is never trusted. The help text is captured with a time cap, never
# piped to `grep -q`: under pipefail an early-exiting reader can SIGPIPE the producer and invert the test.

orca_cli_help() {  # the CLI's --help, capped at 10 s so a hung binary cannot hang the caller
  python3 -c 'import subprocess, sys
try:
    r = subprocess.run(sys.argv[1:], capture_output=True, text=True, timeout=10)
    sys.stdout.write(r.stdout)
except Exception:
    pass' "$1" --help 2>/dev/null || true
}

is_orca() {
  local h
  [ -n "$1" ] && [ -x "$1" ] || return 1
  h=$(orca_cli_help "$1")
  case $h in *"worktree create"*"terminal create"*) return 0 ;; *) return 1 ;; esac
}

find_orca() {
  local c
  if [ -n "${ORCA_CLI:-}" ]; then is_orca "$ORCA_CLI" && { echo "$ORCA_CLI"; return 0; }; return 1; fi
  for c in "${ORCA_CLI_BIN_DIR:+$ORCA_CLI_BIN_DIR/orca}" "${ORCA_CLI_BIN_DIR:+$ORCA_CLI_BIN_DIR/orca-ide}" \
           "$(command -v orca 2>/dev/null || true)" "$(command -v orca-ide 2>/dev/null || true)" \
           "$HOME/.local/bin/orca-ide" /opt/Orca/resources/bin/orca-ide \
           "$HOME/.config/orca/linux-orca-cli-shim/orca" /Applications/Orca.app/Contents/Resources/bin/orca \
           "$HOME/Applications/Orca.app/Contents/Resources/bin/orca"; do
    is_orca "$c" && { echo "$c"; return 0; }
  done
  return 1
}
