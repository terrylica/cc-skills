---
status: accepted
date: 2025-12-26
---

# asciinema-tools Daemon Architecture

## Status

Accepted

## Context and Problem Statement

The original asciinema-tools bootstrap design (ADR 2025-12-24) ran the idle-chunker process inline with the Claude Code session. This architecture has critical failure modes:

| Issue                           | Impact                                                              |
| ------------------------------- | ------------------------------------------------------------------- |
| Shared `gh auth` state          | Switching GitHub accounts breaks backup silently                    |
| Terminal-bound process          | Chunker dies when terminal closes                                   |
| SSH ControlMaster caching       | Stale connections cause auth failures                               |
| Silent failures (`2>/dev/null`) | No indication backups aren't reaching remote                        |
| `source` vs direct execution    | `source script.sh` with `set -e` + EXIT trap closes user's terminal |

These issues were discovered in production when:

1. User switched GitHub accounts mid-session, breaking all subsequent pushes
2. Stale SSH ControlMaster connections caused "Permission denied" despite valid credentials
3. User ran `source bootstrap-claude-session.sh` instead of `./bootstrap-claude-session.sh`, causing EXIT trap to fire in their shell

## Decision Drivers

- Recording infrastructure must be independent of `gh auth` state
- Chunker must survive terminal close
- Push failures must be visible and actionable
- Bootstrap script must be safe from accidental `source` execution
- Single command to check backup health

## Considered Options

1. **Quick fixes only** - Add SSH cache clearing, source prevention guard
2. **Full redesign with launchd daemon** - Dedicated background process with Keychain credentials
3. **Systemd user service** - Linux-specific, not applicable to macOS

## Decision Outcome

Chosen option: **Option 2 - Full redesign with launchd daemon** because:

- macOS launchd provides KeepAlive and auto-restart on crash
- Keychain stores PAT independently of `gh auth`
- Daemon survives terminal close
- Centralized logging and health monitoring
- Push failures trigger Pushover notification

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  DECOUPLED ARCHITECTURE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  launchd Daemon (com.cc-skills.asciinema-chunker.plist)     │   │
│  │  ─────────────────────────────────────────────────────────  │   │
│  │  • Survives terminal close                                  │   │
│  │  • Auto-restart on crash                                    │   │
│  │  • Starts on login                                          │   │
│  │  • Own credentials (Keychain PAT)                           │   │
│  │  • Independent of gh auth                                   │   │
│  └───────────────────────────────────┬─────────────────────────┘   │
│                                      │                              │
│                                      ▼                              │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  idle-chunker-daemon.sh                                     │   │
│  │  ─────────────────────────────────────────────────────────  │   │
│  │  • Monitors ~/.asciinema/active/*.cast                      │   │
│  │  • Pushes via PAT from Keychain (not gh auth)               │   │
│  │  • Logs to ~/.asciinema/logs/chunker.log                    │   │
│  │  • Updates ~/.asciinema/health.json                         │   │
│  │  • Pushover notification on failure                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Claude Code CLI (UNCHANGED)                                │   │
│  │  ─────────────────────────────────────────────────────────  │   │
│  │  • Pure coding experience                                   │   │
│  │  • Can switch gh accounts freely                            │   │
│  │  • asciinema writes to ~/.asciinema/active/                 │   │
│  │  • No recording concerns                                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
~/.asciinema/
├── active/                    # Active recordings (watched by daemon)
│   ├── workspace_2025-12-26.cast
│   └── workspace_2025-12-26.json  # Config for daemon
├── logs/
│   ├── chunker.log            # Daemon log
│   ├── launchd-stdout.log     # launchd stdout
│   └── launchd-stderr.log     # launchd stderr
└── health.json                # Daemon health status
```

### Credential Storage

| Credential         | Keychain Service          | Purpose               |
| ------------------ | ------------------------- | --------------------- |
| GitHub PAT         | `asciinema-github-pat`    | Push to orphan branch |
| Pushover App Token | `asciinema-pushover-app`  | Failure notifications |
| Pushover User Key  | `asciinema-pushover-user` | Failure notifications |

### New Commands

| Command                          | Purpose                                         |
| -------------------------------- | ----------------------------------------------- |
| `/asciinema-tools:daemon-setup`  | Interactive wizard for PAT + Pushover + launchd |
| `/asciinema-tools:daemon-start`  | `launchctl load`                                |
| `/asciinema-tools:daemon-stop`   | `launchctl unload`                              |
| `/asciinema-tools:daemon-status` | Health, credentials, recent logs                |
| `/asciinema-tools:daemon-logs`   | View/follow chunker.log                         |

### Bootstrap Script Changes

**Before (inline chunker):**

```bash
source bootstrap-claude-session.sh  # Dangerous!
# Starts asciinema + chunker in same process
# Dies when terminal closes
```

**After (daemon-based):**

```bash
./bootstrap-claude-session.sh  # Direct execution only
# Starts asciinema recording only
# Daemon handles chunking independently
```

**Source Prevention Guard:**

```bash
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    echo "ERROR: This script must be executed directly, not sourced."
    return 1
fi
```

### SSH Cache Clearing

Both daemon and bootstrap script clear SSH caches on startup:

```bash
rm -f ~/.ssh/control-* 2>/dev/null || true
ssh -O exit git@github.com 2>/dev/null || true
ssh -O exit -p 443 git@ssh.github.com 2>/dev/null || true
```

## Consequences

**Positive:**

- Recording works when user switches `gh auth` accounts
- Backup continues if terminal closes (launchd KeepAlive)
- Push failures are logged and trigger Pushover notification
- Zero interference with Claude Code CLI
- Single command for health status (`/asciinema-tools:daemon-status`)
- Interactive setup wizard guides users through PAT creation

**Negative:**

- macOS-only (launchd not available on Linux)
- Requires user to manually create GitHub Fine-Grained PAT
- One-time setup complexity (daemon-setup wizard)

**Neutral:**

- Daemon runs continuously (minimal CPU when idle)
- Keychain credential storage (secure but platform-specific)

## Validation

### Functional Requirements

- [ ] Daemon starts on login
- [ ] Daemon survives terminal close
- [x] PAT retrieved from Keychain (not gh auth) - `load_credentials()` uses `security find-generic-password`
- [ ] Push works with different gh auth account active
- [x] Push failures logged to chunker.log - `push_chunk()` logs to `$LOG_FILE` via stderr redirection
- [x] Push failures trigger Pushover notification - `notify_pushover()` called on push failure
- [x] health.json updated after each operation - `update_health()` called after push success/failure
- [ ] `daemon-status` shows correct state
- [ ] Bootstrap script simplified (no inline chunker)
- [ ] Claude Code CLI unaffected by account switching

### Silent Failure Fixes (v9.4.2)

| File                     | Fix                             | Evidence                                                  |
| ------------------------ | ------------------------------- | --------------------------------------------------------- | ------------------- |
| `idle-chunker-daemon.sh` | SC2012: `find` instead of `ls`  | `shellcheck --format=gcc` passes                          |
| `idle-chunker-daemon.sh` | SC2155: separate declare/assign | Line 222-223: `local chunk_name; chunk_name=...`          |
| `idle-chunker-daemon.sh` | git add errors logged           | Line 242-244: `if ! git add ...                           | tee -a "$LOG_FILE"` |
| `idle-chunker.sh`        | zstd errors to stderr           | Line 78-80: `if ! zstd ... 2>&1; then echo ERROR >&2`     |
| `idle-chunker.sh`        | git push errors captured        | Line 87-94: `push_output=$(git push 2>&1)` with exit code |
| `validate_secret.py`     | stderr emission                 | `print(..., file=sys.stderr)` in exception handlers       |

### Security

- PAT stored in macOS Keychain (encrypted at rest)
- PAT never written to disk in plaintext
- PAT never logged
- Fine-Grained PAT with minimal permissions (Contents: Read and write)

## Related

- [asciinema-tools Plugin Architecture](/docs/adr/2025-12-24-asciinema-tools-plugin.md)
- [Shell Command Portability ADR](/docs/adr/2025-12-06-shell-command-portability-zsh.md)
