# TTS Telegram Sync

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-8-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Full lifecycle management for Kokoro TTS, Telegram bot sync, and iTerm2 integration.

## Installation

```bash
# From cc-skills marketplace
/plugin install tts-telegram-sync@cc-skills
```

## Quick Start

```bash
# Bootstrap everything (Kokoro + Telegram bot + BotFather)
/tts-telegram-sync:setup

# Check system health
/tts-telegram-sync:health

# Install hooks
/tts-telegram-sync:hooks install
```

## Skills

| Skill                       | Purpose                                                              |
| --------------------------- | -------------------------------------------------------------------- |
| `full-stack-bootstrap`      | One-time bootstrap: Kokoro venv, model, BotFather, secrets, symlinks |
| `settings-and-tuning`       | Configure TTS voices, speed, timeouts, queue depth, bot settings     |
| `bot-process-control`       | Start/stop/restart the Telegram sync bot process                     |
| `system-health-check`       | 10-subsystem health check (bot, TTS, locks, MPS, secrets)            |
| `component-version-upgrade` | Upgrade Kokoro, torch, bot deps, model                               |
| `clean-component-removal`   | Orderly teardown: stop bot, remove venv, clean symlinks              |
| `diagnostic-issue-resolver` | Diagnose lock, process, audio, queue issues                          |
| `voice-quality-audition`    | Compare Kokoro voice quality across 10 voices                        |

## Architecture

```
Clipboard (BTT hotkey)
  → tts_kokoro.sh (signal sound → Kokoro generate → chunked afplay)
  → /tmp/kokoro-tts.lock (heartbeat every 5s)

Telegram Bot (bun --watch)
  → notification-watcher.ts → kokoro-client.ts
  → waitForTtsLock() → generate → afplay
  → /tmp/kokoro-tts.lock (acquire/release)

Shared: Lock protocol, signal sound, NDJSON telemetry
```

## Components

| Component         | Location                                        | Runtime                         |
| ----------------- | ----------------------------------------------- | ------------------------------- |
| Kokoro TTS engine | `~/.local/share/kokoro/`                        | Python 3.13 (Apple Silicon MPS) |
| Telegram bot      | `~/.claude/automation/claude-telegram-sync/`    | Bun                             |
| Shell scripts     | Plugin `scripts/` → symlinks in `~/.local/bin/` | Bash                            |
| Shared library    | Plugin `scripts/lib/tts-common.sh`              | Bash                            |

## Hooks

| Hook                      | Event | Purpose                                   |
| ------------------------- | ----- | ----------------------------------------- |
| `telegram-notify-stop.ts` | Stop  | Send session end notification to Telegram |

## Requirements

- macOS with Apple Silicon (M1+) for MPS acceleration
- Bun runtime
- Python 3.13 via uv
- mise (environment management)
- Homebrew

## License

MIT
