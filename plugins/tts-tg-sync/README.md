# TTS Telegram Sync (TTS only)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-8-blue.svg)](<>)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](<>)

Hotkey-driven text-to-speech for macOS: read the clipboard aloud through Kokoro (via `claude-tts-companion`) with a Supertonic fallback, change the speech rate, stop playback, and audition Kokoro voices.

The Telegram sync bot this plugin used to manage was retired on 2026-09-24, and its skills, hook and setup steps were removed on 2026-09-26. The plugin name is kept so existing installs and `~/.local/bin` links keep working.

## Installation

```bash
# From cc-skills marketplace
/plugin install tts-tg-sync@cc-skills
```

## Quick Start

```bash
# Install the local Kokoro engine and link the hotkey scripts
/tts-tg-sync:setup

# Check system health
/tts-tg-sync:health
```

Then bind a hotkey (a Karabiner-Elements `shell_command` rule, or a BetterTouchTool action) to `~/.local/bin/tts_read_clipboard_wrapper.sh`.

## Skills

| Skill                       | Purpose                                                                 |
| --------------------------- | ----------------------------------------------------------------------- |
| `setup`                     | Short bootstrap: Kokoro engine, `~/.local/bin` links, verification      |
| `full-stack-bootstrap`      | Detailed bootstrap: prerequisites, Kokoro, links, hotkey binding, tests |
| `settings-and-tuning`       | Speech rate, engine choice, voices, signal sound, Supertonic knobs      |
| `health`                    | TTS health check (engines, locks, links, hotkey binding)                |
| `component-version-upgrade` | Upgrade Kokoro, mlx-audio, model, bundled `tts_generate.py`             |
| `clean-component-removal`   | Orderly teardown: venv, links, temp files, locks                        |
| `diagnostic-issue-resolver` | Diagnose silent hotkeys, lock, audio and engine issues                  |
| `voice-quality-audition`    | Compare Kokoro voice quality across 10 voices                           |

## Architecture

```
Hotkey → tts_read_clipboard_wrapper.sh
  ├─ Kokoro:     tts_kokoro.sh → claude-tts-companion POST /tts/speak   (/tmp/tts_kokoro.lock)
  └─ Supertonic: tts_read_clipboard.sh → tts_supertonic_speak.py         (/tmp/kokoro-tts.lock)
Speed keys → tts_speed_set.sh    Stop key → tts_stop.sh    Audition → local Kokoro venv
```

## Components

| Component         | Location                                       | Runtime                 |
| ----------------- | ---------------------------------------------- | ----------------------- |
| Kokoro TTS engine | `~/.local/share/kokoro/`                       | Python 3.14 (MLX-Audio) |
| Hotkey scripts    | Plugin `scripts/` → links in `~/.local/bin/`   | Bash                    |
| Shared library    | Plugin `scripts/lib/tts-common.sh`             | Bash                    |
| Resident engine   | `claude-tts-companion` plugin (HTTP on `8780`) | Swift                   |

## Hooks

None registered. `hooks/hooks.json` is intentionally empty.

## Requirements

- macOS with Apple Silicon (M1+) for MLX Metal acceleration
- Python 3.14 via uv
- `claude-tts-companion` for the primary Kokoro path (the Supertonic fallback works without it)
- Homebrew

## License

MIT
