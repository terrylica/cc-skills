# orca-tools Plugin

> Claude Code under the Orca IDE: worktree spin-offs with one agent terminal, locally and on paired runtimes; session closeout with a recall name, a handoff, and an optional close of the session's own tab.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [git-town-workflow CLAUDE.md](../git-town-workflow/CLAUDE.md)

## Skills

- [worktree-spinoff](./skills/worktree-spinoff/SKILL.md)
- [session-closeout](./skills/session-closeout/SKILL.md)

## Invariants

- **One agent tab.** A spin-off is created with `orca worktree create --agent <id> --prompt …`. Never add the agent afterwards with `terminal create`: that leaves Orca's fallback shell as a second tab.
- **Every `orca` call goes through `o()`.** It carries `--environment` / `--pairing-code`, so the same script targets this machine or a paired runtime. Keep new calls inside it.
- **Find the IDE's CLI with `find_orca`.** On Linux desktops `/usr/bin/orca` is often the GNOME screen reader, so never call a bare `orca`.
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

| Platform                                                  | What ran                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| macOS (Orca 1.4.224, Claude Code 2.1.3xx), a live session | Show form and `--close --dry-run` with nothing running (all three checks `ok`, 18 background launches reconciled to 0), and with a background probe agent working: found by Orca's status record (`subagent … working`) and by the process tree (its running Bash command). A real naming run marked the tab `[running] …` and the workspace (status, and the comment prefixed because one existed). The live watcher's removal of those markers can only happen after the session's turn ends, so it is checked from outside the session (result in the PR)             |
| Bun tests under `/bin/bash` 3.2                           | 35 tests. New: transcript ledger (launch without notification, notification, TaskStop, cron + CronDelete, wake-up due/stop), Orca status record (working vs idle/done subagents, shell/monitor flag, wake-up flag, another session's record, unreadable record), deferred close (waits for a subagent and a settled row, gives up after `--settle-timeout` with the unread dot, `--force`, a task notification is not a prompt, the agent process gone), markers (set, restored, never a new comment, not when another tab shares the workspace), a relative script path |

Found live, fixed: the watcher was started by a relative `$0` after changing directory to `/`, so a close requested as `./orca-closeout` silently never happened (also in the earlier closer). Orca's CLI ignores an empty `--comment` (`getOptionalStringFlag`, `src/cli/flags.ts`), so a workspace comment cannot be cleared: the guard only ever prefixes an existing one.

## Recent changes

- 2026-10-14: `session-closeout` never leaves running work behind: every form reports what the session started that is still running (process tree, transcript ledger, Orca's per-tab status record); `--close` no longer refuses on running work but defers until it has finished and Orca's row has settled (`--settle-timeout`, default 30 min), marking the tab `[running] …` and, when it is the workspace's only agent session, the workspace status meanwhile; naming alone starts a watcher that removes the markers. Fixes: the old closer trusted `tui-idle`, which ends while subagents still run; it skipped its re-check when the agent pid was gone; a relative script path broke the detached closer.

- 2026-10-14: `session-closeout` skill and `orca-closeout` script: recall name (the two records `/rename` writes, held to Orca's 96-character history limit and Claude Code's 200), tab label, and a guarded, delayed close of the session's own tab; 17 Bun tests; an independent review's eleven findings fixed (fail-closed guard, required tab id, close on idle instead of a timer, re-check at close time, setsid detach). `orca-spinoff`: `is_orca` no longer pipes `--help` into `grep -q`.
- 2026-10-13: review fixes: `remove --dry-run`, main worktree excluded, untracked files guarded, caller-relative paths, Orca-native local/remote and base handling, complete listings, forge host in repo matching, JSON output.
- 2026-10-13: plugin created from a project-local skill, made agnostic and portable.
