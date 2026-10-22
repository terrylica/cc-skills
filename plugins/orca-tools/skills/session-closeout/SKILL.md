---
name: session-closeout
description: Close out a Claude Code session running in an Orca IDE terminal so it can be found and resumed later - give it a recall name (the same records /rename writes, sized to what Claude Code and Orca's Agent Session History actually display), end on a compact handoff, and either keep the terminal or close only this session's own tab to free memory, never while subagents, teammates, background commands, monitors or scheduled wake-ups it started are still running (the close waits for them, and the tab and workspace are marked as running meanwhile). TRIGGERS - close out, wrap up, end the session, rename the session, name this session, close the terminal, free memory, handoff note, resume later, session title.
allowed-tools: Bash, Read
---

# Session closeout (Orca IDE + Claude Code)

> **Self-Evolving Skill**: This skill improves through use. If a limit, a record format or an Orca flag changed, or a workaround was needed: fix this file and the script immediately, don't defer. Only update for real, reproducible issues.

Use this at the end of a working session, when the user wants it **findable later** (a recall name), **understandable later** (a handoff), and possibly **gone now** (its terminal closed to free memory). Naming and closing are independent: name without closing, or name and close. One command, [`scripts/orca-closeout`](./scripts/orca-closeout), does both, safely. It follows Orca's bundled guide (`orca skills get orca-cli`) and Claude Code's own session records.

## Decide first: keep, close, or sleep

| The user wants                                            | Do                                                                   | What survives                                                                                                                                                                        |
| --------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A name only; keep working or keep the tab                 | `orca-closeout --title "…"`                                          | Everything                                                                                                                                                                           |
| This session's terminal gone, to free memory              | `orca-closeout --title "…" --close`                                  | The transcript. Resume with the printed `claude --resume <id>`, or from Orca's Agent Session History                                                                                 |
| The **whole workspace** paused, to resume later as it was | Name it, then ask the user to put the workspace to **Sleep** in Orca | Every terminal and agent session in it. Orca's guide: "Use workspace Sleep, not close, when the terminals and agent sessions should resume later". There is no CLI command for Sleep |

Never use `orca terminal close --worktree … --all` here: it closes every terminal in the workspace, other sessions' included, and deletes their resume records.

## Use

```bash
CLOSE=<this skill's directory>/scripts/orca-closeout   # e.g. resolved from the plugin cache
"$CLOSE"                                              # show: session, name, terminal, running work, resume command
"$CLOSE" --title "Area: outcome, state (dates)" [--tab-title "Short label"] [--dry-run]
"$CLOSE" --title "…" --close [--min-wait 5] [--settle-timeout 1800] [--force] [--dry-run]
```

- Run it from **inside** the session being closed (Claude Code's Bash tool): it identifies the session from `CLAUDE_CODE_SESSION_ID` and the terminal from Orca's `ORCA_TERMINAL_HANDLE`.
- stdout is one JSON object: `session`, `transcript`, `title`, `title_length`, `named`, `terminal`, `tab_labelled`, `running` (each item: `kind`, `id`, `name`, `state`, `source`), `running_count`, `checks` (per source: `ok`, or why it is unusable), `marked` (`tab`, `workspace`), `close_scheduled`, `close_deferred`, `watcher_pid`, `close_log`, `resume`. Exit 2 means it refused before changing anything.
- **Every form reports running work**, so the handoff can list it under **Open**. With `--close` it does not refuse because of running work: the close waits for it (below).
- With `--close`, the tab closes only **after your turn ends and everything this session started has finished**: a detached watcher waits for Orca's idle signal (`orca terminal wait --for tui-idle`), so your final message is delivered and saved first, and then until nothing is running (at most `--settle-timeout` seconds). Make that final message the handoff (below). If the user types a new prompt before then, the close is cancelled. If the work never finishes in time, the tab stays open, the markers are removed, and the workspace gets its unread dot.

## Running work: what counts, and what the user sees

A session can start work that outlives its turn: subagents and background agents, agent-team teammates, Workflow runs, background commands, monitors, session-only crons, `/loop` and other scheduled wake-ups. Closing the tab kills or loses all of it, and while it runs, Orca's sidebar row for the tab stays `working` even after the main turn ended. So that row is never left looking unfinished without a reason, the script:

| Situation                 | What happens                                                                                                                                                                                                                       |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nothing running           | Name; with `--close`, the tab closes after the turn ends                                                                                                                                                                           |
| Work running, naming only | Name; the tab title gets a `[running]` prefix; a watcher removes it once the work has finished                                                                                                                                     |
| Work running, `--close`   | Name and mark the same way; the watcher waits for the work, removes the markers, then closes. After `--settle-timeout` it gives up: the tab stays open, the markers are removed, and the workspace's unread dot asks for attention |
| A source cannot be read   | `--close` refuses (exit 2) unless `--force`; naming still works and reports the check                                                                                                                                              |
| `--force`                 | Close as soon as the turn ends; running work is killed with the tab; nothing is marked                                                                                                                                             |

**The workspace is marked only when this is its only agent session** (its status, comment and unread dot are shared by every tab in it), and **each field only when it already has a value**, because Orca cannot clear either one again: status `in-progress` (there is no flag to unset a workspace status), and the comment prefixed with `Running: … |` (Orca's CLI ignores an empty `--comment`). Both are restored exactly. A second run while the first one's markers are still on reads the originals from the first run's state file, so the prefix is never nested and `in-progress` is never recorded as the value to restore.

**The markers come off however the watcher ends**: settled, `--settle-timeout`, the agent process gone, the tab no longer this session's, Orca never reporting the turn idle, or a signal. A tab that had no label of ours is reset by `orca terminal rename` without `--title` (its help: "Omit --title or pass an empty string to reset to the auto-generated title").

**Three sources, combined; any one finding running work is enough.**

1. **The agent's process tree**: Bash-tool shells still running under the session's `claude` process (background commands, a subagent mid-command).
2. **The transcript ledger**: every background command (`backgroundTaskId`) and background agent launched, minus those with a `<task-notification>` or a `TaskStop` result; session-only `CronCreate` jobs without a `CronDelete`; the latest `ScheduleWakeup` while not yet due. Launches older than the current agent process are ignored: they died with an earlier one.
3. **Orca's status record for this tab** (`<Orca user data>/agent-hooks/last-status.json`, used only when its session id and process id are this session's): subagents and teammates not `idle` or `done`, a running shell or monitor (`claudeRunningNonAgentTask`), a pending task wake-up (`claudeTaskWakeupPending`).

After the turn ends, the watcher also needs **Orca's own row** (`orca worktree ps`) for this tab at state `done` with no working mode: that row folds in everything above plus session crons, and is exactly what the user sees. Subagents and teammates run inside the one `claude` process, so no process check alone can see them; and Orca's `tui-idle` reads only the main turn ("a lead turn that ended reads done even while a subagent runs"), so it cannot be the settle signal by itself.

## Name length (measured in the shipping code)

| Where the name is shown                           | Limit                                               | Behaviour past it                                                |
| ------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------- |
| Claude Code (`/resume`, prompt bar, stored title) | **200** characters (code points)                    | Silently cut; control characters removed                         |
| Orca **Agent Session History**                    | **96** characters (UTF-16 units: an emoji counts 2) | First 93 + an ellipsis; runs of whitespace collapse to one space |
| Claude Code's `/resume` picker row                | the terminal's width                                | Cut at the right edge                                            |
| An Orca terminal tab                              | roughly 25 characters at default width              | Cut at the right edge                                            |

So: **at most 96 characters**, with the words that tell this session apart in the **first 25-30**. The script refuses 97+ unless `--allow-long` (up to 200), and always refuses 201+. Pass a shorter `--tab-title` when the full name would be cut in the tab.

A good name: `<area>: <what was done> - <state> (<date or range>)`, for example `billing-api: retry queue + idempotency keys - merged, deploy pending (Mar 3-4)`. Lead with the area, use the words you would search for, and include the state. **Never put secrets or personal details in a name:** names are indexed for search, shown in lists, and visible on paired devices.

## The handoff: minimal output, maximum context

The session's **last message** is what a person sees first: Orca's Agent Session History shows it on the session's card, and `claude --resume` reopens at it. End with this block and nothing after it:

```text
Closeout - <the session name>
Done:  <outcomes, each with its proof: commit, PR, release, file path>
Open:  <unfinished items, each with its owner: you / the agent / someone named>
Next:  <the single next action, and what it waits on>
Resume: claude --resume <id>   (from <starting folder>; or Agent Session History)
```

- **Outcomes, not activity.** "Released v2.3.0; tests pass (PR #41)", not "worked on the release".
- **Pointers, not copies.** Name the durable record (commit, PR, issue, doc); the transcript holds the detail.
- **Say what is NOT done**, and who owns it. A resumed session's first risk is assuming something finished.
- **Ten lines or fewer.** If it needs more, the detail belongs in a committed doc or an issue, linked from here.

To make every session close out this way without asking, add this to the user-level `~/.claude/CLAUDE.md` (it applies to every project):

```markdown
## Session closeout

When the user says to close out, wrap up or end the session: run the orca-tools `session-closeout` skill.
Pick a name of at most 96 characters (area first, then outcome and state), close the terminal only if asked,
and end with the five-line Closeout block (Done / Open / Next / Resume), nothing after it.
```

## Steps

1. **Check for unfinished work.** Run `"$CLOSE"`: its `running` list is what this session started that has not finished. Wait for it or stop it (`TaskStop`) if it should end now; otherwise list it under **Open**. Also: drafts or messages not sent? Uncommitted changes the user expects pushed? Never pass `--force` just to get the tab closed: it kills that work.
2. **Retire the session's own subagents and teammates.** Run `ListAgents`: every subagent or named teammate this session spawned stays listed under the session in Orca's sidebar (idle for hours) until it is stopped. For each one whose result is already used, stop it with `TaskStop` (pass its name); one still working is either waited for or listed under **Open**. Leave **peer sessions** alone: they are other people's or other tasks' sessions, not this session's children. The script cannot do this step: it can see running subagents and teammates (and the close waits for them), but only the agent itself can stop them, and an idle teammate is not running work, so the script never waits for or retires it.
3. **Choose the name** (rules above). The same `"$CLOSE"` output shows any existing name.
4. **Name, and close if asked:** `"$CLOSE" --title "…" [--tab-title "…"] [--close]`. Use `--dry-run` first if unsure.
5. **Write the Closeout block as your final message**, using `resume` from the script's JSON.

## Why each step (observed, not assumed)

- **Naming writes the records `/rename` writes.** Claude Code's `/rename` appends two lines to the session transcript (`~/.claude/projects/<folder>/<session>.jsonl`, or under `$CLAUDE_CONFIG_DIR`): `{"type":"custom-title","customTitle":…,"sessionId":…}` and `{"type":"agent-name","agentName":…,"sessionId":…}`. An agent cannot type a slash command, and there is no CLI flag for renaming a running session, so the script appends the same two lines. It appends in one write and never onto a partial last line, then re-reads the file's tail to confirm. Orca's Agent Session History reads `custom-title` as the name (`agent-name` is its fallback). Claude Code re-appends the current name as the session continues, so the name stays near the end of the file, where the `/resume` list looks for it.
- **The terminal is always named by handle.** Orca's guide: `--terminal` "is optional for most commands; omitted means the active terminal in the current worktree". The active terminal can be another session's. The script passes `ORCA_TERMINAL_HANDLE` every time, and before closing confirms with `orca terminal show` that the handle's tab is this session's `ORCA_TAB_ID`.
- **`--tab`, not `--all`.** `orca terminal close --terminal <handle> --tab` closes this session's tab only. `--worktree … --all` closes every terminal in the workspace and "durably removes its terminal tabs, layouts, and agent-resume records".
- **Closed when settled, re-checked, detached.** Closing the tab ends the agent, so a fixed timer could cut off the final message or running work. The watcher is double-forked into its own session (it survives the tool call and an interrupt; the script path is made absolute first, because it changes directory to `/`), waits at least `--min-wait` seconds, then for Orca's `tui-idle` (up to 10 minutes), then polls every 15 seconds until all sources above are clear. On every poll it checks again: the tab is still this session's, no new user prompt arrived (a prompt with an image or a pasted document counts; a task notification, teammate message or tool result does not), and the agent process still exists (if it is gone, nothing can be confirmed and it stops). Every call it makes (`ps`, `lsof`, the Orca CLI) has a timeout (`ORCA_CLOSEOUT_CALL_TIMEOUT`, default 20 seconds), and a call that times out counts as not settled, never as safe to close. The agent's start time comes from `ps -o etime=`, not the localized `lstart`. Its output goes to `close_log`.
- **Why the guard fails closed.** If the script cannot find its agent (the nearest `claude` process above it) or its own snapshot-marked shell, cannot read the transcript, or finds an Orca status record that is unreadable or belongs to another session or process, it cannot rule running work out, so `--close` refuses unless `--force`. A missing status file or entry is not an error (Orca's hooks may be off): the transcript, the processes and, after the turn, Orca's row still decide. It also refuses without `ORCA_TAB_ID`: the tab check needs it. The agent's MCP servers, status-line scripts and helpers are never counted: they come back when the session resumes.
- **Why not hooks.** Claude Code's `Stop` hook receives `background_tasks` and `session_crons`, the most direct record of running work, but a skill cannot rely on a hook being installed, and `SessionEnd` "can't block session termination". The three sources above need nothing installed.
- **Resume from the starting folder.** Claude Code files a session under the folder it started in, and its `/resume` list shows only sessions of the current folder. The script reads the starting folder from the transcript, so the printed command works even after the session moved to another directory or worktree.

## Pitfalls

- **The name does not appear in `/resume`.** Run `/resume` from the session's starting folder, or resume by id. Long-standing Claude Code bugs can hide renamed sessions from the picker ([#96559](https://github.com/anthropics/claude-code/issues/96559), [#36077](https://github.com/anthropics/claude-code/issues/36077)); resuming by id always works.
- **A later `/rename` wins.** The newest `custom-title` record is the name. That is intended: the user can always override.
- **`orca` may not be Orca.** On Linux desktops `/usr/bin/orca` is often the GNOME screen reader. The script uses `$ORCA_CLI`, then Orca's own `ORCA_CLI_BIN_DIR`, then an `orca` whose help lists terminal commands.
- **Outside Orca** (plain terminal, another IDE): naming still works and running work is still reported (processes and transcript); `--tab-title`, `--close` and the markers need Orca.
- **The watcher cannot be observed from inside the session.** It acts only after the turn ends with nothing running, so a poll, cron or wake-up the session starts to watch it is itself running work and holds it open. Read `close_log` later, or watch it from outside the session.
- **A `/loop` or cron keeps the tab open.** Session crons and pending wake-ups count as running work (Orca shows the row as working between ticks, [stablyai/orca#15137](https://github.com/stablyai/orca/issues/15137)). Stop the loop (`ScheduleWakeup` with `stop`, `CronDelete`) before closing, or the close waits until `--settle-timeout`.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** If not, fix the instruction, the script or the pitfall that caused the failure.
2. **Did a limit or format drift?** If Orca's history cut a name of 96 or fewer characters, if `/rename` began writing other records, or if an `orca terminal` flag changed (`orca terminal close --help`, `orca skills get orca-cli`), update the script, its tests and the tables here.
3. **Was a workaround needed?** Fold it into the script or the pitfalls so the next run does not need it.

Only update if the issue is real and reproducible, not speculative.
