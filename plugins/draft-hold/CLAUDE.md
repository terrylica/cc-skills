# draft-hold Plugin

> Park a draft in macOS Notes (provenance-stamped) for the operator to edit, then read it back.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why

Sending anything to a real person should pass through a human-editable holding surface. macOS **Notes** is the low-friction choice: fully AppleScript-scriptable (CRUD verified), iCloud-synced (edit on Mac/iPhone/iPad), and cleanly read back. **Stickies is NOT reliably scriptable** (no usable AppleScript dictionary — `count windows` → error -1708; only fragile System-Events GUI keystrokes), so it's a best-effort, view-only desktop mirror only.

## Deep-link reality (verified 2026-06-29)

There is **no scriptable URL to open a specific Note**: `open "x-coredata://…/ICNote/p…"` fails (`-10814`), and the native `applenotes:` links (Sonoma+) are created only via the UI "Add Link" command. So the Stickies mirror references the draft **by folder + title**, not a clickable link.

## Provenance (load-bearing)

Every draft gets a footer stamping the **Claude Code session UUID** (`CLAUDE_SESSION_ID` or `--session`), project, and timestamp — so any held note traces back to its session JSONL for later review. If the session id is absent, the token is **omitted** (never a placeholder — operator directive 2026-06-11).

## Skill

- [draft-hold](./skills/draft-hold/SKILL.md)

## Script

`skills/draft-hold/draft-hold.sh {new <title>|get <title>|list|sticky <title>} [--session UUID] [--project NAME] [--folder NAME]`

- `new` reads the body on STDIN, wraps it as HTML, appends the provenance footer, and creates/replaces the note in folder "Claude Drafts".
- `get` prints the note body as plain text (read-back for confirmation).
- `sticky` is best-effort GUI scripting (needs Accessibility permission); Notes stays authoritative.
