# orca-tools Plugin

> Claude Code under the Orca IDE: worktree spin-offs with one agent terminal, locally and on paired runtimes.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [git-town-workflow CLAUDE.md](../git-town-workflow/CLAUDE.md)

## Skills

- [worktree-spinoff](./skills/worktree-spinoff/SKILL.md)

## Invariants

- **One agent tab.** A spin-off is created with `orca worktree create --agent <id> --prompt …`. Never add the agent afterwards with `terminal create`: that leaves Orca's fallback shell as a second tab.
- **Every `orca` call goes through `o()`.** It carries `--environment` / `--pairing-code`, so the same script targets this machine or a paired runtime. Keep new calls inside it.
- **Find the IDE's CLI with `find_orca`.** On Linux desktops `/usr/bin/orca` is often the GNOME screen reader, so never call a bare `orca`.
- **No project or personal identity.** Nothing in the script or the skill names a repository, host, account or person. Machine-specific values (keys, aliases, paths) stay in the user's own configuration.
- **Portable shell.** bash 3.2 (stock macOS) through current bash, BSD and GNU userland alike. No `realpath`, `readlink -f`, `sed -i` or `${var,,}`; Python handles paths and JSON. Shell values reach Python only as argv.
- **Clean failure.** A failed run leaves no staging branch, local or remote, and no temporary worktree; the EXIT trap owns that.

## Verified

The script was verified on 2026-10-13:

| Platform | Shell | What ran |
| --- | --- | --- |
| Linux (Ubuntu, Orca AppImage) | bash 5.3 | Full create/remove cycles: one tab, `prompt_seen`, no leftovers. |
| macOS (Orca.app) | `/bin/bash` 3.2 | Full cycles, with the repo's setup tab and with `--setup skip`. |
| A second Linux desktop | — | Only a dry run, against an Orca install whose `/usr/bin/orca` is the screen reader. |

The `--environment` and `--host` paths follow Orca's documented flags but were not exercised end to end; no runtimes were paired at the time.

## Recent changes

- 2026-10-13: plugin created from a project-local skill, made agnostic and portable.
