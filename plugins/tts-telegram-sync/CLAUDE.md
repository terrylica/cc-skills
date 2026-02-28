# tts-telegram-sync Plugin

> Telegram bot + iTerm2 TTS integration lifecycle management. Depends on `kokoro-tts` for engine management.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md) | **Engine**: [kokoro-tts CLAUDE.md](../kokoro-tts/CLAUDE.md)

## Overview

This plugin manages the Telegram notification bot and iTerm2 tab focus integration for TTS. The Kokoro TTS engine itself is managed by the `kokoro-tts` plugin — use `/kokoro-tts:install`, `/kokoro-tts:health`, `/kokoro-tts:upgrade`, `/kokoro-tts:remove`, and `/kokoro-tts:diagnose` for engine management. All components share a lock file protocol and NDJSON telemetry.

## Conventions

- **Runtime**: Bun for TypeScript, Python 3.13 for Kokoro, Bash for shell scripts
- **Paths**: XDG-compliant (`~/.local/share/kokoro/` for engine, `~/.local/share/tts-telegram-sync/logs/` for logs)
- **Config SSoT**: `~/.claude/automation/claude-telegram-sync/mise.toml`
- **Lock protocol**: `/tmp/kokoro-tts.lock` with 5s heartbeat, 30s stale threshold + pgrep defense
- **Signal sound**: `Tink.aiff` via `TTS_SIGNAL_SOUND` env var (configurable, empty to disable)

## Key Paths

| Resource         | Path                                         |
| ---------------- | -------------------------------------------- |
| Bot source       | `~/.claude/automation/claude-telegram-sync/` |
| Kokoro venv      | `~/.local/share/kokoro/.venv`                |
| Kokoro CLI       | `~/.local/share/kokoro/tts_generate.py`      |
| Shell symlinks   | `~/.local/bin/tts_*.sh`                      |
| Centralized logs | `~/.local/share/tts-telegram-sync/logs/`     |
| Secrets          | `~/.claude/.secrets/ccterrybot-telegram`     |
| Lock file        | `/tmp/kokoro-tts.lock`                       |

## Shared Shell Library

`scripts/lib/tts-common.sh` provides common functions sourced by all TTS shell scripts:

- `tts_log` - Plain text logging to `$LOG` (default: `/tmp/kokoro-tts.log`)
- `acquire_tts_lock` / `release_tts_lock` - Lock with heartbeat
- `detect_language` - CJK ratio heuristic
- `kill_existing_tts` - Stop active playback
- `play_tts_signal` - Signal sound (Tink.aiff)

## Service Architecture

The bot runs as a launchd service via a compiled Swift runner binary (`telegram-bot-runner`) that launches `bun --watch run src/main.ts`. Code changes auto-restart the service — no manual kills needed.

See [itp-hooks CLAUDE.md: TypeScript Services](../itp-hooks/CLAUDE.md#typescript-services-swift-runner--bun---watch) for the full pattern. Process tree and operational commands: [bot-process-control references](./skills/bot-process-control/references/).

## Telemetry

Bot emits NDJSON with core fields: `ts`, `level`, `event`, `component`, `pid` via `audit-log.ts`.
Shell scripts use plain text via `tts_log`. Logs: `~/.local/share/tts-telegram-sync/logs/audit/` (NDJSON), `/tmp/kokoro-tts.log` (plain text).

## References

- [Lock debugging](./skills/diagnostic-issue-resolver/references/lock-debugging.md)
- [Config reference](./skills/settings-and-tuning/references/config-reference.md)
- [Voice catalog](./skills/voice-quality-audition/references/voice-catalog.md)
