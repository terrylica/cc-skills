# Kokoro TTS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-7-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Local text-to-speech engine using MLX-Audio Kokoro-82M on Apple Silicon. Install, synthesize, serve, and manage Kokoro TTS entirely from Claude Code.

## Installation

```bash
# From cc-skills marketplace
/plugin install kokoro-tts@cc-skills
```

## Quick Start

```bash
# Install Kokoro TTS engine
/kokoro-tts:install

# Check health
/kokoro-tts:health

# Synthesize speech
/kokoro-tts:synthesize "Hello from Kokoro TTS"
```

## Skills

| Skill        | Purpose                                                 |
| ------------ | ------------------------------------------------------- |
| `install`    | Apple Silicon check → venv → mlx-audio → model → verify |
| `health`     | 6 checks: venv, python, mlx_audio, scripts, version     |
| `server`     | Start/stop HTTP server (OpenAI-compatible, port 8779)   |
| `synthesize` | Text → WAV via CLI; voice catalog reference             |
| `upgrade`    | Upgrade mlx-audio deps + model + bundled scripts        |
| `remove`     | Clean uninstall (preserves model cache)                 |
| `diagnose`   | Backend-specific troubleshooting                        |

## Architecture

```
~/.local/share/kokoro/
├── .venv/               Python 3.13 venv (uv)
├── kokoro_common.py     Synthesis SSoT
├── tts_generate.py      CLI tool (chunked streaming)
├── tts_server.py        HTTP server (OpenAI API)
└── version.json         Installation metadata
```

## Components

| Component   | Runtime                 | Purpose                       |
| ----------- | ----------------------- | ----------------------------- |
| MLX-Audio   | Python 3.13 (MLX Metal) | On-device TTS inference       |
| HTTP server | Python 3.13             | OpenAI-compatible TTS API     |
| CLI tool    | Python 3.13             | Shell-friendly WAV generation |

## Requirements

- macOS with Apple Silicon (M1+)
- Python 3.13 via uv
- uv package manager
- ~500 MB disk (venv + model cache)

## License

MIT
