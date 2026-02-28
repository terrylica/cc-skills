# kokoro-tts Plugin

> Local Kokoro TTS engine: MLX-Audio install, HTTP server, voice synthesis, health checks, diagnostics.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md)

## Overview

Universal plugin for on-device text-to-speech using [MLX-Audio](https://github.com/Blaizzy/mlx-audio) Kokoro-82M on Apple Silicon. Provides install, health check, HTTP server, voice synthesis, upgrade, remove, and diagnostics skills.

**Platform requirement**: macOS Apple Silicon (M1+). No Intel, Linux, or ONNX fallback.

## Architecture

```
~/.local/share/kokoro/           # Runtime directory (XDG-compliant)
├── .venv/                       # Python 3.13 venv (uv)
├── kokoro_common.py             # Synthesis SSoT (model ID, sample rate, defaults)
├── tts_generate.py              # CLI tool (chunked streaming)
├── tts_server.py                # HTTP server (OpenAI-compatible)
└── version.json                 # Installation metadata
```

Model cache: `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/`

## Conventions

- **Runtime**: Python 3.13 via uv (CRITICAL: never use 3.14)
- **Backend**: MLX-Audio only — no PyTorch, no ONNX
- **Synthesis SSoT**: `kokoro_common.py` (model ID, sample rate, language aliases, synthesis loop)
- **HTTP server**: OpenAI-compatible `/v1/audio/speech` at port 8779
- **Launchd policy**: Compiled Swift binary only (per macOS launchd policy — no bash scripts)

## Key Paths

| Resource       | Path                                                               |
| -------------- | ------------------------------------------------------------------ |
| Venv           | `~/.local/share/kokoro/.venv`                                      |
| CLI tool       | `~/.local/share/kokoro/tts_generate.py`                            |
| HTTP server    | `~/.local/share/kokoro/tts_server.py`                              |
| Synthesis core | `~/.local/share/kokoro/kokoro_common.py`                           |
| Version info   | `~/.local/share/kokoro/version.json`                               |
| Model cache    | `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/` |

## Dependencies

| Package   | Purpose                                       |
| --------- | --------------------------------------------- |
| mlx-audio | MLX-Audio TTS engine (Kokoro-82M MLX backend) |
| soundfile | WAV file I/O                                  |
| numpy     | Audio array operations                        |

## Cross-References

- `tts-telegram-sync` plugin depends on this for engine management
- HTTP server API: [server-api.md](./skills/server/references/server-api.md)
- Voice catalog: [voice-catalog.md](./skills/synthesize/references/voice-catalog.md)
