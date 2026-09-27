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
| Diagnostics      | `host-ps` / `host-log` through the broker                       | `ps` inside the sandbox sees only the sandbox (PID namespace)                                                                                                                                                                            |

Both were proven the same way: from inside the sandbox, `kill -0` on an outside PID is denied and on the command's own child is allowed.

## The pieces

All code is installed root-owned (`0755`) in `/usr/local/libexec/claude-code-sandbox-policy/` and runs under `/usr/bin/python3`, never a user-writable interpreter such as `bun` under `~/.bun`. Everything is stdlib-only and Python 3.9 compatible, because that is macOS's system Python.

- **`sandbox_escape_gate.py`** (managed PreToolUse, Bash). Silent unless the call sets `dangerouslyDisableSandbox`. Then it approves only when every command is on the allowlist, and fails closed on anything it cannot parse. Allowed: `ssh` (no `ProxyCommand`/`LocalCommand`; a script fed with `ssh … < file` is read and scanned first), read-only `launchctl` (`list`, `print`, `print-disabled`, `blame`), and `git [-C dir] push|fetch|pull|clone|ls-remote`. `osascript` is refused with a pointer to `host-notes`: it used to be allowed as `-e` pairs, but Claude Code keeps it sandboxed even when escaped (see Measured behaviour), so the allowance only advertised a dead end. Each may be piped into `grep`, `head`, `tail`, `cut`, `sort`, `uniq`, `wc`, `cat`, `tr`, `jq` or `column`, and output may only go to `/dev/null`. Never allowed: `kill`, `pkill`, `killall`, `shutdown`, `reboot`, `halt` or `poweroff` anywhere, including inside an ssh remote command or a quoted string; shells, interpreters, `sudo`, `eval` and `xargs` locally; chaining, command substitution, heredocs and input redirection (except for ssh).
- **`sandbox_policy_session_check.py`** (managed SessionStart). Warns the agent and the operator when the kernel sandbox cannot start, the gate is missing or not root-owned, or, on macOS, the broker is not answering. It never blocks a session.
- **`sandbox_diag_broker.py`** (macOS LaunchAgent `com.terryli.sandbox-diag-broker`, plist in root-owned `/Library/LaunchAgents`, started through the signed runner `sandbox-diag-broker-runner`). It serves `GET /ps` and `GET /log` (at most a 60-minute window, one query at a time, 120 s timeout, 32 MiB cap) on `127.0.0.1:8797`, with fixed argv and no shell. Since 2026-09-27 it also serves the **drafts** surface agents need for human-in-the-loop messages (notes-commander `draft-park`), confined to ONE Notes folder, `Claude Drafts`: `GET /notes/drafts` (list), `GET /notes/drafts/note?id=` (read), `POST /notes/drafts` (create), `POST /notes/drafts/note?id=` (replace a body). No delete, no other folder, no other app; note ids must match `x-coredata://<UUID>/ICNote/p<n>` exactly; bodies are capped at 512 KiB and reach AppleScript only as run-handler arguments of fixed scripts, never as script source; one Notes operation at a time. Every request must carry a `Host` naming the broker (127.0.0.1 or localhost on its port), which stops a DNS-rebinding web page from reading `/ps`, `/log` or the drafts, and every `POST` must carry `X-Sandbox-Broker: 1`, which a browser cannot add cross-site. The first Notes request makes macOS ask once whether `sandbox-diag-broker-runner` may control Notes.
- **`host-ps`, `host-log`, `host-notes`**: sandbox-side clients of the broker. Call them without the escape flag. `host-notes list | get ID | new < html | update ID < html`; `draft-park` switches to it automatically when `SANDBOX_RUNTIME` is set.

## Measured behaviour this design is built around (Claude Code 3.10, 2026-09-27)

- `sandbox.excludedCommands` does not exempt commands on macOS ([anthropics/claude-code#53012](https://github.com/anthropics/claude-code/issues/53012)): `ssh`, `ps`, `log`, `osascript` and git-over-ssh stayed sandboxed when excluded.
- `allowUnsandboxedCommands: false` makes Claude Code ignore `dangerouslyDisableSandbox` even in skip-permissions mode. That would close the hatch completely, but it breaks ssh and git-over-ssh, hence the gate.
- With the hatch open, Claude Code honoured the flag for `ssh` but silently kept `ps`, `/usr/bin/log` and wrapper scripts around them sandboxed, whatever their name. This is undocumented, and it is why diagnostics go through the broker rather than the hatch.
- Go and Security.framework TLS inside the macOS sandbox need `allowMachLookup` for `trustd` (`gh` failed with `x509: OSStatus -26276` without it).
- Apple Events are blocked in the sandbox, and the hatch does not lift that for `osascript` either: an escaped `osascript -e 'tell application "Notes" to count folders'` failed `-10810`, exactly as it did sandboxed (2026-09-27). `sandbox.allowAppleEvents: true` would lift it, but Claude Code's own documentation says it "removes code-execution isolation": sandboxed commands could launch other applications unsandboxed and script any running one, which undoes this policy. Hence the one-folder drafts broker instead.
- On macOS the hatch does not lift the sandbox for `git` either, so the gate's git allowance changes nothing there. Measured three times on 2026-09-27, across two sessions: an escaped `git ls-remote` and an escaped `git -C <repo> push origin main` both ran inside the sandbox. Their output began with the sandbox's `sysctl` denial, and a pre-push hook failed exactly as it did sandboxed. GitHub operations therefore have to work INSIDE the sandbox, and they do: `gh` and HTTPS git work as they are, and git over SSH works once ssh's `ProxyCommand` tunnels through the sandbox's authenticated proxy (an `nc` shim around the `ProxyCommand` Claude Code injects). Linux is unmeasured; bubblewrap may honour the flag for git. The allowance stays in the gate until Linux is measured.
- Shell init and hooks break in the macOS sandbox in ways that look like tool bugs. Measured 2026-09-27: `sysctl -n` is refused, so `CARGO_BUILD_JOBS="$(sysctl -n hw.ncpu)"` came out empty and every cargo call failed to parse the empty job count. Use `getconf _NPROCESSORS_ONLN`. `sccache` fails every compile with `Operation not permitted (os error 1)`, so export an empty `RUSTC_WRAPPER` when `SANDBOX_RUNTIME` is set. A hook that needs plain `ssh <host>` gets nowhere, so give it a route over HTTP through the proxy. The general rule: shell init and hooks must not depend on `sysctl -n`, `sccache`, unix sockets, or plain ssh to a host.

## Settings choices

The goal is signal confinement without breaking work, so the network allows every domain (still through the sandbox proxy), and writes are allowed under `~` except `~/.ssh`, `~/.gnupg`, `~/.config/age`, `~/.claude/settings.json`, and (macOS) `~/Library/Keychains` and `~/Library/LaunchAgents`, or (Linux) `~/.config/systemd`. Tighten these once the fleet has lived with the policy.

## Regression check

`managed-sandbox-policy/verify_managed_sandbox_policy.py` is the pilot packaged as a pass/fail test. It changes nothing, runs on each host's `/usr/bin/python3`, and exits 1 when any check fails. Run it after every Claude Code update, after re-applying the installer, and on any host you suspect.

```bash
moon run repo:sandbox-policy-verify                                   # static tier on this host
/usr/bin/python3 plugins/itp-hooks/managed-sandbox-policy/verify_managed_sandbox_policy.py --json
ssh bigblack /usr/bin/python3 ~/eon/cc-skills/plugins/itp-hooks/managed-sandbox-policy/verify_managed_sandbox_policy.py
CCMAX_GROUP=<group> /usr/bin/python3 …/verify_managed_sandbox_policy.py --live --ssh-host bigblack
```

The **static tier** needs no model call. It checks five things:

1. The managed settings are root-owned and actually enable the sandbox and both hooks.
2. Every installed file is root-owned, locked, and byte-identical to the repo copy. A mismatch means the installer was not re-applied.
3. The installed gate returns the expected verdict for eight known escape requests.
4. A process confined the way Claude Code confines Bash cannot signal an outside one (Seatbelt `same-sandbox` on macOS, `bwrap --unshare-pid` on Linux).
5. The SessionStart check reports no degradation.

Run from inside an agent session, checks 4 and 5 are SKIPPED with the reason, because Seatbelt cannot be nested. Run it from a plain terminal or over ssh to exercise them.

The **live tier** (`--live`) starts a victim process, then runs one fresh headless session with no `--settings`, so only the installed policy applies. It judges what happened, not what the model reports:

- a sandboxed `kill -0 <victim>` is refused;
- the escaped one is refused;
- on macOS, `host-ps` returns the process table;
- with `--ssh-host`, an escaped ssh reaches that host;
- `gh api user` works sandboxed;
- the victim is still alive at the end.

It costs one headless session, about 100k prompt tokens. Under the ccmax wrapper, set `CCMAX_GROUP`.

Tests: `test_verify_managed_sandbox_policy.py` pins the live-tier parser and judges.
