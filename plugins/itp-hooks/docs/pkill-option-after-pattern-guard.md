# pkill-option-after-pattern-guard

**Hook:** `hooks/pretooluse-pkill-option-after-pattern-guard.ts` · **Detector:** `hooks/lib/pkill-option-after-pattern-detector.ts` · **Event:** PreToolUse · **Matcher:** `Bash` · **Escape:** `PKILL-OPTION-ORDER-OK: <≥10-char reason>`

Denies a `pkill` or `pgrep` whose option comes **after** the first pattern, such as `pkill -f 'bun server.ts' -n`. The deny message carries the same command with every option moved in front of the pattern.

## The hazard

macOS `pkill` and `pgrep` are the BSD tools, and they read options with BSD `getopt`, which **stops at the first non-option argument**. Everything after the first pattern is therefore another pattern, even when it looks like a flag. So `pkill -f 'bun server.ts --build build-preview' -n` does not mean "the newest match only". It means "signal every process whose command line matches `bun server.ts --build build-preview` **or contains `-n`**", and with `-f` the command line is the whole argv, where `--no-sandbox`, `--no-rate-limit`, `--no-chrome` and `--num-raster-threads` are everywhere.

Linux procps permutes arguments, so there the same line does what it says. That is why it reads as correct, and why an agent that learned it on Linux writes it on a Mac. The corrected order (options first) is equivalent on Linux, so the guard applies on every platform.

`pgrep` is covered as well as `pkill`: `kill $(pgrep -f x -n)` has the same blast radius, and a read-only `pgrep` with this shape returns a wrong answer.

## The incident (2026-09-27)

At 09:46:23 PDT an agent finished a Playwright scenario run with `pkill -f 'bun server.ts --build build-preview' -n 2>/dev/null; true`. At 09:46:30 the following received SIGTERM at the same instant:

- eight Claude Code sessions (`claude --no-chrome …`), whose `ccmax-claude` supervisors logged `exit_code: 143`;
- the Crashpad crash reporter of every Electron app (`chrome_crashpad_handler --no-rate-limit …`): Code, Orca, Synergy, Typeless and Discord, plus Time Doctor's own `crashpad_handler --no-rate-limit …`;
- an agent-launched Google Chrome and a `chrome-headless-shell`, a Lark helper, an Orca helper, and Orca's embedded terminals (`bash --noprofile --norc`).

The user's own Chrome and Google Drive survived, because their crash reporters' arguments contain no `-n`. A read-only reproduction afterwards: `pgrep -f <nonexistent> -n` matched **64** live processes, and `pgrep -n -f <nonexistent>` matched **0**.

The visible damage was worse than the kill. Each app's Crashpad client re-spawns its handler when the handler dies, and on macOS 15.8.1 (`xnu-11417.140.69`) every respawn failed at startup with `Check failed: kr == KERN_SUCCESS. mach_port_request_notification: (os/kern) invalid capability (20)` in `exception_handler_server.cc`. Each failure is a crash, and ReportCrash attributes a helper's crash to its responsible app, so the operator saw a stream of "Code quit unexpectedly", "Synergy quit unexpectedly" and similar dialogs. After ReportCrash throttled its reports, the loop continued silently: 1,196 failed spawns in five minutes, each one a `syspolicyd` provenance check and a launchd service registration.

## Recovering after such a kill

A running app's crash-reporter loop only stops when the app is relaunched, because the restart thread lives in the app. The initial start of a fresh launch works, and only the respawn path fails. To find the looping apps:

```bash
/usr/bin/log show --last 2m --predicate 'process CONTAINS "crashpad" AND messageType == fault' --style compact | grep -c 'Check failed'
```

Then quit and relaunch each affected app gracefully (`osascript -e 'tell application "Synergy" to quit'`, then `open -a Synergy`). The crash reports are named `chrome_crashpad_handler-*.ips` or `crashpad_handler-*.ips` under `~/Library/Logs/DiagnosticReports/`, and their `responsibleProc` field names the app.

## What is flagged

| Shape                                                      | Example                                  |
| ---------------------------------------------------------- | ---------------------------------------- |
| An option after the first pattern                          | `pkill -f foo -n`, `pgrep -x Finder -q`  |
| An option that takes a value (moved with its value)        | `pkill -f "bun server.ts" -P $$`         |
| A signal after the pattern (moved to argv[1])              | `pkill -f foo -9` → `pkill -9 -f foo`    |
| A bare `--` or `-` after the pattern                       | `pkill -f foo --`                        |
| Inside `$(…)` or backticks, including within `"…"`         | `kill $(pgrep -f foo -n)`                |
| Behind `sudo`, `env`, `timeout`, `nice`, `xargs`, …        | `timeout --foreground 5 pkill -f foo -n` |
| Inside `bash`/`sh`/`zsh` `-c`, `ssh host '…'`, `pueue add` | `/usr/bin/env bash -c 'pkill -f foo -n'` |
| Inside a heredoc fed to a shell                            | `bash <<'EOF'` … `EOF`                   |

A signal is moved to the front because BSD `pkill` reads a signal only as its very first argument; `pkill -f -9 foo` is a usage error.

## What is deliberately not flagged

A guard on commands this common, in a repo where the incident itself gets written up, gets switched off if it fires on the wrong thing:

- **Mentions:** quoted arguments (`git commit -m "…pkill -f x -n…"`), comments, and heredoc bodies fed to anything other than a shell (`cat`, `python3 -`, `git commit -F -`).
- **Patterns after `--`:** that is how you write a pattern that really begins with `-` (`pkill -f -- '-n'`).
- **Redirections:** `2>/dev/null`, `>&2` and `2>&1` after the pattern are not arguments.
- **Another command's flags:** `pgrep -f foo | head -n 1`, `pkill -f foo && echo -n done`.

## Known gaps

- ~~A script written to a file with Write/Edit and then executed is not inspected.~~ Closed 2026-09-27: [broad-process-signal-guard](./broad-process-signal-guard.md) applies this check to shell scripts written with Write/Edit. This hook itself still reads only the Bash tool's command string.
- A pattern held in a variable (`pkill -f "$PAT"`) cannot be checked statically. An empty variable matches every process, which is a separate hazard this guard does not claim to cover.

## Better than any pattern

When you started the process yourself, signal its PID rather than pattern-matching the machine: `bun server.ts & pid=$!; …; kill "$pid"`. The process-storm rules already ask hooks to use PID-specific kills and never `pkill -f`. This guard catches the case where `pkill` is used anyway.
