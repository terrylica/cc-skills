# Kokoro TTS Engine Bootstrap Reference

Detailed reference for the Kokoro TTS engine installation managed by `scripts/kokoro-install.sh`.

## Architecture

```
~/.local/share/kokoro/          # XDG-compliant install directory
├── .venv/                      # Python 3.13 venv (created by uv)
│   └── bin/python              # Venv Python interpreter
├── tts_generate.py             # CLI script (copied from plugin bundle)
└── version.json                # Installation metadata
```

Model cache is stored separately at `~/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/` (HuggingFace default).

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

All dependency versions are pinned in `scripts/kokoro-install.sh` (the SSoT). Key packages:

| Package         | Purpose                                           |
| --------------- | ------------------------------------------------- |
| kokoro          | Core TTS engine (Kokoro-82M model interface)      |
| misaki[en]      | English phonemizer for text-to-phoneme conversion |
| torch           | PyTorch for MPS-accelerated inference             |
| soundfile       | WAV file I/O                                      |
| numpy           | Audio array operations                            |
| transformers    | HuggingFace model loading                         |
| huggingface_hub | Model download from HuggingFace Hub               |
| loguru          | Structured logging                                |

## Apple Silicon MPS Verification

The installer verifies MPS (Metal Performance Shaders) availability:

```python
import torch
assert torch.backends.mps.is_available(), "MPS not available"
```

MPS provides GPU-accelerated inference on Apple Silicon. The `tts_generate.py` script sets `PYTORCH_ENABLE_MPS_FALLBACK=1` for operations not yet implemented on Metal.

Device selection priority in `tts_generate.py`:

1. `mps` (Apple Silicon)
2. `cuda` (NVIDIA GPU)
3. `cpu` (fallback)

## Model Download

The Kokoro-82M model is downloaded from HuggingFace on first use:

```python
from kokoro import KPipeline
KPipeline("en-us", repo_id="hexgrad/Kokoro-82M")
```

This triggers an automatic download to `~/.cache/huggingface/hub/`. Subsequent runs use the cached model. The model is approximately 170 MB.

## version.json

The installer writes a metadata file tracking the installation:

```json
{
  "kokoro": "<version>",
  "torch": "<version>",
  "python": "3.13",
  "installed_at": "2026-02-13T00:00:00Z",
  "source": "kokoro-install.sh --install",
  "venv_path": "~/.local/share/kokoro/.venv"
}
```

This is used by `--health` checks and upgrade tracking.

## Installer Commands

| Command       | Purpose                                                                                |
| ------------- | -------------------------------------------------------------------------------------- |
| `--install`   | Fresh install (venv + deps + model + MPS verify)                                       |
| `--upgrade`   | Upgrade deps + re-download model                                                       |
| `--health`    | Health check (8 checks: venv, python, script, kokoro, torch, MPS, model, version.json) |
| `--uninstall` | Remove venv and script (preserves model cache)                                         |
| `--migrate`   | Migrate from legacy `~/fork-tools/kokoro/` to XDG location                             |

## Health Check Details

`kokoro-install.sh --health` runs 8 checks:

1. Venv exists at `~/.local/share/kokoro/.venv`
2. Python executable is present and executable
3. `tts_generate.py` exists
4. `kokoro` package is importable
5. `torch` package is importable
6. MPS is available
7. Model is cached and loadable
8. `version.json` exists
