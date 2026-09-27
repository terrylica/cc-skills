# managed-sandbox-policy

**Source:** `managed-sandbox-policy/` · **Installer:** `install_managed_sandbox_policy.py` (preview by default, `sudo … --apply`) · **Hosts:** macOS and Linux

Turns on Claude Code's kernel sandbox for every Bash command, makes it impossible for a session or setting to switch off, and allows exactly one way out: a root-owned gate that never lets a command which can signal or stop processes run unsandboxed.

## Why

On 2026-09-27 an agent ran `pkill -f 'bun server.ts --build build-preview' -n`. On macOS, BSD getopt made the trailing `-n` a second pattern, and every process whose argv contained "-n" got SIGTERM: eight Claude Code sessions, every Electron app's crash reporter, Chrome's renderers, Orca's terminals and the Synergy server. The Synergy server survived in a wedged state, so bigblack lost its keyboard and mouse and its display stayed dark. The `pkill-option-after-pattern-guard` blocks that one spelling. A kernel sandbox blocks every spelling: a sandboxed command can signal only its own subtree.

## What each host uses

|                  | macOS                                                           | Linux (bigblack, Ubuntu 24.04)                                                                                                                                                                                                           |
| ---------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Confinement      | Seatbelt, `(allow signal (target same-sandbox))`                | bubblewrap `--unshare-pid` (plus `socat` for the proxy)                                                                                                                                                                                  |
| Prerequisite     | none                                                            | `/etc/apparmor.d/bwrap`: grants user namespaces to `/usr/bin/bwrap` only, because `kernel.apparmor_restrict_unprivileged_userns=1` otherwise stops bwrap with `setting up uid map: Permission denied`. The installer writes and loads it |
| Managed settings | `/Library/Application Support/ClaudeCode/managed-settings.json` | `/etc/claude-code/managed-settings.json`                                                                                                                                                                                                 |
| Diagnostics      | `host-ps` / `host-log` through the read-only broker             | `ps` inside the sandbox sees only the sandbox (PID namespace)                                                                                                                                                                            |

Both were proven the same way: from inside the sandbox, `kill -0` on an outside PID is denied and on the command's own child is allowed.

## The pieces

All code is installed root-owned (`0755`) in `/usr/local/libexec/claude-code-sandbox-policy/` and runs under `/usr/bin/python3`, never a user-writable interpreter such as `bun` under `~/.bun`. Everything is stdlib-only and Python 3.9 compatible, because that is macOS's system Python.

- **`sandbox_escape_gate.py`** (managed PreToolUse, Bash). Silent unless the call sets `dangerouslyDisableSandbox`. Then it approves only when every command is on the allowlist, and fails closed on anything it cannot parse. Allowed: `ssh` (no `ProxyCommand`/`LocalCommand`; a script fed with `ssh … < file` is read and scanned first), read-only `launchctl` (`list`, `print`, `print-disabled`, `blame`), and `osascript -e` without `quit`/`do shell script`/System Events. On macOS, `git` is refused with a message naming the HTTPS fix (changed 2026-09-27; see below), because escaping it never worked there. On Linux, which was not measured, `git [-C dir] push|fetch|pull|clone|ls-remote` may still escape. Each may be piped into `grep`, `head`, `tail`, `cut`, `sort`, `uniq`, `wc`, `cat`, `tr`, `jq` or `column`, and output may only go to `/dev/null`. Never allowed: `kill`, `pkill`, `killall`, `shutdown`, `reboot`, `halt` or `poweroff` anywhere, including inside an ssh remote command or a quoted string; shells, interpreters, `sudo`, `eval` and `xargs` locally; chaining, command substitution, heredocs and input redirection (except for ssh).
- **`sandbox_policy_session_check.py`** (managed SessionStart). Warns the agent and the operator when the kernel sandbox cannot start, the gate is missing or not root-owned, or, on macOS, the broker is not answering. It never blocks a session.
- **`sandbox_diag_broker.py`** (macOS LaunchAgent `com.terryli.sandbox-diag-broker`, plist in root-owned `/Library/LaunchAgents`, started through the signed runner `sandbox-diag-broker-runner`). It serves `GET /ps` and `GET /log` (at most a 60-minute window, one query at a time, 120 s timeout, 32 MiB cap) on `127.0.0.1:8797`, with fixed argv and no shell.
- **`host-ps`, `host-log`**: sandbox-side clients of the broker. Call them without the escape flag.

## Measured behaviour this design is built around (Claude Code 3.10, 2026-09-27)

- `sandbox.excludedCommands` does not exempt commands on macOS ([anthropics/claude-code#53012](https://github.com/anthropics/claude-code/issues/53012)): `ssh`, `ps`, `log`, `osascript` and git-over-ssh stayed sandboxed when excluded.
- `allowUnsandboxedCommands: false` makes Claude Code ignore `dangerouslyDisableSandbox` even in skip-permissions mode. That would close the hatch completely, but it breaks ssh, hence the gate. (git-over-ssh is broken either way; see the git bullets below.)
- With the hatch open, Claude Code honoured the flag for `ssh` but silently kept `ps`, `/usr/bin/log` and wrapper scripts around them sandboxed, whatever their name. This is undocumented, and it is why diagnostics go through the broker rather than the hatch.
- Go and Security.framework TLS inside the macOS sandbox need `allowMachLookup` for `trustd` (`gh` failed with `x509: OSStatus -26276` without it).
- **Git over SSH needs an AUTHENTICATED proxy CONNECT** (measured 2026-09-27). Claude Code injects `GIT_SSH_COMMAND=ssh … -o ProxyCommand='nc -X 5 -x localhost:<proxy> %h %p'`: a SOCKS5 route that carries no credentials, which the proxy refuses (to `ssh.github.com:443` and to `github.com:22`). An HTTP CONNECT without credentials is refused too. The proxy's credentials arrive in `HTTPS_PROXY` / `ALL_PROXY` as `http://user:pass@localhost:<port>`, and an HTTP CONNECT carrying them as `Proxy-Authorization` to `ssh.github.com:443` goes through. So git over SSH host aliases works inside the sandbox with a ProxyCommand that does that, for example an `nc` shim ahead of `/usr/bin/nc` on `PATH` that recognises only the injected argv and passes everything else to the real `nc`. Measured: `git ls-remote` and a dry-run `git push` over two accounts' aliases succeeded inside the sandbox. HTTPS to `github.com` works without any of this (`allowedDomains: ["*"]`).
- **With the hatch open, git stays sandboxed**, like `ps` and `log` above (measured 2026-09-27). Through the hatch, `ssh -T git@github.com-<alias>` authenticated and ran without the sandbox's shell-init symptom (`sysctl: … Operation not permitted`), while `git ls-remote` and `git push` over the same alias failed and still showed it. So on macOS the gate refuses git escapes (they never help) and points to running git inside the sandbox. Linux (bubblewrap) was not measured and keeps the old rule; re-measure there before extending the refusal.
- **The HTTPS alternative:** credentials come from Git Credential Manager, never from `gh` in a credential helper (process-storm rule). GCM cannot store a NEW credential from inside a session, because `~/Library/Keychains` is write-denied (`Could not create new item [0x186a1]`), so seed each account from an ordinary terminal first. If you rewrite remotes to HTTPS, prefer `pushInsteadOf`: `git remote get-url` expands `insteadOf` but not `pushInsteadOf`, and tools that parse the host alias out of it keep working.

## Settings choices

The goal is signal confinement without breaking work, so the network allows every domain (still through the sandbox proxy), and writes are allowed under `~` except `~/.ssh`, `~/.gnupg`, `~/.config/age`, `~/.claude/settings.json`, and (macOS) `~/Library/Keychains` and `~/Library/LaunchAgents`, or (Linux) `~/.config/systemd`. Tighten these once the fleet has lived with the policy.

## Re-validating after a Claude Code update

`/tmp/sandbox-pilot/run-pilot*.sh` were the headless probes behind the measurements above. The regression task that packages them is tracked as follow-on work. Until it lands, re-run the kill probe by hand after an update: `kill -0 <pid of any app>` inside a session must fail with `operation not permitted`.
