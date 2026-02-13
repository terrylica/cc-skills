# Upstream Fork: hexgrad/kokoro

Reference for the relationship between the upstream Kokoro project and the bundled `tts_generate.py` script.

## Upstream Project

- **Repository**: [hexgrad/kokoro](https://github.com/hexgrad/kokoro)
- **PyPI package**: `kokoro` ([PyPI](https://pypi.org/project/kokoro/))
- **Model**: Kokoro-82M (hosted on HuggingFace at `hexgrad/Kokoro-82M`)

## Why We Bundle tts_generate.py

The `tts_generate.py` script in `scripts/tts_generate.py` is the **only custom file** from the upstream project. It is not part of the PyPI package -- it is a CLI wrapper we maintain separately.

### Rationale

1. **PyPI kokoro package** provides the `KPipeline` Python API but no standalone CLI
2. **tts_generate.py** is our CLI adapter that wraps `KPipeline` for shell script integration
3. The script adds features not in the upstream library:
   - Chunked streaming mode (`--chunk` flag) for progressive playback
   - Text sanitization (surrogate removal, control char stripping)
   - Hierarchical text chunking (paragraph, sentence, word boundaries)
   - MPS fallback environment variable (`PYTORCH_ENABLE_MPS_FALLBACK`)
   - Device auto-detection (MPS, CUDA, CPU priority)

### File Flow

```
scripts/tts_generate.py  (plugin bundle - SSoT for the script)
        │
        ├── kokoro-install.sh --install  (copies to venv directory)
        │
        └── ~/.local/share/kokoro/tts_generate.py  (runtime location)
```

The installer (`kokoro-install.sh`) copies the bundled script to the Kokoro directory during `--install` and `--upgrade` operations.

## Dependency Relationship

```
PyPI kokoro package (upstream library)
    └── provides KPipeline API
         └── tts_generate.py (our CLI wrapper)
              └── tts_kokoro.sh (shell script, calls tts_generate.py)
                   └── Bot TTS integration (TypeScript, spawns shell script)
```

## Upgrade Considerations

When upgrading the kokoro PyPI package:

1. Check the [hexgrad/kokoro releases](https://github.com/hexgrad/kokoro/releases) for breaking changes
2. Run `kokoro-install.sh --upgrade` to update all deps
3. The upgrade re-copies `tts_generate.py` from the plugin bundle
4. Run `kokoro-install.sh --health` to verify everything works
5. Test TTS output quality with `tts_kokoro_audition.sh`

## Model Details

- **Name**: Kokoro-82M
- **Size**: Approximately 170 MB
- **Cache location**: `~/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/`
- **Sample rate**: 24000 Hz
- **Output format**: WAV (via soundfile)

The model is downloaded automatically on first use via `huggingface_hub`. Subsequent runs use the cached version. The `--uninstall` command preserves the model cache (only removes venv and script).
