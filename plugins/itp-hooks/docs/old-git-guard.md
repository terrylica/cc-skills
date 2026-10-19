# old-git-guard

**Hook:** `hooks/pretooluse-old-git-guard.ts` · **Detector:** `hooks/lib/old-git-detector.ts` · **Companion:** `hooks/sessionstart-git-version-check.sh` · **Event:** PreToolUse (Bash orchestrator) + SessionStart · **Escape:** `OLD-GIT-OK: <≥10-char reason>`

Denies a git command that fires hooks when the git that would run is older than 2.54. That includes an explicit `/usr/bin/git` on macOS, which is Apple's git (2.50 on macOS 15).

## The hazard

Git 2.54 added config-based hooks: a `hook.<name>.event` / `hook.<name>.command` pair in `~/.gitconfig` runs a hook in every repository without touching `.git/hooks` or `core.hooksPath`. An older git reads the same config file and **silently runs none of those hooks**. Nothing errors and nothing warns, so every hook defined that way is skipped, even though a newer git on the same machine would have run it.

## What is checked

| Command                                                                                            | Verdict with git < 2.54 |
| -------------------------------------------------------------------------------------------------- | ----------------------- |
| `git commit`, `push`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`                     | deny                    |
| the same with global options: `git -C <dir> commit`, `git -c k=v push`, `git --git-dir=… rebase`   | deny                    |
| the same through wrappers: `sudo`, `env`, `bash -c '…'`, `pueue add -- …`, heredocs fed to a shell | deny                    |
| `/usr/bin/git commit` (any explicit path): that binary's own version decides                       | deny                    |
| read-only git: `status`, `log`, `diff`, `fetch`, `show`, …                                         | allow, never probed     |
| mentions: quoted text, comments, `grep 'git push'`, heredocs fed to `cat`                          | allow                   |
| `ssh host 'git commit'`: the remote host's git, which this machine cannot judge                    | allow                   |
| version cannot be read (probe fails or output unparseable)                                         | allow (fail open)       |

`pull` and `revert` are included beyond the original six because both create commits and fire `commit-msg` / `pre-merge-commit`.

## Which git

An explicit path (`/usr/bin/git`, `./bin/git`) is probed as written. A bare `git` is resolved on the hook's `PATH`, which Claude Code inherits from the same environment as the Bash tool. A `PATH=` assignment inside the command itself is not modelled, and neither are git aliases (`git ci` for `commit`).

Each version is cached per session in `$TMPDIR/itp-hooks-old-git-guard/<session>.json`, keyed by binary path, mtime and size. An upgrade mid-session is therefore noticed, and the steady-state cost is one `stat`. There are no network calls.

## The fix the message names

Run the same command with `/opt/homebrew/bin/git`, or put Homebrew first on `PATH` (`export PATH="/opt/homebrew/bin:$PATH"`) and use plain `git`. On Linux, install git 2.54 or newer and make it the first `git` on `PATH`.

## SessionStart companion

`sessionstart-git-version-check.sh` runs `git --version` once at session start and writes a warning into the session context when the first `git` on `PATH` is below 2.54, or is `/usr/bin/git` on macOS. It is silent otherwise and never blocks. Its floor mirrors `GIT_CONFIG_HOOKS_MIN_VERSION` in the detector, and a test keeps the two equal.

## Escape

`OLD-GIT-OK: <reason>` anywhere in the command, with at least 10 characters of reason. Use it only where no config-based hook gate applies; the fix above is almost always the right answer.

Tests: `hooks/pretooluse-old-git-guard.test.ts` (stub `git` binaries on `PATH` report a chosen version, so the verdict does not depend on the host's git).
