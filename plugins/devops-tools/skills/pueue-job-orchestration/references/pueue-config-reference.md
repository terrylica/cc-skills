# Pueue Configuration Reference

Complete `pueue.yml` configuration derived from verified source code (`settings.rs`) and empirical testing on macOS + Linux.

## Config File Location

| Platform  | Config Path                                     | Data Path                              |
| --------- | ----------------------------------------------- | -------------------------------------- |
| **macOS** | `~/Library/Application Support/pueue/pueue.yml` | `~/Library/Application Support/pueue/` |
| **Linux** | `~/.config/pueue/pueue.yml`                     | `~/.local/share/pueue/`                |

Override with environment variable: `PUEUE_CONFIG_PATH=/path/to/pueue.yml`

## `[shared]` Settings

| Setting                   | Type             | Default       | Description                                    |
| ------------------------- | ---------------- | ------------- | ---------------------------------------------- |
| `pueue_directory`         | path (optional)  | OS default    | Directory for state, task logs, certs          |
| `runtime_directory`       | path (optional)  | OS default    | PID file, unix socket location                 |
| `alias_file`              | path (optional)  | config dir    | Path to `pueue_aliases.yml`                    |
| `use_unix_socket`         | bool             | `true`        | Use unix sockets (unix only, not Windows)      |
| `unix_socket_path`        | path (optional)  | runtime dir   | Path to unix socket file                       |
| `unix_socket_permissions` | octal (optional) | `0o700`       | Socket file permissions                        |
| `host`                    | string           | `"127.0.0.1"` | TCP hostname (used when unix sockets disabled) |
| `port`                    | string           | `"6924"`      | TCP port                                       |
| `pid_path`                | path (optional)  | runtime dir   | Daemon PID file location                       |
| `daemon_cert`             | path (optional)  | data dir      | TLS certificate path                           |
| `daemon_key`              | path (optional)  | data dir      | TLS key path                                   |
| `shared_secret_path`      | path (optional)  | data dir      | Shared secret for client auth                  |

## `[client]` Settings

| Setting                       | Type           | Default                | Description                                  |
| ----------------------------- | -------------- | ---------------------- | -------------------------------------------- |
| `restart_in_place`            | bool           | `false`                | Restart replaces task (loses old logs)       |
| `read_local_logs`             | bool           | `true`                 | Read logs from disk (vs request from daemon) |
| `show_confirmation_questions` | bool           | `false`                | Confirm dangerous actions                    |
| `edit_mode`                   | string         | `"toml"`               | `"toml"` or `"files"` for task editing       |
| `show_expanded_aliases`       | bool           | `false`                | Expand aliases in `pueue status`             |
| `dark_mode`                   | bool           | `false`                | Use dark color shades                        |
| `max_status_lines`            | int (optional) | unlimited              | Max lines per task in status view            |
| `status_time_format`          | string         | `"%H:%M:%S"`           | Time format in status output                 |
| `status_datetime_format`      | string         | `"%Y-%m-%d\n%H:%M:%S"` | Datetime format in status output             |

## `[daemon]` Settings

| Setting                  | Type              | Default    | Description                                    |
| ------------------------ | ----------------- | ---------- | ---------------------------------------------- |
| `pause_group_on_failure` | bool              | `false`    | Pause group when any task fails                |
| `pause_all_on_failure`   | bool              | `false`    | Pause ALL groups when any task fails           |
| `compress_state_file`    | bool              | `false`    | Zstd compress state file (~10:1 ratio)         |
| `callback`               | string (optional) | `null`     | Handlebars template command on task completion |
| `callback_log_lines`     | int               | `10`       | Lines of stdout/stderr passed to callback      |
| `env_vars`               | map               | `{}`       | Environment variables injected into all tasks  |
| `shell_command`          | list (optional)   | OS default | Shell for task execution                       |

### Shell Command Defaults

| Platform    | Default                                                 |
| ----------- | ------------------------------------------------------- |
| **Unix**    | `["sh", "-c", "{{ pueue_command_string }}"]`            |
| **Windows** | `["powershell", "-c", "...{{ pueue_command_string }}"]` |

## `[profiles]` Section

Profiles override settings when invoked with `pueue -p <profile>`:

```yaml
profiles:
  gpu-heavy:
    daemon:
      pause_group_on_failure: true
      callback: "echo 'GPU job {{id}} {{result}}' >> /tmp/gpu-completions.log"
    client:
      dark_mode: true
    shared: {}
```

Usage: `pueue -p gpu-heavy status`

## Example Complete Config

```yaml
shared:
  use_unix_socket: true

client:
  restart_in_place: false
  read_local_logs: true
  show_confirmation_questions: false
  dark_mode: false
  status_time_format: "%H:%M:%S"
  status_datetime_format: "%Y-%m-%d\n%H:%M:%S"

daemon:
  pause_group_on_failure: false
  pause_all_on_failure: false
  compress_state_file: true
  callback: "echo '{{id}}:{{result}}:{{exit_code}}' >> /tmp/pueue-completions.log"
  callback_log_lines: 10
  env_vars: {}

profiles:
  production:
    daemon:
      pause_group_on_failure: true
      compress_state_file: true
    client:
      show_confirmation_questions: true
    shared: {}
```

## Source

Derived from [`pueue_lib/src/settings.rs`](https://github.com/Nukesor/pueue/blob/main/pueue_lib/src/settings.rs) and [`pueue_lib/src/setting_defaults.rs`](https://github.com/Nukesor/pueue/blob/main/pueue_lib/src/setting_defaults.rs) in the pueue repository.
