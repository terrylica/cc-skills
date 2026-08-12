# notes-commander Plugin

> macOS Notes organizer (read/export/reorganize, all accounts) + the `draft-park` human-in-the-loop draft skill, on one hardened AppleScript engine.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Why

The operator's Notes tree grew sporadic — ~30 mostly-flat iCloud folders across 3 accounts, mixed EN/中文 naming, near-empty folders next to 100+-note dumping grounds, tags barely used. Organizing it safely needs _wiring first_: full read + export to local storage (the undo story), then deliberate folderization primitives, then an audit that proposes before anything moves. `draft-park` owns the hardened Notes/AppleScript know-how and lives here as one skill of this plugin rather than duplicating the engine.

## Architecture (load-bearing)

- **`scripts/lib/notes-core.ts`** — the ONE shared engine. Pure helpers (`isNoteId`, `isTransientOsaError`, `entityLeaks`, `terminateLegacyEntities`, `contentPresent`, `bodyToHtml`, `parseRecords`, `safeFilename`, `noteNameMatchesTitle`, `matchNoteIds`) + `runOsa` (osascript with bounded retry on transient AppleEvent errors only). Pure parts unit-tested in `notes-core.test.ts` (30 tests). AppleScript payloads live in the consumers, not here.
- **`scripts/notes.ts`** — organizer CLI: `inventory` / `export` / `mkdir` / `move-note` / `rename-folder` / `merge-folder` / `doctor`. FS/RS-delimited (U+0001/U+0002) record streams from AppleScript, parsed by `parseRecords` (AppleScript has no JSON).
- **`scripts/draft-park.ts`** — the draft-park engine, now importing the shared core; `new` verifies a real note id + read-back (entity leaks, content presence) by default.
- **Skills resolve their entrypoint with `cc-plugin-root`** — `SH="$(cc-plugin-root notes-commander)/skills/<skill>/<script>"`. That helper (`scripts/cc-plugin-root`, symlinked to `~/.local/bin/`) reads `~/.claude/plugins/installed_plugins.json`, so it returns the version Claude Code actually loaded. Do NOT glob `~/.claude/plugins/cache/cc-skills/notes-commander/*` — 10 of the 11 cached versions there are marked `.orphaned_at`, and the highest semver is routinely one of them.
  `scripts/` is present in the latest cached version of **all 27** cc-skills plugins that ship one, this plugin included, so the shim's relative resolution (`$here/../../scripts/draft-park.ts`) resolves from the L3 cache; its L2 marketplace-mirror fallback is belt-and-suspenders, not the primary path.

## Critical invariants

1. **No delete verb.** Notes are only moved, never deleted; `merge-folder` empties but keeps the source folder. Worst case must stay "wrong folder", never "gone".
2. **Snapshot before reorganizing.** `notes-organize`'s protocol requires a `notes-export` run first (default root `~/.local/share/notes-commander/export/` — outside any repo, never committed).
3. **Folder PATHS, not names.** `/`-separated paths (`To-Do / Done`) resolved segment-by-segment from the account root (`resolveFolder`); names are NOT unique. `folders of <account>` returns a FLATTENED list (nested included) — top-level detection filters on `class of (container of f) is account`.
4. **Silent-failure guard.** Creation asserts `isNoteId` on the returned value — on macOS 26 osascript can exit 0 yet create nothing.
5. **textutil decode keeps the `<meta charset="utf-8">` prefix** (Latin-1 mojibake otherwise) and is the only entity decoder (Notes emits semicolon-less `&quot`). Never sed.
6. **Batch AppleScript property fetches** (`body of every note of f`) — per-note Apple Events are quadratically slow.
7. Tags have **no AppleScript API**; cross-account `move` is unsupported. Both are documented manual actions, not bugs.
8. **`$CLAUDE_PLUGIN_ROOT` must never appear in a SKILL.md.** It is not a shell variable — Claude Code substitutes the exact literal `${CLAUDE_PLUGIN_ROOT}` (braces required) inside plugin manifests and sets it in hook/MCP subprocess envs only. A skill body is served to the model verbatim, so the reference reaches Bash as an unset var, expands to empty, and calls `/skills/…` → exit 127. This is exactly how `/notes-commander:draft-hold` broke on 2026-08-05. Use `"$(cc-plugin-root notes-commander)/…"`. Note `${CLAUDE_PLUGIN_ROOT:-fallback}` is NOT a fix either — the substitution regex needs the closing brace right after the name, so that idiom silently always takes the fallback.
9. **Title→note-id resolution lives in ONE place: `matchNoteIds` (over a folder's `(id,name)` index).** macOS truncates a long note NAME with a trailing `…`, so exact `whose name is <title>` misses long titles. Both `draft-park` (get/sticky/dedup) and `notes move-note` fetch the index, resolve the title in TS (exact, then truncation-tolerant per `noteNameMatchesTitle`), and act by **id**. Never re-implement name-matching in an AppleScript payload — that duplicate rule was removed 2026-07-20; keep it single-sourced.
10. **Quit Notes before setting the body of an existing note.** While the Notes UI holds the note open, `set body of n to …` fails with AppleEvent error `-10000`. Also resolve the id to a variable inside the `tell` block (`set n to note id "…"`) — the one-liner `set body of note id "…" to …` fails even when the note is closed. Read paths are unaffected by both.

## Skills

| Skill                                                | Purpose                                                                                                                                                                               |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [draft-park](./skills/draft-park/SKILL.md)           | Park a draft in Notes for human edit, read back before sending (migrated from the retired standalone plugin; renamed from `draft-hold` 2026-08-12; its evolution log continues there) |
| [notes-inventory](./skills/notes-inventory/SKILL.md) | Accounts → folder tree → counts, human or `--json`                                                                                                                                    |
| [notes-export](./skills/notes-export/SKILL.md)       | Full snapshot → markdown + `manifest.json` under `~/.local/share/notes-commander/export/<stamp>/`                                                                                     |
| [notes-organize](./skills/notes-organize/SKILL.md)   | mkdir / move-note / rename-folder / merge-folder / doctor, dry-run first                                                                                                              |
| [notes-audit](./skills/notes-audit/SKILL.md)         | Analyze inventory+snapshot, propose a target hierarchy, STOP for approval                                                                                                             |

## Testing

`bun test` from the plugin dir (or repo root — colocated `*.test.ts` discovered automatically): 30 pure-helper tests. Live round-trip: `bun scripts/notes.ts doctor` (create → read-back verify → delete probe note + inventory count).
