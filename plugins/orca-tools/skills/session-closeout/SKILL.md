---
name: session-closeout
description: Close out a Claude Code session running in an Orca IDE terminal so it can be found and resumed later - give it a recall name (the same records /rename writes, sized to what Claude Code and Orca's Agent Session History actually display), end on a compact handoff, and either keep the terminal or close only this session's own tab to free memory. TRIGGERS - close out, wrap up, end the session, rename the session, name this session, close the terminal, free memory, handoff note, resume later, session title.
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
"$CLOSE"                                              # show: session, transcript, current name, terminal, resume command
"$CLOSE" --title "Area: outcome, state (dates)" [--tab-title "Short label"] [--dry-run]
"$CLOSE" --title "…" --close [--min-wait 5] [--force] [--dry-run]
```

- Run it from **inside** the session being closed (Claude Code's Bash tool): it identifies the session from `CLAUDE_CODE_SESSION_ID` and the terminal from Orca's `ORCA_TERMINAL_HANDLE`.
- stdout is one JSON object: `session`, `transcript`, `title`, `title_length`, `named`, `terminal`, `tab_labelled`, `close_scheduled`, `closer_pid`, `close_log`, `resume`. Exit 2 means it refused before changing anything.
- With `--close`, the tab closes only **after your turn ends**: a detached closer waits for Orca's own idle signal (`orca terminal wait --for tui-idle`), so your final message is delivered and saved first. Make that message the handoff (below). If the user types a new prompt before then, the close is cancelled.

## Name length (measured in the shipping code)

| Where the name is shown                           | Limit                                  | Behaviour past it                                                           |
| ------------------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------- |
| Claude Code (`/resume`, prompt bar, stored title) | **200** characters (code points) | Silently cut; control characters removed |
| Orca **Agent Session History** | **96** characters (UTF-16 units: an emoji counts 2) | First 93 + an ellipsis; runs of whitespace collapse to one space |
| Claude Code's `/resume` picker row                | the terminal's width                   | Cut at the right edge                                                       |
| An Orca terminal tab                              | roughly 25 characters at default width | Cut at the right edge                                                       |

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

1. **Check for unfinished work.** Background commands still running? Drafts or messages not sent? Uncommitted changes the user expects pushed? Finish them or list them under **Open**. The script refuses `--close` while one of the agent's own Bash-tool commands is still running (closing would kill it), and checks again just before closing; `--force` overrides.
2. **Retire the session's own subagents and teammates.** Run `ListAgents`: every subagent or named teammate this session spawned stays listed under the session in Orca's sidebar (idle for hours) until it is stopped. For each one whose result is already used, stop it with `TaskStop` (pass its name); one still working is either waited for or listed under **Open**. Leave **peer sessions** alone: they are other people's or other tasks' sessions, not this session's children. The script cannot do this step: in-process teammates are not separate processes, so its background-command guard never sees them.
3. **Choose the name** (rules above). Run `"$CLOSE"` first to see any existing name.
4. **Name, and close if asked:** `"$CLOSE" --title "…" [--tab-title "…"] [--close]`. Use `--dry-run` first if unsure.
5. **Write the Closeout block as your final message**, using `resume` from the script's JSON.

## Why each step (observed, not assumed)

- **Naming writes the records `/rename` writes.** Claude Code's `/rename` appends two lines to the session transcript (`~/.claude/projects/<folder>/<session>.jsonl`, or under `$CLAUDE_CONFIG_DIR`): `{"type":"custom-title","customTitle":…,"sessionId":…}` and `{"type":"agent-name","agentName":…,"sessionId":…}`. An agent cannot type a slash command, and there is no CLI flag for renaming a running session, so the script appends the same two lines. It appends in one write and never onto a partial last line, then re-reads the file's tail to confirm. Orca's Agent Session History reads `custom-title` as the name (`agent-name` is its fallback). Claude Code re-appends the current name as the session continues, so the name stays near the end of the file, where the `/resume` list looks for it.
- **The terminal is always named by handle.** Orca's guide: `--terminal` "is optional for most commands; omitted means the active terminal in the current worktree". The active terminal can be another session's. The script passes `ORCA_TERMINAL_HANDLE` every time, and before closing confirms with `orca terminal show` that the handle's tab is this session's `ORCA_TAB_ID`.
- **`--tab`, not `--all`.** `orca terminal close --terminal <handle> --tab` closes this session's tab only. `--worktree … --all` closes every terminal in the workspace and "durably removes its terminal tabs, layouts, and agent-resume records".
- **Closed when idle, re-checked, detached.** Closing the tab ends the agent, so a fixed timer could cut off the final message. The closer is double-forked into its own session (it survives the tool call and an interrupt), waits at least `--min-wait` seconds, then waits for Orca's `tui-idle`, the signal Orca's guide uses for "the agent's turn is over" (up to 10 minutes; otherwise it does not close). Before closing it checks again: the tab is still this session's, no new user prompt arrived, and no background command started meanwhile. Its output goes to `close_log`.
- **What the close guard counts, and why it fails closed.** Claude Code runs each Bash-tool command in a shell that first sources a `shell-snapshots/…` file. A still-running one (other than the one running the script) is a background command the close would kill. The agent's MCP servers, status-line scripts and helpers are not counted: they come back when the session resumes. If the script cannot find its agent (the nearest `claude` process above it) or its own snapshot-marked shell, it cannot rule background work out, so it refuses unless `--force`. It also refuses without `ORCA_TAB_ID`: the tab check needs it.
- **Resume from the starting folder.** Claude Code files a session under the folder it started in, and its `/resume` list shows only sessions of the current folder. The script reads the starting folder from the transcript, so the printed command works even after the session moved to another directory or worktree.

## Pitfalls

- **The name does not appear in `/resume`.** Run `/resume` from the session's starting folder, or resume by id. Long-standing Claude Code bugs can hide renamed sessions from the picker ([#96559](https://github.com/anthropics/claude-code/issues/96559), [#36077](https://github.com/anthropics/claude-code/issues/36077)); resuming by id always works.
- **A later `/rename` wins.** The newest `custom-title` record is the name. That is intended: the user can always override.
- **`orca` may not be Orca.** On Linux desktops `/usr/bin/orca` is often the GNOME screen reader. The script uses `$ORCA_CLI`, then Orca's own `ORCA_CLI_BIN_DIR`, then an `orca` whose help lists terminal commands.
- **Outside Orca** (plain terminal, another IDE): naming still works; `--tab-title` and `--close` refuse.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** If not, fix the instruction, the script or the pitfall that caused the failure.
2. **Did a limit or format drift?** If Orca's history cut a name of 96 or fewer characters, if `/rename` began writing other records, or if an `orca terminal` flag changed (`orca terminal close --help`, `orca skills get orca-cli`), update the script, its tests and the tables here.
3. **Was a workaround needed?** Fold it into the script or the pitfalls so the next run does not need it.

Only update if the issue is real and reproducible, not speculative.
