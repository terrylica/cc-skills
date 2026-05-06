# openwolf Plugin

> Wraps the third-party [openwolf](https://github.com/cytostack/openwolf) npm middleware (Cytostack, AGPL-3.0) — installs/inspects/cleanly removes its `.wolf/` directory, Claude Code hook entries, CLAUDE.md snippet, rules file, and global registry entry per project.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [kokoro-tts CLAUDE.md](../kokoro-tts/CLAUDE.md) | [plugins/CLAUDE.md](../CLAUDE.md)

## What openwolf does

`openwolf init` writes the following into the **target project**:

- `.wolf/` directory — `anatomy.md`, `cerebrum.md`, `memory.md`, `buglog.json`, `token-ledger.json`, `OPENWOLF.md`, `identity.md`, `config.json`, `reframe-frameworks.md`, plus 6 compiled hook scripts under `.wolf/hooks/`.
- 6 hook entries merged into `.claude/settings.json` (`SessionStart`, `PreToolUse:Read`, `PreToolUse:Write|Edit|MultiEdit`, `PostToolUse:Read`, `PostToolUse:Write|Edit|MultiEdit`, `Stop`).
- `.claude/rules/openwolf.md` (cursor-style rules).
- A 225-byte snippet **prepended** to `CLAUDE.md` that imports `@.wolf/OPENWOLF.md`.
- An entry in `~/.openwolf/registry.json` (the global project registry).
- Optional: a PM2 daemon `openwolf-{basename}` on port 18790 (dashboard 18791) — only if PM2 is installed; degrades gracefully otherwise.

The npm package ships **no `uninstall` command** — clean removal is this plugin's load-bearing responsibility.

## Skills

- [install](./skills/install/SKILL.md) — install global npm + run `openwolf init` in current project
- [status](./skills/status/SKILL.md) — surface `openwolf status` output for current project
- [remove](./skills/remove/SKILL.md) — full removal: `.wolf/`, hooks, rules, CLAUDE.md snippet, PM2 daemon, registry entry

## Conventions / invariants

- **Per-project, not user-global.** Skip `init` on this marketplace repo and on small one-shots. Use it on focused product repos.
- **Mutates `.claude/settings.json`.** The init merges 6 hook entries; `remove` filters by `.wolf/hooks/` substring in the `command` field, preserving every other hook (verbatim merge logic mirrors openwolf's `replaceOpenWolfHooks`).
- **Mutates `CLAUDE.md`.** The init prepends a fixed 225-byte block. `remove` strips exactly that block plus the `\n\n` separator and leaves the rest untouched.
- **Registry is load-bearing.** `openwolf update` walks `~/.openwolf/registry.json` and re-runs init on every entry. Stale entries → silent re-init of removed projects. `remove` always unregisters.
- **PM2 is optional.** `daemon` checks `which pm2` and degrades gracefully. `remove` calls `pm2 delete openwolf-{basename}` with `|| true`.
- **AGPL-3.0 boundary.** This plugin contains zero openwolf source code — only invokes the published npm binary. No license obligation.

## Key paths

| Resource          | Path (relative to target project)   |
| ----------------- | ----------------------------------- |
| Wolf data         | `.wolf/`                            |
| Hook scripts      | `.wolf/hooks/*.js`                  |
| Cursor rules      | `.claude/rules/openwolf.md`         |
| Settings hooks    | `.claude/settings.json` (merged)    |
| CLAUDE.md snippet | top of `CLAUDE.md`                  |
| Global registry   | `~/.openwolf/registry.json`         |
| PM2 daemon        | `openwolf-{basename}` on port 18790 |
| Dashboard         | `http://localhost:18791`            |

## Removal contract (what `remove` guarantees)

After `remove` succeeds, **all** of these are true:

1. `.wolf/` does not exist in the project.
2. `.claude/settings.json` contains zero entries whose `command` includes `.wolf/hooks/`. All other hooks preserved.
3. `.claude/rules/openwolf.md` does not exist.
4. `CLAUDE.md` does not contain the openwolf snippet.
5. `~/.openwolf/registry.json` has no entry pointing at this project.
6. PM2 daemon `openwolf-{basename}` is not running (or PM2 is not installed).

`remove` is **idempotent** — running it twice is safe.
