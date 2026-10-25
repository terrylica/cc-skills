# orca-tools Plugin

> Claude Code under the Orca IDE: the floating terminal as the default terminal for anything needing a person or a TTY; worktree spin-offs with one agent terminal, locally and on paired runtimes; session closeout with a recall name, a handoff, and an optional close of the session's own tab.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [git-town-workflow CLAUDE.md](../git-town-workflow/CLAUDE.md)

## Skills

- [floating-terminal](./skills/floating-terminal/SKILL.md) — **the default terminal for agents under Orca** (macOS, Linux): `orca-float run -- CMD` runs a command needing Touch ID, a TTY or a person in Orca's floating terminal and returns its real exit code. Never open iTerm/Terminal/gnome-terminal for this
- [worktree-spinoff](./skills/worktree-spinoff/SKILL.md)
- [session-closeout](./skills/session-closeout/SKILL.md)

## Invariants

- **One agent tab.** A spin-off is created with `orca worktree create --agent <id> --prompt …`. Never add the agent afterwards with `terminal create`: that leaves Orca's fallback shell as a second tab.
- **Every `orca` call goes through `o()`.** It carries `--environment` / `--pairing-code`, so the same script targets this machine or a paired runtime. Keep new calls inside it.
- **Find the IDE's CLI with `find_orca`.** On Linux desktops `/usr/bin/orca` is often the GNOME screen reader, so never call a bare `orca`. The shared copy is `scripts/lib/orca-cli.sh` (used by `orca-float`); `orca-spinoff` and `orca-closeout` still carry their own copies, to be moved onto it.
- **Never trust `orca terminal wait` for an exit code.** It reported 0 for a command that exited 7. `orca-float` has the command write its own status file.
- **No project or personal identity.** Nothing in the script or the skill names a repository, host, account or person. Machine-specific values (keys, aliases, paths) stay in the user's own configuration.
- **Portable shell.** bash 3.2 (stock macOS) through current bash, BSD and GNU userland alike. No `realpath`, `readlink -f`, `sed -i` or `${var,,}`; Python handles paths and JSON. Shell values reach Python only as argv.
- **Clean failure.** A failed run leaves no staging branch, local or remote, and no temporary worktree; the EXIT trap owns that.
- **Decide from Orca's data, not the filesystem.** Local or remote comes from `--environment` / `ORCA_ENVIRONMENT` and the row's `hostId`; worktree lookups use `--repo`, skip `isMainWorktree`, and refuse a `truncated` listing.
- **stdout is one JSON object** (built with `json.dumps`); everything else goes to stderr.
- **Never act on Orca's active terminal by default.** Every `orca terminal` call names its handle (`--terminal`): omitted, Orca uses the active terminal, which may be another session's. `orca-closeout` closes only its own tab, confirmed by `ORCA_TAB_ID`, and never uses `--all`.
- **Measured limits live in one place each.** `orca-closeout` holds the name limits (`ORCA_HISTORY_MAX=96`, `CLAUDE_TITLE_MAX=200`) with the code they were read from cited in its SKILL.md; change both together.
- **Help text is captured, never piped to `grep -q`.** Under `pipefail` an early-exiting reader can SIGPIPE the producer and invert the test.

## Verified

The script was verified on 2026-10-13:

| Platform                                             | Shell              | What ran                                                                                                                                                                                     |
| ---------------------------------------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linux (Ubuntu, Orca AppImage)                        | bash 5.3           | Full create/remove cycles: one tab, `prompt_seen`, no leftovers.                                                                                                                             |
| macOS (Orca.app)                                     | `/bin/bash` 3.2    | Full cycles, with the repo's setup tab and with `--setup skip`.                                                                                                                              |
| A second Linux desktop                               | —                  | Only a dry run, against an Orca install whose `/usr/bin/orca` is the screen reader.                                                                                                          |
| Linux (Ubuntu, Orca 1.4.224), after the review fixes | bash 5.3           | One full cycle with a handoff: one tab, `prompt_seen`, `remove --dry-run` left it in place, an untracked file blocked `remove`, `remove --force` left no worktree, branch or staging branch. |
| macOS, after the review fixes                        | `/bin/bash` 3.2.57 | `bash -n`, and `create` / `remove` dry runs against a registered repo.                                                                                                                       |

The `--environment` and `--host` paths follow Orca's documented flags but were not exercised end to end; no runtimes were paired at the time.

### session-closeout (2026-10-14)

| Platform                                                                                   | What ran                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS (Orca 1.4.224, Claude Code 2.1.300)                                                  | The show form and `--title … --tab-title … --close --dry-run` inside a live Orca terminal: the agent, its shell and the tab were all identified as the session's own. An earlier live run of the same steps (rename records, `orca terminal rename`, delayed `terminal close --tab`) closed only that tab, and the name appeared in Agent Session History                                                         |
| Bun tests under `/bin/bash` 3.2 (stub Orca CLI, throwaway config dir, fake `claude` agent) | 17 tests: records match `/rename`, partial last line, normalisation, length limits (UTF-16 for Orca), dry run, handle-only tab label; refusals before any change (no Orca terminal, no `ORCA_TAB_ID`, another session's tab, no agent found, a background command running); close only after `tui-idle`, by handle, never `--all`; cancelled by a new prompt; cancelled by a background command started meanwhile |

Measured, with the source read: Claude Code's title normaliser cuts at 200 code points (`xI=200` in 2.1.300); Orca's session scanner cuts titles at 96 (93 + an ellipsis) in 1.4.224. The close guard's real-session positive case (a live background command) was not reproduced on the test Mac, where a local hook moves background commands to a job queue; the unit test reproduces the observed process tree.

### session-closeout running-work guard (2026-10-14)

| Platform                                                               | What ran                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| macOS (Orca 1.4.224, Claude Code version not recorded), a live session | Show form and `--close --dry-run` with nothing running (all three checks `ok`, 18 background launches reconciled to 0), and with a background probe agent working: found by Orca's status record (`subagent … working`) and by the process tree (its running Bash command). A real naming run marked the tab `[running] …` and the workspace (status, and the comment prefixed because one existed). The live watcher's removal of those markers can only happen after the session's turn ends; it has not yet been observed live, only in the unit tests                |
| Bun tests under `/bin/bash` 3.2                                        | 35 tests. New: transcript ledger (launch without notification, notification, TaskStop, cron + CronDelete, wake-up due/stop), Orca status record (working vs idle/done subagents, shell/monitor flag, wake-up flag, another session's record, unreadable record), deferred close (waits for a subagent and a settled row, gives up after `--settle-timeout` with the unread dot, `--force`, a task notification is not a prompt, the agent process gone), markers (set, restored, never a new comment, not when another tab shares the workspace), a relative script path |

### session-closeout review fixes (2026-10-21, #30)

| Platform                                                                           | What ran                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bun tests under `/bin/bash` 3.2, macOS (Orca 1.4.235 CLI help read, no live calls) | 49 tests, also run by `moon run repo:check` (its `test` task runs every tracked `*.test.ts`). New: a hung `orca terminal show` refuses `--close`; a hung `orca worktree ps` keeps the tab open until `--settle-timeout`; a hung `lsof` reads as a running background command; a hung `ps` makes the process check unreadable; markers removed when the agent is gone, when the tab changed, when Orca never reports the turn idle, on give-up and before a close; an unlabelled tab reset by omitting `--title`; a workspace with no status or comment left unmarked; no nested `Running:` prefix on a second run (state file, or a leftover prefix); the agent start time read under `fr_FR`; an image prompt cancels the close; a tool result and a list-form task notification do not |

`orca terminal rename --help` (1.4.235): "Omit --title or pass an empty string to reset to the auto-generated title." The restore omits `--title`, the documented form that does not depend on how an empty value is parsed. `orca worktree set --help` lists no way to clear `--workspace-status` (only the link flags take `null`), so a workspace without a status is never given one.

Found live, fixed: the watcher was started by a relative `$0` after changing directory to `/`, so a close requested as `./orca-closeout` silently never happened (also in the earlier closer). Orca's CLI ignores an empty `--comment` (`getOptionalStringFlag`, `src/cli/flags.ts`), so a workspace comment cannot be cleared: the guard only ever prefixes an existing one.

### floating-terminal (2026-10-24)

| Platform | What ran |
| --- | --- |
| macOS (Orca 1.4.2xx), `/bin/bash` 3.2 | Live: `doctor` (probe landed in `global-floating-terminal`, closed); a command exiting 7 returned `exit_code 7` with the tab kept; a quoted argument (`a b`, a newline, `$d`) arrived intact and the tab closed on success; a password-manager CLI sign-in that fails from the agent's own process succeeded in the floating terminal. |
| Linux (Ubuntu 26.04, Orca 1.4.224), over SSH as a user with no Orca running | The first version missed Orca entirely: on Linux the CLI is `orca-ide` (`/opt/Orca/resources/bin/orca-ide`, linked into `PATH`), not `orca`. Fixed, `doctor` found `/usr/bin/orca-ide` and reported Orca's own `runtime_unavailable` reason (no Orca app for that user), exit 1, with no traceback. |
| Bun tests under `/bin/bash` 3.2 (stub Orca CLI) | 14 tests: real exit code, close by handle only on success, `--keep`, the floating worktree, timeout, dry run, `doctor` positive and negative, the Linux `orca-ide` name found on `PATH`, Orca's own refusal surfaced, no Orca (exit 3), usage errors. |

Not yet run on Linux with Orca running for the same user: a full `run` there, including the util-linux `script` branch, is covered only by reading.
