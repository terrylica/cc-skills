#!/usr/bin/env bash
# draft-hold — park a message/draft in macOS Notes for the operator to edit, then
# read it back. macOS Notes is the source of truth (fully AppleScript-scriptable,
# iCloud-synced, editable on any device). Stickies is NOT reliably scriptable
# (no usable dictionary) so it's only a best-effort, view-only desktop mirror.
#
# Every draft is self-contained: a provenance footer stamps the Claude Code
# session UUID + project + timestamp, so any note traces back to its session JSONL.
#
# Usage:
#   draft-hold.sh new "<title>" [--session UUID] [--project NAME] [--folder NAME]   # body on STDIN
#   draft-hold.sh get "<title>" [--folder NAME]      # print note body as plain text (read-back)
#   draft-hold.sh list [--folder NAME]               # list draft titles
#   draft-hold.sh sticky "<title>" [--folder NAME]   # best-effort: mirror to a desktop Stickies note
#
# Env: CLAUDE_SESSION_ID is used if --session is omitted.
set -euo pipefail

FOLDER="Claude Drafts"
SESSION="${CLAUDE_SESSION_ID:-}"
PROJECT="$(basename "$PWD")"
BODY_ONLY=0

cmd="${1:-}"; shift || true
title=""
# first positional (title) for new/get/sticky
case "$cmd" in
  new|get|sticky) title="${1:-}"; shift || true ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --session)   SESSION="${2:-}"; shift 2 ;;
    --project)   PROJECT="${2:-}"; shift 2 ;;
    --folder)    FOLDER="${2:-}"; shift 2 ;;
    --body-only) BODY_ONLY=1; shift ;;
    *) shift ;;
  esac
done

# HTML-encode for the body we hand to Notes. We MUST encode " as well: although
# Notes tolerates a raw " on input, its AppleScript `body` getter re-serializes
# every " as the *semicolon-less* legacy entity `&quot` on read-back — so we
# always decode with a real HTML parser (textutil) rather than fragile sed.
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

# Decode a Notes `body` HTML string to plain text. textutil (WebKit-backed)
# handles tags->linebreaks AND legacy entities with or without the trailing
# semicolon (`&quot` -> "), which the old `sed s/&quot;/"/g` silently missed.
# The <meta charset> prefix is REQUIRED: without a charset declaration textutil
# misreads UTF-8 stdin as Latin-1 and mojibakes every non-ASCII character
# (verified 2026-07-02 with a Chinese draft: 关于 -> å…³äºŽ).
html_to_text() { { printf '<meta charset="utf-8">'; cat; } | textutil -stdin -stdout -convert txt -format html; }

case "$cmd" in
  new)
    [ -n "$title" ] || { echo "usage: draft-hold.sh new <title>  (body on stdin)" >&2; exit 2; }
    raw="$(cat)"
    # Wrap every line in <tt> so Notes stores the note as "Monostyled" (its monospaced
    # paragraph style — verified: Monostyled round-trips as <tt>). The title is the bold
    # first line so the Notes-derived note NAME == title (get/list/replace need that).
    title_html="<div><tt><b>$(printf '%s' "$title" | esc)</b></tt></div><div><br></div>"
    html="$(printf '%s\n' "$raw" | esc | awk '{ if($0=="") print "<div><br></div>"; else print "<div><tt>"$0"</tt></div>" }')"
    sess_seg=""; [ -n "$SESSION" ] && sess_seg="session ${SESSION} | "
    footer="<div><br></div><div><tt>------</tt></div><div><tt>Held by Claude Code | ${sess_seg}${PROJECT} | $(date '+%Y-%m-%d %H:%M %Z')</tt></div>"
    body="${title_html}${html}${footer}"
    osascript - "$FOLDER" "$title" "$body" <<'OSA'
on run {folderName, noteTitle, bodyHTML}
  tell application "Notes"
    if not (exists folder folderName) then make new folder with properties {name:folderName}
    if exists note noteTitle of folder folderName then delete note noteTitle of folder folderName
    set n to make new note at folder folderName with properties {body:bodyHTML}
    return (id of n)
  end tell
end run
OSA
    ;;
  get)
    [ -n "$title" ] || { echo "usage: draft-hold.sh get <title> [--body-only]" >&2; exit 2; }
    full="$(osascript - "$FOLDER" "$title" <<'OSA' | html_to_text
on run {folderName, noteTitle}
  tell application "Notes"
    if not (exists note noteTitle of folder folderName) then return "(no such draft)"
    return body of note noteTitle of folder folderName
  end tell
end run
OSA
)"
    if [ "$BODY_ONLY" = "1" ]; then
      # Sendable message only: drop the title heading (first non-empty line) and
      # everything from the provenance separator (------) onward.
      printf '%s\n' "$full" | awk '
        BEGIN { state = "pre" }
        /^------[[:space:]]*$/ { exit }
        {
          if (state == "pre")   { if (NF == 0) next; state = "title"; next }
          if (state == "title") { if (NF == 0) next; state = "body" }
          print
        }'
    else
      printf '%s\n' "$full" | awk 'NF || prev{print} {prev=NF}'
    fi
    ;;
  list)
    osascript - "$FOLDER" <<'OSA'
on run {folderName}
  tell application "Notes"
    if not (exists folder folderName) then return "(folder not found: " & folderName & ")"
    set out to ""
    repeat with n in notes of folder folderName
      set out to out & (name of n) & linefeed
    end repeat
    return out
  end tell
end run
OSA
    ;;
  sticky)
    [ -n "$title" ] || { echo "usage: draft-hold.sh sticky <title>" >&2; exit 2; }
    # Stickies has no AppleScript dictionary -> GUI-script via clipboard + Cmd-N + paste.
    # Requires Accessibility permission for the controlling app. Best-effort, view-only.
    text="$(osascript - "$FOLDER" "$title" <<'OSA'
on run {folderName, noteTitle}
  tell application "Notes"
    if not (exists note noteTitle of folder folderName) then return ""
    return body of note noteTitle of folder folderName
  end tell
end run
OSA
)"
    plain="$(printf '%s' "$text" | html_to_text)"
    plain="Draft (edit in Notes -> $FOLDER -> $title)"$'\n\n'"$plain"
    printf '%s' "$plain" | pbcopy
    osascript <<'OSA' 2>&1 || echo "Stickies mirror failed (grant Accessibility to the controlling app). Notes copy is authoritative."
tell application "Stickies" to activate
delay 0.6
tell application "System Events" to tell process "Stickies"
  keystroke "n" using command down
  delay 0.4
  keystroke "v" using command down
end tell
OSA
    echo "Mirrored to Stickies (view-only). Edit the real draft in Notes -> $FOLDER -> $title."
    ;;
  *)
    echo "usage: draft-hold.sh {new <title>|get <title>|list|sticky <title>} [--session UUID] [--project NAME] [--folder NAME]" >&2
    exit 2 ;;
esac
