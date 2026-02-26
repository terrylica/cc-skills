**Skill**: [Pueue Job Orchestration](../SKILL.md)

# Callback Hooks & Scheduling

## Callback Hooks (Completion Notifications)

Pueue fires a callback command on **every** task completion. Configure in `pueue.yml`:

```yaml
daemon:
  callback: 'curl -s -X POST https://hooks.example.com/pueue -d ''{"id":{{id}},"result":"{{result}}","exit_code":{{exit_code}},"command":"{{command}}"}'''
  callback_log_lines: 10 # Lines of stdout/stderr available in {{output}}
```

### Template Variables (14 total, Handlebars syntax)

| Variable            | Type   | Description                                              |
| ------------------- | ------ | -------------------------------------------------------- |
| `{{id}}`            | int    | Task ID                                                  |
| `{{command}}`       | string | The command that was run                                 |
| `{{path}}`          | string | Working directory                                        |
| `{{group}}`         | string | Group name                                               |
| `{{result}}`        | string | `Success`, `Failed`, `Killed`, `DependencyFailed`        |
| `{{exit_code}}`     | string | `0` on success, error code on failure, `None` otherwise  |
| `{{start}}`         | string | Unix timestamp of start time                             |
| `{{end}}`           | string | Unix timestamp of end time                               |
| `{{output}}`        | string | Last N lines of stdout/stderr (see `callback_log_lines`) |
| `{{output_path}}`   | string | Full path to log file on disk                            |
| `{{queued_count}}`  | string | Remaining queued tasks in this group                     |
| `{{stashed_count}}` | string | Remaining stashed tasks in this group                    |

### Production Examples

```bash
# File-based sentinel (for script polling)
callback: "echo '{{id}}:{{result}}:{{exit_code}}' >> /tmp/pueue-completions.log"

# Telegram notification
callback: "curl -s 'https://api.telegram.org/bot${BOT_TOKEN}/sendMessage?chat_id=${CHAT_ID}&text=Job%20{{id}}%20{{result}}%20(exit%20{{exit_code}})'"

# Conditional alert (only on failure)
callback: "/bin/bash -c 'if [ \"{{result}}\" != \"Success\" ]; then echo \"FAILED: {{command}}\" | mail -s \"Pueue Alert\" user@example.com; fi'"
```

### Config File Location (Platform Difference)

| Platform  | Config Path                                     |
| --------- | ----------------------------------------------- |
| **macOS** | `~/Library/Application Support/pueue/pueue.yml` |
| **Linux** | `~/.config/pueue/pueue.yml`                     |

See [Pueue Config Reference](./pueue-config-reference.md) for all settings.

---

## Delayed Scheduling (`--delay`)

Queue a job that starts after a specified delay:

```bash
# Relative time
pueue add --delay 3h -- python heavy_computation.py

# Natural language
pueue add --delay "next wednesday 5pm" -- python weekly_report.py

# RFC 3339
pueue add --delay "2026-03-01T02:00:00" -- python overnight_batch.py
```

### Stashed + Delay Combo

Create stashed jobs that auto-enqueue at a future time:

```bash
# Stash now, auto-enqueue in 2 hours
pueue add --stashed --delay 2h -- python populate_cache.py
```

### Patterns

| Pattern                              | Command                                                |
| ------------------------------------ | ------------------------------------------------------ |
| Off-peak batch scheduling            | `pueue add --delay "2am" -- python heavy_etl.py`       |
| Staggered thundering-herd prevention | `pueue add --delay "${i}s" -- curl api/endpoint`       |
| Weekend-only processing              | `pueue add --delay "next saturday" -- python batch.py` |
