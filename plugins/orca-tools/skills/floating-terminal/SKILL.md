---
name: floating-terminal
description: The default terminal for an AI coding agent running under the Orca IDE (macOS and Linux) - run any command that needs a person or a real TTY (Touch ID, a password manager's desktop-app integration, a passkey, sudo, an interactive prompt, a long visible run) in Orca's own floating terminal through Orca's CLI, and get the command's REAL exit code and output back as JSON. Use instead of opening iTerm, Terminal.app, gnome-terminal or any osascript/open-launched window, and instead of asking the person to paste a command into their shell. TRIGGERS - run this in a terminal, needs Touch ID, needs a TTY, interactive command, op signin, sudo prompt, open a terminal, floating terminal, Orca terminal, run where I can see it, human in the loop command.
allowed-tools: Bash, Read
---

# Floating terminal (Orca IDE)

> **Self-Evolving Skill**: This skill improves through use. If Orca's CLI changed, a measured fact below no longer holds, or a workaround was needed: fix this file and the script immediately, don't defer. Only update for real, reproducible issues.

An agent's own Bash tool has no terminal a person can see or answer, and some tools refuse to run without one: biometric unlock, a password manager's app integration, `sudo`, passkeys, anything that prompts. Under the Orca IDE the answer is **Orca's floating terminal**, driven only through Orca's own CLI: one panel that exists on every Orca desktop, opened and read without any other app. [`scripts/orca-float`](./scripts/orca-float) does it in one call and hands back the result.

## When to use it — the default order

1. **The agent's own Bash tool** for anything non-interactive. It stays the first choice.
2. **`orca-float run`** for anything that needs a person, a TTY, or should stay visible. This is the default terminal for agents under Orca.
3. **Ask the person to run it themselves** only when Orca is absent (`orca-float doctor` exits 3) or its floating terminal is disabled.

Never open iTerm, Terminal.app, gnome-terminal, `osascript … do script`, or `open -a Terminal` for this: those windows are outside Orca, give no exit code back, and leave windows behind.

## Use

```bash
FLOAT="$(cc-plugin-root orca-tools)/skills/floating-terminal/scripts/orca-float"
"$FLOAT" doctor                                        # is the floating terminal usable here? (creates and closes a probe)
"$FLOAT" run --title "Unlock" -- some-cli signin       # runs, waits, returns JSON; the person answers any prompt in the panel
"$FLOAT" run --cwd ~/repo --timeout 600 -- ./script.sh --flag "two words"
"$FLOAT" open --title "Shell"                          # an interactive floating shell for the person; prints its handle
```

| Flag            | Meaning                                                                                          |
| --------------- | ------------------------------------------------------------------------------------------------ |
| `--title T`     | The tab's title (default `agent`). Say what the person is being asked to do.                     |
| `--cwd DIR`     | Directory to run in (default: the current one).                                                  |
| `--timeout SEC` | How long to wait for it to finish (default 1800). A person may take a while to touch a sensor.   |
| `--tail N`      | Lines of output to return (default 40; `0` for none).                                            |
| `--no-log`      | Do not record the output (for a command that prints a secret). The exit code still comes back.   |
| `--keep`        | Keep the tab open even on success. A failed run always keeps its tab, so the person can read it. |
| `--no-focus`    | Create the tab without bringing the panel forward.                                               |
| `--dry-run`     | Print the launcher it would run and create nothing.                                              |

One argument after `--` is run as a shell command line (`-- 'a | b'`); several are quoted word by word.

**Output:** stdout is one JSON object; progress goes to stderr.

```json
{
  "ok": true,
  "state": "finished",
  "exit_code": 0,
  "handle": "term_…",
  "tab_closed": true,
  "seconds": 4,
  "output": "…last lines…"
}
```

`state` is `finished`, `timeout` (still running; the tab stays) or `gone` (the person closed the tab). Exit status: 0 ok, 1 the command failed or did not finish, 2 usage, 3 no Orca CLI found.

**Tell the person before you call it** — "a floating terminal will open and ask for Touch ID" — because the run blocks until they answer or `--timeout` passes.

## Secrets

- A command that **prints** a secret: use `--no-log`, and do not ask for its output. Better, have it write the secret to its destination (a vault, a keychain) itself.
- Never put a secret in the command line: it is written to a temporary script (mode 700 directory, removed after the run) and shown in the panel.
- The output log is the same bytes the panel shows. It is deleted after the run; only `--tail` lines come back.

## How it works, and the measured facts behind it

Measured on Orca 1.4.2xx on macOS:

- `orca terminal create --worktree id:global-floating-terminal --command …` opens a tab in the floating terminal and runs the command in a login shell there. `orca terminal show` reports that tab's `worktreeId` as `global-floating-terminal`; `doctor` checks exactly that.
- **`orca terminal wait --for exit` cannot be trusted for the exit code**: it reported `exitCode 0` (`exitCause host_status_unavailable`) for a command that exited 7. And `orca terminal read` returns nothing once the shell has exited. So the script never relies on either: the command runs under `script` (a real TTY, so prompts and biometric unlock work, and every byte shown is also logged), writes its own exit status to a file, and the script polls that file — at most `--timeout` one-second ticks, checking every 15 s that the tab still exists.
- `script` differs between BSD (macOS) and util-linux; the launcher picks the right form at run time.
- Every `orca terminal` call names its handle. Omitted, Orca uses the active terminal, which may be another session's. Only the tab this run created is ever closed, never with `--all`.

Linux: the same Orca CLI and the same launcher (util-linux `script`). The CLI is found by the plugin's shared finder (`scripts/lib/orca-cli.sh`): `$ORCA_CLI`, `$ORCA_CLI_BIN_DIR/orca`, an `orca` on `PATH` that is really Orca's, then Orca's own install locations. On Linux desktops `/usr/bin/orca` is often the GNOME screen reader, so a bare `orca` is never trusted.

The floating terminal is a local panel: this skill drives the Orca on the machine it runs on, not a paired runtime.

## Requirements

The Orca IDE CLI with the floating terminal enabled in Orca's settings, `bash ≥ 3.2`, `python3 ≥ 3.9`, and `script` (present on macOS and in util-linux).

## Post-Execution Reflection

1. **Did the JSON match what the person saw in the panel?** If the exit code or output differed, fix the launcher and add a test.
2. **Did a tab stay behind after a successful run, or close after a failed one?** Fix the close rule.
3. **Did a secret appear in `output`?** That run should have used `--no-log`; say so above if the case was not covered.
