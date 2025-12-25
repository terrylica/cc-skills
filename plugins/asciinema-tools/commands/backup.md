---
description: Stream-backup active recordings to GitHub. TRIGGERS - backup recording, sync cast, streaming backup.
allowed-tools: Bash, AskUserQuestion, Glob, Write
argument-hint: "[install|status|stop|history] [-r repo] [-i interval] [--chunk] [--meta]"
---

# /asciinema-tools:backup

Configure and manage streaming backup to GitHub orphan branch.

## Arguments

| Argument         | Description                            |
| ---------------- | -------------------------------------- |
| `install`        | Configure and start backup automation  |
| `status`         | Show active backups and last sync      |
| `stop`           | Disable backup for current session     |
| `history`        | View recent backup commits             |
| `-r, --repo`     | GitHub repository (e.g., `owner/repo`) |
| `-i, --interval` | Sync interval (e.g., `30s`, `5m`)      |
| `--chunk`        | Split at idle time                     |
| `--meta`         | Include session metadata               |

## Execution

Invoke the `asciinema-streaming-backup` skill with user-selected options.

### Skip Logic

- If action provided -> skip Phase 1 (action selection)
- If `-r` and `-i` provided -> skip Phase 2-3 (config and repo)

### Workflow

1. **Preflight**: Check gh CLI and fswatch
2. **Action**: AskUserQuestion for action type
3. **Config**: AskUserQuestion for backup settings
4. **Repo**: AskUserQuestion for repository selection
5. **Execute**: Run selected action
