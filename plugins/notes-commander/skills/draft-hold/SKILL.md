---
name: draft-hold
description: Park a draft message/text in macOS Notes for the operator to review and edit, then read it back before acting (e.g. before sending to a real person). Notes is the source of truth (AppleScript CRUD, iCloud-synced, provenance-stamped with the Claude Code session UUID); Stickies is a best-effort view-only desktop mirror. Use whenever you draft something a human should confirm/edit before it is sent or committed — messages, replies, announcements, anything outbound. TRIGGERS - hold this draft, park the message, let me edit first, draft for my approval, save to notes for review, read back the draft.
allowed-tools: Bash, Read
---

# draft-hold — human-in-the-loop drafts via macOS Notes

> **Self-Evolving skill** — if macOS Notes/Stickies behavior drifts from what's below, fix this SKILL.md and the shared engine `scripts/lib/notes-core.ts` (+ a case in `notes-core.test.ts`); see the Post-Execution Reflection at the bottom.

When you compose something a human should confirm or edit before it goes out (a message to a real person, an announcement, a commit body), **don't keep it only in chat** — park it in macOS Notes so the operator can edit it on any device, then read it back and act on the edited version.

`DH="$CLAUDE_PLUGIN_ROOT/skills/draft-hold/draft-hold.sh"` — a thin shim that `exec`s the **Bun/TypeScript engine** `scripts/draft-hold.ts`, built on the plugin's shared `notes-core` engine (which also powers `notes-inventory`/`notes-export`/`notes-organize`).

## Formatting is handled in code — just write naturally

The engine (formatter in `scripts/lib/notes-core.ts`, unit-tested in `notes-core.test.ts`) normalizes your input into Notes HTML, so you never hand-manage line breaks:

- **Prose reflows.** Consecutive non-blank lines join into ONE paragraph that Notes soft-wraps to the reader's screen. Accidental hard-wrapping (text pre-wrapped at ~80/100 cols) is corrected automatically — it can no longer become a permanent mid-sentence break. Blank lines are the only breaks that matter.
- **A blank line = a new paragraph/section.** That is the one authored break.
- **List items** — lines beginning with `-`, `*`, `+`, `•`, `1.`, `2)`, `a.` etc. each stay on their own line; a wrapped continuation line (indented, no marker) joins back to its item.
- **Verbatim / columnar / code blocks** — wrap them in a ` ``` ` fence. Every line inside is preserved exactly and rendered monospace with spaces held (via `&nbsp;`), so columns and IDs line up **in the Notes UI**. (Note: `get --body-only` returns the _sendable_ plain text and collapses inter-column runs to single spaces; if exact alignment must survive to the recipient, send an attachment/screenshot.)

## Hardening (verified failure modes this engine guards)

- **Silent-failure detection** — `new` asserts Notes returned a real note id (`x-coredata://…`); on recent macOS, osascript can exit 0 yet create nothing. If that happens you get a loud `✗ SILENT-FAILURE` instead of a phantom "success".
- **Bounded retry** — transient AppleEvent errors (`-600`/`-1712`/"not running") retry with backoff; permission/syntax errors fail fast.
- **Read-back verify (default ON)** — after `new`, the note is read back and checked for entity leaks and content presence. `--no-verify` skips (rarely needed).

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

   Use `--body-only` to get exactly the text to send/paste — it strips the title heading and everything from the `------` provenance separator onward. Show the operator the exact current text, get explicit go-ahead, then send/commit.

4. `"$DH" list` enumerates held drafts.

## macOS quirks this skill handles for you

- **Quote serialization**: Notes' AppleScript `body` getter re-emits every `"` as the _semicolon-less_ legacy entity `&quot` (verified 2026-06-29). We decode with `textutil` (a real HTML parser) instead of `sed`, so `&quot`/`&amp`/`&lt` etc. round-trip back to literal characters. Never hand-roll entity decoding here. The read-back verify now DETECTS a drift here automatically (`✗ ENTITY-LEAK`).
- **UTF-8 decode needs an explicit charset**: `textutil -format html` assumes Latin-1 when the HTML has no charset declaration, mojibaking every non-ASCII character (关于 → `å…³äºŽ`; verified 2026-07-02 with a Chinese draft). `htmlToText` therefore prepends `<meta charset="utf-8">` before piping to textutil — keep that prefix.
- **Note name = first body line**: Notes names a note after its first line, ignoring any title you "set". `new` therefore prepends the title as a bold first line so `get`/`list`/replace can find it by title. Pass the message body only on STDIN.
- **Proportional prose, monospace only in fences**: prose paragraphs render in Notes' normal proportional font (so a long line reflows). Only ` ``` ` fenced blocks are wrapped in `<tt>` (Notes' "Monostyled" face) with spaces held as `&nbsp;`. The mono face is fixed by Notes — it is _not_ the global `NSFixedPitchFont`, which governs TextEdit-style apps, not Notes.

## Getting the session UUID for provenance

Pass the current Claude Code session JSONL UUID via `CLAUDE_SESSION_ID` or `--session` so the note traces back to its session. If you don't know it, the `statusline-tools:session-info` skill reports it, or read the newest `*.jsonl` under `~/.claude/projects/<project-slug>/`. If genuinely unavailable, omit it (the footer drops the token — never write a placeholder).

## Rules

- **Never send/commit from memory** — always `get` the note first; the operator may have changed it.
- Notes is the source of truth. Stickies cannot be read back (no AppleScript dictionary), so never treat a sticky as the live draft.
- There is no scriptable deep-link to a specific note (`open x-coredata://…` fails; `applenotes:` links are UI-only) — reference drafts by **folder + title**.
- First run prompts once for Automation permission to control Notes.

## Evolution log

- **2026-07-18 (b) — migrated into notes-commander + hardened.** The standalone draft-hold plugin was folded into the new `notes-commander` plugin as one of its skills; formatting + process wrappers moved to the shared `scripts/lib/notes-core.ts` engine. Added, per a web-researched audit of recent macOS AppleScript failure modes: silent-no-op detection (`isNoteId` on create — osascript can exit 0 yet create nothing on macOS 26), bounded retry on transient AppleEvent errors (`-600`/`-1712`), and a default-on read-back verify (`entityLeaks` + `contentPresent`). All pure helpers unit-tested (16 tests in `notes-core.test.ts`).
- **2026-07-18 (a) — hard-wrapped prose became forced mid-sentence breaks.** A long bilingual briefing was passed with each paragraph pre-wrapped at ~100 chars; because the old bash `new` made each input line its own Notes paragraph (all wrapped in `<tt>`), the reader saw mid-sentence line breaks that did not reflow. _First fix (insufficient)_: a "one line per paragraph" caller contract — but that only works if every caller remembers it. _Real fix_: reimplemented the engine as **Bun/TypeScript**, enforcing the formatting in code so the failure is impossible: prose blocks REFLOW (consecutive lines join; blank line = paragraph), list markers stay per-item, and only ` ``` ` fenced blocks are preserved verbatim/monospace (spaces held as `&nbsp;`). Verified by unit tests + a live Notes round-trip.

## Post-Execution Reflection

After holding or sending a draft, check before closing:

1. **Did read-back match what Notes shows?** — if entities/quotes leaked (e.g. `&quot`), the decode path drifted; the verify step should have caught it — fix the `textutil` step in `notes-core.ts`, never hand-roll sed.
2. **Did `get`/`list` find the note by title?** — if not, the name==title assumption broke; fix the title-prepend in `new`.
3. **Did Notes/Stickies change behavior?** — update the macOS-quirks section so the next run doesn't rediscover it.

Only update if the issue is real and reproducible — not speculative.
