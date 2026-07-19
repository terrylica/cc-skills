---
name: notes-organize
description: Reorganize macOS Notes deliberately - create folders (incl. nested subfolders), move notes between folders, rename folders, and merge/empty a folder into another. Every destructive-ish verb supports --dry-run, and the workflow REQUIRES a notes-export snapshot first. Use when folderizing sporadic notes, splitting an oversized folder, consolidating near-empty folders, or executing a notes-audit proposal. TRIGGERS - organize my notes, move this note, create notes folder, folderize, merge folders, clean up notes folders, rename notes folder.
allowed-tools: Bash, Read
---

# notes-organize — the reorganization primitives

The folderization verbs, built on the shared hardened engine (path-based folder resolution,
transient-error retry). Folder **paths** use `/` between segments (`To-Do / Done`) because
names are not unique across the tree.

```bash
NC="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/notes-commander/scripts/notes.ts"

bun "$NC" mkdir "Projects"                                   # top-level folder (iCloud default)
bun "$NC" mkdir "Archive" --parent "Projects"                # nested subfolder
bun "$NC" move-note "Meeting notes" --from "Notes" --to "Projects" --dry-run   # preview
bun "$NC" move-note "Meeting notes" --from "Notes" --to "Projects"             # execute
bun "$NC" rename-folder "NAD+ Biz" --to "NAD+ Business"
bun "$NC" merge-folder "Test Folder" --into "Archive" --dry-run                # preview count
bun "$NC" merge-folder "Test Folder" --into "Archive"        # moves ALL notes out of source
bun "$NC" doctor                                             # end-to-end health round-trip
```

All verbs accept `--account A` (default `iCloud`; your Google/Exchange accounts by name).

## The safety protocol (ALWAYS follow, in order)

1. **Snapshot first** — run the `notes-export` skill. No snapshot → no reorganization.
2. **Dry-run** any `move-note`/`merge-folder` and show the operator what will happen.
3. **Execute**, then re-run `inventory` to confirm the resulting counts.
4. Ambiguous titles: `move-note` refuses when several notes share the title and prints their ids — re-run with `--id x-coredata://…`.

## Deliberate limitations (guard rails, not gaps)

- **No delete verb.** Notes are only ever MOVED; folders are never deleted by this tool. `merge-folder` empties the source but leaves the (now-empty) folder for the operator to delete in the Notes UI after visual confirmation. This keeps the worst possible outcome "a note is in the wrong folder", never "a note is gone".
- Tags (`#tag`) have **no AppleScript API** — organizing is folder-based. If tag hygiene matters, note it in the audit output for manual action.
- Moves between DIFFERENT accounts are not supported by Notes' AppleScript `move` (same-account only). Cross-account moves are a manual drag in the UI.
