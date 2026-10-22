---
name: worktree-spinoff
description: Spin a task off the default branch into its own Orca IDE worktree with exactly one agent terminal (Orca's built-in launcher, started with a handoff prompt), the handoff file already committed in the branch, and a readable sidebar entry; target this machine or any paired Orca runtime; remove it cleanly afterwards. TRIGGERS - spin off, new worktree, Orca worktree, handoff, hand over, work there instead, separate concerns, parallel task.
allowed-tools: Bash, Read, Write
---

# Worktree spin-off (Orca IDE)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, Orca's CLI changed, or a workaround was needed: fix this file and the script immediately, don't defer. Only update for real, reproducible issues.

Use this when a task should continue in its own Orca worktree, with its own branch, sidebar entry and agent session, instead of in the current one. One command, [`scripts/orca-spinoff`](./scripts/orca-spinoff), does the whole spin-off and the clean removal. It follows Orca's bundled `orca-cli` guide (`orca skills get orca-cli`) and keeps to Orca's native model: worktrees, the built-in agent launcher, repos and projects, hosts, and paired runtimes. Everything here was observed on Orca 1.4.22x on Linux and macOS.

## Assumptions

- **Orca IDE manages the agents.** You drive Claude Code (or another TUI agent Orca knows: `codex`, `gemini`, …) through Orca's CLI and GUI, locally and on other devices through paired runtimes.
- **The toolchain comes from Nix.** One Nix profile gives the same current `bash`, `git`, `python3` and coreutils on macOS, Linux and BSD, so the same commands behave the same everywhere. The script also runs on stock macOS (`/bin/bash` 3.2, BSD userland) because it uses no GNU-only flags. It needs `bash ≥ 3.2`, `git ≥ 2.20`, `python3 ≥ 3.9` and the Orca IDE CLI.
- **The repository is registered in Orca on the target runtime** (`orca repo add --path <checkout>`), and its remote is reachable from the machine where you run the script.

## Use

```bash
SPIN=<this skill's directory>/scripts/orca-spinoff     # e.g. from the plugin cache
"$SPIN" create --name my-task --title "My task (issue #12)" \
  --handoff ./handoff.md --display "My task: readable name" \
  [--issue 12] [--comment "status"] [--link .venv] [--setup skip] [--dry-run]
"$SPIN" remove --name my-task [--delete-remote-branch] [--force] [--dry-run]
```

- **`--title`:** the prompt's first line. Orca labels the agent's row in the sidebar with it, so keep it short and specific.
- **`--handoff FILE`:** committed as `docs/handoff/<file>` (`--handoff-dir`) before the agent starts. The default prompt tells the agent to read it first; `--prompt-file` replaces the prompt body.
- **`--link PATH`:** symlinks a path of the main checkout into the worktree, for things that are not in git: `.venv`, `node_modules`, `.env`.
- **`--handoff` and `--prompt-file`:** relative paths are relative to your current directory, also inside a linked worktree.
- **Base:** with a handoff, the remote's default branch (or `--base`). Without a handoff or `--base`, the script omits `--base-branch`, so Orca uses the repo's default base, as Orca's `orca-cli` guide asks for independent top-level handoffs.
- **`--dry-run`:** for `create` and `remove`, runs every check (repo, remote, base, collisions, leftovers, unsaved work), prints the plan, and changes no branch or worktree. It may still `git fetch`.
- **Output:** stdout is one JSON line, `{"worktree", "path", "branch", "terminal", "terminals", "setup_tabs", "prompt_seen"}` (`terminals` is `null` if Orca could not list them); progress and warnings go to stderr. The handoff is complete when `prompt_seen` is true. Report the worktree and terminal to the user; do not wait for the new agent to finish.

### Other devices (Orca-native targeting)

| Goal                                                  | Flags                                           | Notes                                                                                                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This machine                                          | none                                            | Uses the repo registered at this checkout's path                                                                                                                                                                                                                                                                                                              |
| A paired Orca runtime (another computer running Orca) | `--environment <id>` or `--pairing-code <code>` | `orca environment list` shows the ids; pair once with `orca environment add --name <n> --pairing-code <code>`. The repo is matched by its remote's `owner/repo`, because paths and SSH aliases differ per machine (an SSH-alias host on one side and `github.com` on the other do not match: pass `--repo-id`). The agent starts differently there; see below |
| A host of a project (`ssh:<id>`, `runtime:<id>`)      | `--host <host>`                                 | `orca host list`. Uses `--project` (resolved from the repo) instead of `--repo`, as Orca requires                                                                                                                                                                                                                                                             |
| Ambiguous match                                       | `--repo-id <id>`                                | From `orca repo list --json` on the target                                                                                                                                                                                                                                                                                                                    |

The handoff is staged on the forge (`handoff/<name>`, deleted after creation), so it reaches any device that can fetch the repository. On a paired runtime the base is named with that clone's own remote (Orca's `gitRemoteIdentity.remoteName`), and `orca repo search-refs` must find it there first; if that clone has not fetched yet, the script stops and removes the staging branch. Whether a worktree is on this machine is decided from Orca's data (`--environment`, or the row's `hostId`), never from whether its path exists here: two machines with the same user name have the same workspace paths. `--link` applies only when the worktree is on this machine. `remove` on another runtime or host removes the worktree there and leaves that machine's local branch for you to delete there. `remove --host` picks among same-named worktrees on several hosts.

**On a paired runtime the built-in launcher is refused**, so the agent is started in the worktree's own shell tab instead. `worktree create --agent` and `agent launch` against a runtime reached with `--environment` both fail with `agent_launch_replay_unsupported` (measured with the Orca 1.4.235 and 1.4.237 CLIs against a 1.4.237 runtime: the CLI does not advertise `agent.launch.v2` to a remote runtime, which that call requires). The script then creates the worktree bare, types `<agent> '<prompt>'` into the one shell tab Orca opens there (`terminal send`, so there is still a single tab), and titles it after the agent. Three differences follow: the remote Orca's `agentDefaultArgs` are not applied (a shell alias or wrapper still is, since it is that machine's interactive shell); the prompt cannot be read back from the tab, so `prompt_seen` is `false` and the script says so instead of waiting; and Claude Code asks its folder-trust question unless that machine already trusts the repository (see the pitfalls).

## Why each step (observed, not assumed)

- **One terminal.**
  - `orca worktree create --agent <id> --prompt …` is the only path to a single agent tab.
  - Orca's launcher starts the agent with your configured default arguments (`settings.agentDefaultArgs`) in a login shell, so aliases and wrappers apply. It titles the tab after the agent, attaches Orca's agent-status hooks, and submits the prompt at launch: no wait-then-send race.
  - A bare `worktree create` opens a fallback shell; adding the agent later with `terminal create --command …` gives two tabs, a raw command as the title, and a prompt that is lost if sent before the TUI is ready.
- **Setup tab.** When the repo defines a setup script and Orca runs setup in a new tab (`settings.setupScriptLaunchMode = new-tab`), a second tab titled "Setup" appears beside the agent's. The script counts it separately (`setup_tabs`). Use `--setup skip` for a single tab when the agent can run setup itself.
- **Handoff before launch.** The handoff is committed on `handoff/<name>` from a temporary worktree outside Orca, and pushed. Orca creates the worktree from that ref; the staging branch is then deleted (the new branch contains it). The branch's recorded base (`branch.<b>.base`) is reset to the real base. If any step fails, a trap removes the staging branch and the temporary worktree.
- **Branch name.** With `settings.branchPrefix = git-username`, Orca names the branch `<forge login>/<name>`. The prefix follows the live remote: a forge Orca does not recognise gives a plain `<name>`. Tell the agent its real branch (`git branch --show-current`) if the handoff names another.
- **Display name.** `worktree create` has no display-name flag, so the script follows with `orca worktree set --display-name`.
- **Lineage and focus.** `--no-parent` by default, so the task is a top-level entry and an independent concern. Pass `--parent active` for stacked work. `--activate` is off by default, so your current view is not switched; the new entry appears in the sidebar at once.
- **Removal.** `orca worktree rm` is asynchronous (`removing: true`), so the script waits for the folder to disappear. Orca deletes the branch only when it equals the worktree name, so the script deletes a prefixed branch itself. Without `--force` it refuses if there are uncommitted changes, untracked files (other than the links it made), or commits on no remote branch. Ignored files (`.venv`, build output) are deleted with the folder. The main worktree is never matched, and names are checked against Orca's complete listing (`--repo`, no truncation; hosts it could not reach are reported).

## Pitfalls found on real machines

- **`orca` may not be Orca.** On Linux desktops, `/usr/bin/orca` is often the GNOME screen reader. The script uses `$ORCA_CLI` if set, else an `orca` whose help mentions `worktree create`, else the IDE's own CLI: `~/.config/orca/linux-orca-cli-shim/orca` on Linux, `/Applications/Orca.app/Contents/Resources/bin/orca` on macOS.
- **A broken macOS CLI link.** If `orca` fails with "Unable to determine Orca.app path from symlink", the link it runs is unreadable (for example a root-owned `/usr/local/bin/orca` with mode `lrwx------`). Without sudo, a user-owned link earlier on `PATH` fixes it: `ln -s /Applications/Orca.app/Contents/Resources/bin/orca ~/.local/bin/orca`.
- **Forge features need a real host in the remote URL.** Orca treats a remote host without a dot (`git@work-alias:owner/repo`) as an unresolved SSH alias, or as a self-hosted forge called by that name. Its tasks, PR links and branch prefix then stay off or fail. Keep the real host in the URL and pin the key per repository: `git config core.sshCommand 'ssh -i ~/.ssh/<key> -o IdentitiesOnly=yes'`.
- **Orca caches the remote identity.** It probes the remote when the repo is added (`orca repo show` → `gitRemoteIdentity`, `orca project list` → `providerIdentity`). A corrected URL takes effect after an Orca restart, at a moment when no agent session is mid-task.
- **Claude Code's folder trust is per repository root, not inherited from a parent folder.** A worktree of a repository whose root is not trusted on that machine stops at "Is this a project you created or one you trust?", even when a parent folder such as `~/orca/workspaces` is trusted (measured 2026-10-22). Orca's own launcher passes trust for you; on the paired-runtime route, trust the repository root once on that machine (`~/.claude.json` → `projects.<repo root>.hasTrustDialogAccepted`, or answer the question once). The same machine also asks "Do you want to use this API key?" when a key in the environment is not in `customApiKeyResponses.approved`; never answer that one blind, because the default is No.
- **Removing a repository or deleting its folder leaves its terminal tabs open.** After a repo was removed from Orca (`orca repo list` empty, `orca worktree list` empty) and its folders deleted, `orca terminal list` still returned its tabs, the sidebar showed them under "Unknown", and their shells sat in the deleted folder. Starting Claude Code in one fails with "The current working directory was deleted" (measured 2026-10-22, on a paired runtime). Once the worktree is gone, `orca terminal close --worktree … --all` returns `selector_not_found`, so close each tab by handle: `orca terminal close --terminal <handle> --tab`. Clean up in this order: tabs first, then the worktree (`remove` above), then the repo.
- **Sign-in waits on the keyring.** Orca's forge sign-in reads the system keyring. A locked keyring (on Linux, an "Unlock Login Keyring" dialog) leaves the sidebar on "Refreshing sign-in" and forge views empty.

## Continuing and checking

- **The new worktree runs a new agent session.** Sessions are filed per folder. Continuity comes from the committed handoff and the repository, so put the previous session's transcript path in the handoff if details may be needed.
- **Talking to the agent:**
  - message it: `orca terminal send --terminal <handle> --text "…" --enter`;
  - read it: `orca terminal read --terminal <handle> --cursor 0 --json`;
  - pause it: put the workspace to Sleep. `orca terminal close --all` deletes resume records.
- **Visual check (optional):** take a screenshot and read it.
  - Wayland: `grim -s 0.6 shot.png`.
  - X11: `import -window root shot.png`.
  - macOS: `screencapture -x shot.png`.

  Expect the display name in bold, the branch below it, and one agent row labelled with the prompt's title.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** If not, fix the instruction, the script or the pitfall list that caused the failure.
2. **Did Orca's CLI or output change?** If a flag, a JSON field or a default drifted (`orca worktree create --help`, `orca skills get orca-cli`), update the script and the tables here to match.
3. **Was a workaround needed?** If you had to improvise (extra flags, manual cleanup, another platform's quirk), fold it into the script or the pitfalls so the next run does not need it.

Only update if the issue is real and reproducible, not speculative.
