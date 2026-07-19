# notes-commander

macOS Notes organizer + human-in-the-loop drafts for Claude Code — full read/export wiring, safe folderization, and the draft-hold workflow, all on one hardened AppleScript engine.

## What it does

- **Inventory** — every account, folder (nested included), and note count as data (`inventory [--json]`).
- **Export/backup** — snapshot ALL notes to local markdown + a JSON manifest (`export`), default under `~/.local/share/notes-commander/export/<stamp>/`. The undo story for any cleanup.
- **Organize** — `mkdir`, `move-note`, `rename-folder`, `merge-folder`, each dry-runnable; no delete verb by design (worst case is "wrong folder", never "gone").
- **Audit** — a skill that analyzes your folder taxonomy (empty folders, dumping grounds, mixed-language naming, stale content) and proposes a target hierarchy before anything moves.
- **draft-hold** — park an outbound draft in Notes for human editing, read it back before sending (provenance-stamped with the Claude Code session UUID). Migrated from the retired standalone `draft-hold` plugin.
- **Doctor** — `notes.ts doctor` runs a live create → read-back-verify → delete round-trip plus an inventory pass.

## Install

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install notes-commander
```

Requires Bun and macOS. First run prompts once for Automation permission to control Notes.

## Hardening

The shared engine (`scripts/lib/notes-core.ts`, unit-tested) guards the real-world AppleScript failure modes on recent macOS:

- **Silent no-op detection** — creation asserts Notes returned a real `x-coredata://` note id (osascript can exit 0 yet create nothing on macOS 26).
- **Bounded retry** — transient AppleEvent errors (`-600`, `-1712`, "not running") retry with backoff; permission/syntax errors fail fast.
- **Read-back verify** — drafts are re-read after save and checked for entity leaks (`&quot` without semicolon — a Notes quirk) and content presence, UTF-8/CJK-safe.

## Skills

`draft-hold` · `notes-inventory` · `notes-export` · `notes-organize` · `notes-audit`

See [CLAUDE.md](./CLAUDE.md) for maintainer invariants (path-based folder resolution, the no-delete rule, cache-layer script paths).
