# broad-process-signal-guard

**Hook:** `hooks/pretooluse-broad-process-signal-guard.ts` · **Detector:** `hooks/lib/broad-process-signal-detector.ts` · **Event:** PreToolUse on `Bash|Write|Edit|MultiEdit` · **Escape:** `BROAD-PROCESS-SIGNAL-OK: <reason of 10+ characters>` · **Fails:** open

Kill guard v2. Its sibling [pkill-option-after-pattern-guard](./pkill-option-after-pattern-guard.md) blocks the one spelling that caused the 2026-09-27 incident. This guard blocks the rest of that family: signals aimed by name or pattern that reach far more than the process the agent meant.

## Why

On 2026-09-27 an agent's `pkill -f '<pattern>' -n` became a pattern of `-n` on macOS. It SIGTERMed eight Claude Code sessions, every Electron app's crash reporter (the apps then crash-looped "quit unexpectedly" dialogs until relaunched), an agent Chrome and Orca's terminals. It also wedged `synergy-core`, which left the bigblack workstation with no input and a blank display.

A managed Claude Code kernel sandbox that confined each command's signals to its own subtree was installed fleet-wide the same day and retired hours later, because it blocked too much autonomous work (decision: `~/.claude/decisions-release-toolchain-CLAUDE.md`, "Claude Code kernel sandbox retired"; code at tag `archive/pre-retire-managed-sandbox-policy`). This guard and v1 are therefore the protection that remains. Signalling the PID you started is always possible and never broad, so a static block costs almost nothing.

## What it denies

| Form                                                   | Why it is broad                                                                   |
| ------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `kill -9 -1`, `kill -- -1`, `kill -1 -1`               | `-1` as a TARGET is every process you may signal                                  |
| `kill 0`, `kill -TERM 0`                               | your whole process group, which under a harness, pueue or launchd is not just you |
| `pkill node`, `pkill -f claude`, `killall bun`         | shared runtimes and host programs run as many unrelated processes                 |
| `kill $(pgrep python3)`, `` kill -9 `pgrep node` ``    | the same, through a substitution                                                  |
| `pkill -u me`, `killall -u me` (no process name)       | every process of that user                                                        |
| `pkill -f vite`, `pkill -f '.*'`, `killall -m '^Code'` | fewer than five literal characters cannot single out one process                  |

The shared-name list is anchored to the whole name or pattern, so `pkill -f 'bun server.ts --port 5198'` stays specific while `bun` alone does not. The list covers node, bun, deno, the npm/pnpm/yarn/uv launchers, python (any version), ruby, perl, java, php, the shells, ssh/sshd, claude, codex, electron, Chrome/Chromium and their helpers, Code/Cursor, iTerm2, Terminal, tmux, screen, mosh-server, launchd, loginwindow, WindowServer, systemd, sway, pueued and login.

It also inspects shell scripts written with Write, Edit or MultiEdit. A file counts as a shell script by extension (`.sh .bash .zsh .ksh .dash .command`) or by a shell shebang, including the on-disk shebang when an Edit touches an extensionless script. In scripts it applies both this check and the v1 option-order check, which closes v1's documented gap: a script written first and executed second.

## What it deliberately allows

- `kill <pid>`, `kill -1 <pid>` (SIGHUP to one PID), `kill -0 <pid>` probes, `kill -l`.
- `pgrep` on its own: it only reports.
- Patterns it cannot see: `pkill -f "$PAT"`. An empty variable is a separate hazard.
- Single-instance relaunches: `killall Dock`, `killall Finder`, `killall SystemUIServer`.
- Mere mentions: quoted arguments, comments, heredocs fed to `cat`/`python3 -`/`git commit -F -`, and non-shell files (`.md`, `.py`, `.ts`).
- Option-looking words after the first pkill pattern: v1 explains those, so one mistake gets one explanation.

## Shared lexer

v1's lexer was extracted on 2026-09-27 into `hooks/lib/shell-command-quote-aware-static-lexer.ts` (tokenising) and `hooks/lib/shell-command-invocation-walker.ts` (wrappers and nesting: `$(…)`, backticks, `sudo`/`env`/`nice`/`timeout`/`xargs`/`caffeinate`, `bash -c`, `ssh host '…'`, `pueue add`, heredocs fed to a shell). Both guards use them, so they share the same blind spots rather than each having its own.

## Known gaps

- `pgrep … | xargs kill` is not connected: the pipeline's pgrep is a separate command.
- A script executed from a path the agent did not write this session is not inspected.
- Signals sent by a program in another language (`subprocess.run(["pkill", …])`, `process.kill(-1)`) are out of scope.

## Tests

`hooks/pretooluse-broad-process-signal-guard.test.ts` spawns the real hook: 18 deny cases, 17 allow cases (including the SIGHUP, probe and mention forms), and the Write/Edit/MultiEdit paths, among them v1's incident line written into a `.sh` file.
