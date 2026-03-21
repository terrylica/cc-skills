# Kokoro TTS Engine Bootstrap Reference

Detailed reference for the Kokoro TTS engine installation managed by `scripts/kokoro-install.sh`.

## Architecture

```
~/.local/share/kokoro/          # XDG-compliant install directory
├── .venv/                      # Python 3.13 venv (created by uv)
│   └── bin/python              # Venv Python interpreter
├── kokoro_common.py            # Shared constants and synthesis core (SSoT)
├── tts_generate.py             # CLI script (copied from plugin bundle)
└── version.json                # Installation metadata
```

Model cache is stored separately at `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/` (HuggingFace default).

## Python 3.13 via uv

<!-- SSoT-OK: kokoro-install.sh is the SSoT for the actual version pin -->

The installer uses `uv venv --python 3.13` to create the virtual environment. This ensures:

- Python 3.13 is used consistently (per the global Python version policy)
- uv handles Python discovery and download if needed
- The venv is isolated from system Python

If Python 3.13 is not available, install it first:

```bash
uv python install 3.13
```

## PyPI Dependencies

All dependency versions are managed by `scripts/kokoro-install.sh` (the SSoT). Key packages:

| Package   | Purpose                                       |
| --------- | --------------------------------------------- |
| mlx-audio | MLX-Audio TTS engine (Kokoro-82M MLX backend) |
| soundfile | WAV file I/O                                  |
| numpy     | Audio array operations                        |

## MLX-Audio Verification

The installer verifies MLX-Audio availability:

```python
from mlx_audio.tts.utils import load_model
print("MLX-Audio OK")
```

MLX-Audio provides Metal-accelerated inference on Apple Silicon. The installer requires `uname -m == arm64` and fails fast on Intel or Linux.

## Model Download

The Kokoro-82M MLX model is downloaded from HuggingFace on first use:

```python
from mlx_audio.tts.utils import load_model
load_model("mlx-community/Kokoro-82M-bf16")
```

This triggers an automatic download to `~/.cache/huggingface/hub/`. Subsequent runs use the cached model.

## version.json

The installer writes a metadata file tracking the installation:

```json
{
  "mlx_audio": "<version>",
  "backend": "mlx",
  "python": "3.13",
  "model": "mlx-community/Kokoro-82M-bf16",
  "installed_at": "2026-02-28T00:00:00Z",
  "source": "kokoro-install.sh --install",
  "venv_path": "~/.local/share/kokoro/.venv"
}
```

This is used by `--health` checks and upgrade tracking.

## Installer Commands

| Command       | Purpose                                                                                           |
| ------------- | ------------------------------------------------------------------------------------------------- |
| `--install`   | Fresh install (venv + mlx-audio + model + verify)                                                 |
| `--upgrade`   | Upgrade deps + re-download model                                                                  |
| `--health`    | Health check (6 checks: venv, python, mlx_audio, kokoro_common.py, tts_generate.py, version.json) |
| `--uninstall` | Remove venv and scripts (preserves model cache)                                                   |

## Health Check Details

`kokoro-install.sh --health` runs 6 checks:

1. Venv exists at `~/.local/share/kokoro/.venv`
2. Python 3.13 executable is present
3. `mlx_audio` package is importable
4. `kokoro_common.py` exists
5. `tts_generate.py` exists
6. `version.json` exists
