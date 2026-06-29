---
name: draft-hold
description: Park a draft message/text in macOS Notes for the operator to review and edit, then read it back before acting (e.g. before sending to a real person). Notes is the source of truth (AppleScript CRUD, iCloud-synced, provenance-stamped with the Claude Code session UUID); Stickies is a best-effort view-only desktop mirror. Use whenever you draft something a human should confirm/edit before it is sent or committed — messages, replies, announcements, anything outbound. TRIGGERS - hold this draft, park the message, let me edit first, draft for my approval, save to notes for review, read back the draft.
allowed-tools: Bash, Read
---

# draft-hold — human-in-the-loop drafts via macOS Notes

When you compose something a human should confirm or edit before it goes out (a message to a real person, an announcement, a commit body), **don't keep it only in chat** — park it in macOS Notes so the operator can edit it on any device, then read it back and act on the edited version.

`DH="$CLAUDE_PLUGIN_ROOT/skills/draft-hold/draft-hold.sh"`

## Workflow

1. **Park the draft** (body on STDIN):

   ```bash
   CLAUDE_SESSION_ID=<this-session-uuid> "$DH" new "<title>" --project "<repo-or-context>" <<'EOF'
   Hi <name> — <your drafted message>...
   EOF
   ```

   Creates/replaces a note in the **"Claude Drafts"** folder with a provenance footer (session UUID + project + timestamp). Tell the operator: _"Draft is in Notes → Claude Drafts → <title>; edit it there, then tell me to send."_

2. **(Optional) desktop mirror** — `"$DH" sticky "<title>"` pops a view-only Stickies note (needs Accessibility permission). Notes stays authoritative.

3. **Read it back** before acting — ALWAYS re-read, since the operator may have edited it:

   ```bash
   "$DH" get "<title>"              # full note (heading + message + provenance footer)
   "$DH" get "<title>" --body-only  # JUST the sendable message (no heading, no footer)
   ```

   Use `--body-only` to get exactly the text to send/paste — it strips the title
   heading and everything from the `------` provenance separator onward. Show the
   operator the exact current text, get explicit go-ahead, then send/commit.

4. `"$DH" list` enumerates held drafts.

## macOS quirks this skill handles for you

- **Quote serialization**: Notes' AppleScript `body` getter re-emits every `"` as the
  _semicolon-less_ legacy entity `&quot` (verified 2026-06-29). We decode with
  `textutil` (a real HTML parser) instead of `sed`, so `&quot`/`&amp`/`&lt` etc. round-trip
  back to literal characters. Never hand-roll entity decoding here.
- **Note name = first body line**: Notes names a note after its first line, ignoring any
  title you "set". `new` therefore prepends the title as a bold first line so
  `get`/`list`/replace can find it by title. Pass the message body only on STDIN.
- **Monospaced by default**: `new` wraps every line in `<tt>`, which Notes renders as its
  monospaced ("Monostyled") style — drafts read like a code block so columns/IDs line up.
  This is cosmetic in Notes only; `get`/`--body-only` strip the tags, so the text you
  send is unaffected. (Notes' mono face is fixed by Notes — it is _not_ the global
  `NSFixedPitchFont`; that default governs TextEdit-style apps, not Notes.)

## Getting the session UUID for provenance

Pass the current Claude Code session JSONL UUID via `CLAUDE_SESSION_ID` or `--session` so the note traces back to its session. If you don't know it, the `statusline-tools:session-info` skill reports it, or read the newest `*.jsonl` under `~/.claude/projects/<project-slug>/`. If genuinely unavailable, omit it (the footer drops the token — never write a placeholder).

## Rules

- **Never send/commit from memory** — always `get` the note first; the operator may have changed it.
- Notes is the source of truth. Stickies cannot be read back (no AppleScript dictionary), so never treat a sticky as the live draft.
- There is no scriptable deep-link to a specific note (`open x-coredata://…` fails; `applenotes:` links are UI-only) — reference drafts by **folder + title**.
- First run prompts once for Automation permission to control Notes.
