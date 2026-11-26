---
name: session-closeout
description: Close out a Claude Code session running in an Orca IDE terminal or chat so it can be found and resumed later - give it a recall name (the same records /rename writes, sized to what Claude Code and Orca's Agent Session History actually display), end on a compact handoff, and either keep the terminal or close only this session's own tab to free memory, never while subagents, teammates, background commands, monitors or scheduled wake-ups it started are still running (the close waits for them, and the tab and workspace are marked as running meanwhile). TRIGGERS - close out, wrap up, end the session, rename the session, name this session, close the terminal, free memory, handoff note, resume later, session title.
allowed-tools: Bash, Read
---

# Session closeout (Orca IDE + Claude Code)

> **Self-Evolving Skill**: This skill improves through use. If a limit, a record format or an Orca flag changed, or a workaround was needed: fix this file and the script immediately, don't defer. Only update for real, reproducible issues.

Use this at the end of a working session, when the user wants it **findable later** (a recall name), **understandable later** (a handoff), and possibly **gone now** (its terminal closed to free memory). Naming and closing are independent: name without closing, or name and close. One command, [`scripts/orca-closeout`](./scripts/orca-closeout), does both, safely. It follows Orca's bundled guide (`orca skills get orca-cli`) and Claude Code's own session records.

## Decide first: keep, close, or sleep

| The user wants                                             | Do                                                                           | What survives                                                                                                                                                                        |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A name only; keep working or keep the tab                  | `orca-closeout --title "…"`                                                  | Everything                                                                                                                                                                           |
| This session's terminal gone, to free memory               | `orca-closeout --title "…" --close`                                          | The transcript. Resume with the printed `claude --resume <id>`, or from Orca's Agent Session History                                                                                 |
| The **whole workspace** paused, to resume later as it was  | Name it, then ask the user to put the workspace to **Sleep** in Orca         | Every terminal and agent session in it. Orca's guide: "Use workspace Sleep, not close, when the terminals and agent sessions should resume later". There is no CLI command for Sleep |
| The session is an Orca **chat** (GUI tab), named or closed | `orca-closeout --title "…"`, then ask the user to close the chat tab by hand | Everything. The script names the chat with `orca chat rename`; `--close` is refused (exit 2), because Orca's CLI has no command to close a chat (2026-11-11, Orca 1.4.256)           |

Never use `orca terminal close --worktree … --all` here: it closes every terminal in the workspace, other sessions' included, and deletes their resume records.

## Use

```bash
CLOSE=<this skill's directory>/scripts/orca-closeout   # e.g. resolved from the plugin cache
"$CLOSE"                                              # show: session, name, terminal, running work, git, resume command
"$CLOSE" --title "Area: outcome, state (dates)" [--tab-title "Short label"] [--dry-run]
"$CLOSE" --title "…" --close [--min-wait 5] [--settle-timeout 1800] [--force] [--dry-run]
"$CLOSE" --git-path DIR                               # read git from DIR instead of the current directory
```

- Run it from **inside** the session being closed (Claude Code's Bash tool): it identifies the session from `CLAUDE_CODE_SESSION_ID` and the terminal from Orca's `ORCA_TERMINAL_HANDLE`. In an Orca chat (`ORCA_STRUCTURED_SESSION` set) there is no terminal: the label goes to the chat (`orca chat rename --name`, which defaults to the chat it runs in), and `--close` is refused.
- stdout is one JSON object: `session`, `transcript`, `title`, `title_length`, `named`, `terminal`, `surface` (`terminal`, `chat`, or null outside Orca), `tab_labelled` (the terminal tab or the chat), `running` (each item: `kind`, `id`, `name`, `state`, `source`), `running_count`, `checks` (per source: `ok`, or why it is unusable; `checks.git` names every git value that could not be determined), `git` (below), `marked` (`tab`, `workspace`), `close_scheduled`, `close_deferred`, `watcher_pid`, `close_log`, `resume`. Exit 2 means it refused before changing anything (the git report's fetch may have updated remote-tracking refs, nothing else).
- **Every form reports running work**, so the handoff can list it under **Open**. With `--close` it does not refuse because of running work: the close waits for it (below).
- **Every form reports git** for the worktree it runs in, so nobody has to check by hand whether the work was saved and merged. `--close` refuses (exit 2, before changing anything) while that worktree has uncommitted files or unpushed commits, or while either count cannot be read, unless `--force` (below).

## Git: what is reported, and what refuses the close

`git` is `null` outside a repository (`checks.git`: `not a git repository`), and also when git cannot read the repository (dubious ownership, a pruned linked worktree, a corrupt `.git`): then `checks.git` says why and `--close` refuses, because files there may be unsaved. Otherwise it describes the worktree the script runs in (`--git-path DIR` to read another):

| Field            | Meaning                                                                                                                                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `worktree`       | `path` (the toplevel) and `linked` (`true` for a linked worktree, `false` for the main one)                                                                                                                                                                              |
| `branch`, `head` | The branch, `null` on a detached HEAD; the commit                                                                                                                                                                                                                        |
| `upstream`       | `name` and `state` (`up-to-date`, `ahead`, `behind`, `diverged`, or `gone` when the remote branch was deleted), with `ahead` and `behind` counts; `null` when the branch tracks nothing                                                                                  |
| `dirty`          | Uncommitted files, tracked and untracked, ignored ones excluded; a worktree nested inside it is not counted                                                                                                                                                              |
| `unpushed`       | Commits of HEAD on no remote branch (`git rev-list HEAD --not --remotes`). The commits of a merged pull request whose head is HEAD count as pushed. `null` when the repository has no remote                                                                             |
| `merged`         | `true` when HEAD is in the remote default branch, or a merged pull request has HEAD as its head; `false` when `gh` finds no such pull request; `"unknown"` when HEAD is outside the default branch and `gh` is missing or fails; `null` with no remote or a failed fetch |
| `pr`             | The merged pull request whose head is HEAD (`number`, `url`, `head`), when `gh` found one; never one from an earlier use of the same branch name                                                                                                                         |
| `remote`         | The remote read (the upstream's, else `origin`, else the first), its `default_branch` (from `refs/remotes/<remote>/HEAD`, else the remote's own HEAD, else `main` or `master`) and whether the fetch succeeded                                                           |
| `children`       | Every other worktree of the same repository inside this one (for example `.claude/worktrees/*`), each with the fields above and `prunable` (its directory is gone)                                                                                                       |
| `blocks_close`   | What makes `--close` refuse: uncommitted files or unpushed commits of this worktree, or a count that could not be read. Empty when the close may proceed                                                                                                                 |

- **A fetch comes first** (`git fetch --prune` of that one remote, capped by `ORCA_CLOSEOUT_CALL_TIMEOUT` like every call), so `merged` and `gone` are current. It updates only remote-tracking refs, also under `--dry-run`. When it fails or times out, `merged` is `null` and `checks.git` says why.
- **A squash or rebase merge leaves HEAD outside the default branch.** The script then asks `gh pr list --head <branch> --state merged` (`ORCA_CLOSEOUT_GH` names another `gh`, or a missing path to skip it). Without `gh` the answer is `"unknown"`, and such a branch also reads as unpushed once its remote branch is deleted, so the close asks for `--force`: confirm the merge by its pull request first.
- **Why unsaved work refuses the close.** Closing the tab loses no file, but it ends the agent, which is the one actor that knows what those changes were for. A merged branch, or a pushed one that is not merged yet, never refuses; it is only reported. Children never refuse the close either: they are reported for step 2 below.
- **A timeout is unknown, never clean.** A git call that times out leaves its value `null`; a `null` `dirty` or `unpushed` count refuses the close like a real one.
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
Done:  <outcomes, each with its proof: commit, PR, release, file path; "worktree merged (PR …)" when it is>
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

1. **Check for unfinished work.** Run `"$CLOSE"`: its `running` list is what this session started that has not finished. Wait for it or stop it (`TaskStop`) if it should end now; otherwise list it under **Open**. Also: drafts or messages not sent? Never pass `--force` just to get the tab closed: it kills that work.
2. **Check git**, from the same output's `git` object; never by hand.
   - **Uncommitted, unpushed or unmerged work** (`dirty`, `unpushed`, `merged` other than `true`, in this worktree or a child) goes under **Open**, with its owner, unless you commit, push or merge it now. `checks.git` names anything that could not be determined; say so rather than guess.
   - **A merged child worktree this session created** (`children`, created by its own `git worktree add` or `EnterWorktree`) is removed by the session, but only when its entry shows `merged: true`, `dirty: 0` and `unpushed` 0 or `null`: `git worktree remove <path>` (never `--force`), then its local branch (`git branch -d`, or `-D` only when `merged` is `true` through its `pr`), then its remote branch if `upstream.state` is not `gone` (`git push <remote> --delete <branch>`). A child this session did not create belongs to another session: report it, never remove it.
   - **This session's own worktree is never removed from inside the session**: its shell lives there. When it is merged and clean, hand its removal to the user or to the main session, and say so under **Next**.
   - The Closeout block's **Done** line states that the worktree is merged, with the pull request that merged it (`pr.url`, or the commit in `default_branch`).
3. **Retire the session's own subagents and teammates.** Run `ListAgents`: every subagent or named teammate this session spawned stays listed under the session in Orca's sidebar (idle for hours) until it is stopped. For each one whose result is already used, stop it with `TaskStop` (pass its name); one still working is either waited for or listed under **Open**. Leave **peer sessions** alone: they are other people's or other tasks' sessions, not this session's children. The script cannot do this step: it can see running subagents and teammates (and the close waits for them), but only the agent itself can stop them, and an idle teammate is not running work, so the script never waits for or retires it.
4. **Choose the name** (rules above). The same `"$CLOSE"` output shows any existing name.
5. **Name, and close if asked:** `"$CLOSE" --title "…" [--tab-title "…"] [--close]`. Use `--dry-run` first if unsure. A close refused for unsaved git work is lifted by committing and pushing it, or, once it is listed under **Open**, by `--force`.
6. **Write the Closeout block as your final message**, using `resume` from the script's JSON.

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
- **An Orca chat is not a terminal** (measured 2026-11-11, Orca 1.4.255 and 1.4.256). A chat session's environment has `ORCA_STRUCTURED_SESSION`, `ORCA_AGENT_SESSION_ID` and `ORCA_CHAT_SCRATCH_DIR` and no terminal of its own, yet a session that started in a terminal tab can still carry that tab's `ORCA_TERMINAL_HANDLE` after it moved to a chat. Before this fix the script used that stale handle, named the old tab, and its close watcher waited 600 s for `orca terminal wait --for tui-idle`, which a chat never sends, then logged "the agent did not become idle". Now a chat ignores any terminal handle, names itself with `orca chat rename` (`orca skills get orca-cli`: "A chat tab has no terminal handle, so `terminal rename` cannot rename it"), never marks `[running]` (there is no terminal title for a watcher to restore) and refuses `--close` before changing anything. `orca chat --help` lists `rename` as its only command.
- **Outside Orca** (plain terminal, another IDE): naming still works and running work is still reported (processes and transcript); `--tab-title`, `--close` and the markers need Orca.
- **A squash-merged branch reads `merged: "unknown"` without `gh`**, and its commits read as unpushed once the remote branch is deleted, so `--close` refuses. With `gh` signed in, the merged pull request whose head is HEAD settles both. A branch whose last commit came after the merge reads `merged: false` and no `pr`: that commit is unmerged work.
- **The script runs `git` from the current directory.** If the shell moved out of the session's worktree, pass `--git-path`.
- **The watcher cannot be observed from inside the session.** It acts only after the turn ends with nothing running, so a poll, cron or wake-up the session starts to watch it is itself running work and holds it open. Read `close_log` later, or watch it from outside the session.
- **A `/loop` or cron keeps the tab open.** Session crons and pending wake-ups count as running work (Orca shows the row as working between ticks, [stablyai/orca#15137](https://github.com/stablyai/orca/issues/15137)). Stop the loop (`ScheduleWakeup` with `stop`, `CronDelete`) before closing, or the close waits until `--settle-timeout`.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** If not, fix the instruction, the script or the pitfall that caused the failure.
2. **Did a limit or format drift?** If Orca's history cut a name of 96 or fewer characters, if `/rename` began writing other records, or if an `orca terminal` flag changed (`orca terminal close --help`, `orca skills get orca-cli`), update the script, its tests and the tables here.
3. **Was a workaround needed?** Fold it into the script or the pitfalls so the next run does not need it.

Only update if the issue is real and reproducible, not speculative.
