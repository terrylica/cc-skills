# notes-commander Plugin

> macOS Notes organizer (read/export/reorganize, all accounts) + the migrated draft-hold skill, on one hardened AppleScript engine.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why

The operator's Notes tree grew sporadic — ~30 mostly-flat iCloud folders across 3 accounts, mixed EN/中文 naming, near-empty folders next to 100+-note dumping grounds, tags barely used. Organizing it safely needs _wiring first_: full read + export to local storage (the undo story), then deliberate folderization primitives, then an audit that proposes before anything moves. draft-hold (previously its own plugin) already owned the hardened Notes/AppleScript know-how, so it migrated in as one skill of this plugin (2026-07-18) rather than duplicating the engine.

## Architecture (load-bearing)

- **`scripts/lib/notes-core.ts`** — the ONE shared engine. Pure helpers (`isNoteId`, `isTransientOsaError`, `entityLeaks`, `contentPresent`, `bodyToHtml`, `parseRecords`, `safeFilename`) + `runOsa` (osascript with bounded retry on transient AppleEvent errors only). Pure parts unit-tested in `notes-core.test.ts` (16 tests). AppleScript payloads live in the consumers, not here.
- **`scripts/notes.ts`** — organizer CLI: `inventory` / `export` / `mkdir` / `move-note` / `rename-folder` / `merge-folder` / `doctor`. FS/RS-delimited (U+0001/U+0002) record streams from AppleScript, parsed by `parseRecords` (AppleScript has no JSON).
- **`scripts/draft-hold.ts`** — the draft-hold engine, now importing the shared core; `new` verifies a real note id + read-back (entity leaks, content presence) by default.
- **Skills reference scripts via the Layer-2 marketplace mirror path** (`$HOME/.claude/plugins/marketplaces/cc-skills/plugins/notes-commander/scripts/…`).
  <!-- LAYER3-STRIPPED-PATH-OK: documenting the forbidden pattern itself, not using it -->
  NEVER via `${CLAUDE_PLUGIN_ROOT}/scripts/` — the Layer-3 operator cache strips `scripts/` (iter-78 guard enforces this; gmail-commander precedent). The draft-hold shim resolves relative first (repo/L2), then falls back to the L2 mirror path.

## Critical invariants

1. **No delete verb.** Notes are only moved, never deleted; `merge-folder` empties but keeps the source folder. Worst case must stay "wrong folder", never "gone".
2. **Snapshot before reorganizing.** `notes-organize`'s protocol requires a `notes-export` run first (default root `~/.local/share/notes-commander/export/` — outside any repo, never committed).
3. **Folder PATHS, not names.** `/`-separated paths (`To-Do / Done`) resolved segment-by-segment from the account root (`resolveFolder`); names are NOT unique. `folders of <account>` returns a FLATTENED list (nested included) — top-level detection filters on `class of (container of f) is account`.
4. **Silent-failure guard.** Creation asserts `isNoteId` on the returned value — on macOS 26 osascript can exit 0 yet create nothing.
5. **textutil decode keeps the `<meta charset="utf-8">` prefix** (Latin-1 mojibake otherwise) and is the only entity decoder (Notes emits semicolon-less `&quot`). Never sed.
6. **Batch AppleScript property fetches** (`body of every note of f`) — per-note Apple Events are quadratically slow.
7. Tags have **no AppleScript API**; cross-account `move` is unsupported. Both are documented manual actions, not bugs.

## Skills

| Skill                                                | Purpose                                                                                                                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| [draft-hold](./skills/draft-hold/SKILL.md)           | Park a draft in Notes for human edit, read back before sending (migrated from the retired draft-hold plugin; its evolution log continues there) |
| [notes-inventory](./skills/notes-inventory/SKILL.md) | Accounts → folder tree → counts, human or `--json`                                                                                              |
| [notes-export](./skills/notes-export/SKILL.md)       | Full snapshot → markdown + `manifest.json` under `~/.local/share/notes-commander/export/<stamp>/`                                               |
| [notes-organize](./skills/notes-organize/SKILL.md)   | mkdir / move-note / rename-folder / merge-folder / doctor, dry-run first                                                                        |
| [notes-audit](./skills/notes-audit/SKILL.md)         | Analyze inventory+snapshot, propose a target hierarchy, STOP for approval                                                                       |

## Testing

`bun test` from the plugin dir (or repo root — colocated `*.test.ts` discovered automatically): 16 pure-helper tests. Live round-trip: `bun scripts/notes.ts doctor` (create → read-back verify → delete probe note + inventory count).
