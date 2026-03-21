# Upstream: MLX-Audio Kokoro

Reference for the relationship between the MLX-Audio project and the bundled TTS scripts.

## Upstream Project

- **Repository**: [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio)
- **PyPI package**: `mlx-audio` ([PyPI](https://pypi.org/project/mlx-audio/))
- **Model**: Kokoro-82M-bf16 (hosted on HuggingFace at `mlx-community/Kokoro-82M-bf16`)

## Why We Bundle Scripts

The bundled scripts (`kokoro_common.py`, `tts_generate.py`) are custom CLI wrappers we maintain. They are not part of the `mlx-audio` PyPI package.

### Rationale

1. **mlx-audio** provides the `load_model` / `generate` Python API but no standalone CLI suited for shell script integration
2. **kokoro_common.py** is our SSoT for model ID, sample rate, language aliases, and synthesis loop
3. **tts_generate.py** is our CLI adapter that wraps `kokoro_common` for shell script integration
4. The scripts add features not in the upstream library:
   - Chunked streaming mode (`--chunk` flag) for progressive playback
   - Text sanitization (surrogate removal, control char stripping)
   - Hierarchical text chunking (paragraph, sentence, word boundaries)

### File Flow

```
scripts/kokoro_common.py     (plugin bundle - SSoT for synthesis core)
scripts/tts_generate.py      (plugin bundle - SSoT for CLI)
        │
        ├── kokoro-install.sh --install  (copies to runtime directory)
        │
        └── ~/.local/share/kokoro/       (runtime location)
              ├── kokoro_common.py
              └── tts_generate.py
```

The installer (`kokoro-install.sh`) copies the bundled scripts to the Kokoro directory during `--install` and `--upgrade` operations.

## Dependency Relationship

```
PyPI mlx-audio package (upstream library)
    └── provides load_model + generate API
         └── kokoro_common.py (our synthesis SSoT)
              └── tts_generate.py (our CLI wrapper)
                   └── tts_kokoro.sh (shell script, calls tts_generate.py)
                        └── Bot TTS integration (TypeScript, spawns shell script)
```

## Upgrade Considerations

When upgrading the mlx-audio package:

1. Check the [Blaizzy/mlx-audio releases](https://github.com/Blaizzy/mlx-audio/releases) for breaking changes
2. Run `kokoro-install.sh --upgrade` to update all deps
3. The upgrade re-copies bundled scripts from the plugin bundle
4. Run `kokoro-install.sh --health` to verify everything works
5. Test TTS output quality with `tts_kokoro_audition.sh`

## Model Details

- **Name**: Kokoro-82M-bf16
- **Format**: MLX (bfloat16 quantized)
- **Cache location**: `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/`
- **Sample rate**: 24000 Hz
- **Output format**: WAV (via soundfile)

The model is downloaded automatically on first use via `huggingface_hub`. Subsequent runs use the cached version. The `--uninstall` command preserves the model cache (only removes venv and scripts).
