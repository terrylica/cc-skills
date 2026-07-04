#!/usr/bin/env bash
# macos-font-defaults — point macOS's "user fixed-pitch font" and the per-app
# fixed-width fonts (TextEdit plain text, Stickies default note) at a chosen font.
# Idempotent: re-running changes nothing if values already match.
#
# Why this exists: macOS has NO single system-wide "monospaced font" setting. The
# closest knob is the global NSFixedPitchFont default, which drives
# +[NSFont userFixedPitchFontOfSize:] (used by TextEdit plain text and other
# standard-text-system apps). Terminal/iTerm/VS Code keep their OWN font settings
# and are untouched. Stickies stores its default note font as an archived NSFont in
# its sandbox container plist. Apple Notes hardcodes its mono face and CANNOT be
# redirected (documented limitation) — its per-note "Monostyled" is the only lever.
#
# Usage:
#   apply.sh check                              # report current values, no changes
#   apply.sh apply [--font NAME] [--size N]     # apply (default: JetBrains Mono NL)
#
# Default font is the JetBrains Mono NL Nerd Font regular PostScript name.
set -euo pipefail

FONT="JetBrainsMonoNLNF-Regular"
SIZE=""   # empty => leave the macOS default size (~11pt) untouched

cmd="${1:-check}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --font) FONT="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

STICKIES_PLIST="$HOME/Library/Containers/com.apple.Stickies/Data/Library/Preferences/com.apple.Stickies.plist"

font_installed() {
  swift -e "import AppKit; exit(NSFont(name: \"$1\", size: 12) == nil ? 1 : 0)" >/dev/null 2>&1
}

stickies_default_font() {
  swift -e "
import AppKit
let path = \"$STICKIES_PLIST\"
guard let d = NSDictionary(contentsOfFile: path), let fd = d[\"DefaultFont\"] as? Data,
      let f = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: fd)
else { print(\"none\"); exit(0) }
print(f.fontName)
" 2>/dev/null || echo "none"
}

report() {
  local ufp
  ufp="$(swift -e 'import AppKit; let f=NSFont.userFixedPitchFont(ofSize:0); print((f?.fontName ?? "nil") + " " + String(format: "%.0f", f?.pointSize ?? 0))' 2>/dev/null)"
  echo "user fixed-pitch font : $ufp"
  echo "global NSFixedPitchFont: $(defaults read -g NSFixedPitchFont 2>/dev/null || echo unset) (size: $(defaults read -g NSFixedPitchFontSize 2>/dev/null || echo 'system default'))"
  echo "TextEdit NSFixedPitchFont: $(defaults read com.apple.TextEdit NSFixedPitchFont 2>/dev/null || echo unset)"
  echo "Stickies default note font: $(stickies_default_font)"
}

case "$cmd" in
  check)
    report
    ;;
  apply)
    font_installed "$FONT" || { echo "ERROR: font '$FONT' is not installed" >&2; exit 1; }

    # 1) Global user fixed-pitch font (family). Size left at macOS default unless --size.
    defaults write -g NSFixedPitchFont -string "$FONT"
    if [ -n "$SIZE" ]; then
      defaults write -g NSFixedPitchFontSize -int "$SIZE"
    else
      defaults delete -g NSFixedPitchFontSize >/dev/null 2>&1 || true
    fi

    # 2) TextEdit plain-text font (belt-and-suspenders; doesn't rely solely on global).
    defaults write com.apple.TextEdit NSFixedPitchFont -string "$FONT"
    if [ -n "$SIZE" ]; then
      defaults write com.apple.TextEdit NSFixedPitchFontSize -int "$SIZE"
    fi

    # 3) Stickies default note font (archived NSFont in the sandbox container plist).
    #    Only touch it when it differs, so a running Stickies need not be quit.
    local_cur="$(stickies_default_font)"
    if [ "$local_cur" != "$FONT" ]; then
      if pgrep -x Stickies >/dev/null 2>&1; then
        osascript -e 'tell application "Stickies" to quit' >/dev/null 2>&1 || true
        sleep 1
      fi
      sz="${SIZE:-11}"
      swift -e "
import AppKit
let path = \"$STICKIES_PLIST\"
guard let font = NSFont(name: \"$FONT\", size: $sz) else { FileHandle.standardError.write(\"bad font\n\".data(using:.utf8)!); exit(1) }
let data = try! NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)
let d = NSMutableDictionary(contentsOfFile: path) ?? NSMutableDictionary()
d[\"DefaultFont\"] = data
if !d.write(toFile: path, atomically: true) { FileHandle.standardError.write(\"write failed\n\".data(using:.utf8)!); exit(1) }
"
      echo "Stickies default note font set to $FONT (was: $local_cur)"
    else
      echo "Stickies default note font already $FONT (skipped)"
    fi

    echo "---- applied; current state ----"
    report
    echo "NOTE: relaunch apps to pick up changes. Apple Notes is not covered (it uses its own mono face)."
    ;;
  *)
    echo "usage: apply.sh {check|apply} [--font NAME] [--size N]" >&2
    exit 2 ;;
esac
