# Upgrade Procedures

Detailed upgrade steps for each component of the text-to-speech stack. The Telegram bot's dependency and Bun-runtime procedures were removed on 2026-09-26; the bot was retired on 2026-09-24.

---

## Kokoro TTS Engine

The primary upgrade path. Updates Python dependencies, re-downloads the model, and writes a new `version.json`.

### Upgrade Steps

```bash
KOKORO_INSTALL="$(cc-plugin-root tts-tg-sync)/scripts/kokoro-install.sh"

# 1. Record current state
cat ~/.local/share/kokoro/version.json

# 2. Run health check (baseline)
bash "$KOKORO_INSTALL" --health

# 3. Execute upgrade
bash "$KOKORO_INSTALL" --upgrade

# 4. Verify
bash "$KOKORO_INSTALL" --health
cat ~/.local/share/kokoro/version.json
```

### What Gets Updated

- Python packages: `mlx-audio`, `soundfile`, `numpy`
- Model weights: re-downloaded from `mlx-community/Kokoro-82M-bf16` (uses HuggingFace cache)
- `kokoro_common.py` and `tts_generate.py`: re-copied from plugin bundle to `~/.local/share/kokoro/`
- `version.json`: rewritten with new versions and timestamp

### Rollback

```bash
# If upgrade breaks TTS, do a clean reinstall:
bash "$KOKORO_INSTALL" --uninstall
bash "$KOKORO_INSTALL" --install
```

The model cache at `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16` is preserved across uninstall, so reinstall reuses the cached model.

---

## tts_generate.py Script

Updates the TTS generation script from the plugin bundle without touching the venv.

### Upgrade Steps

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"

# 1. Compare current vs bundle
diff ~/.local/share/kokoro/tts_generate.py "$PLUGIN_DIR/scripts/tts_generate.py"

# 2. Copy from bundle
cp "$PLUGIN_DIR/scripts/tts_generate.py" ~/.local/share/kokoro/tts_generate.py

# 3. Verify
~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Script update test" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-tts-test.wav && echo "OK" || echo "FAIL"
```

### Rollback

The previous version is not automatically backed up. If the new script fails, use `kokoro-install.sh --upgrade` to re-copy from the bundle, or check git history in the cc-skills repo.

---

## Hotkey Scripts

No procedure needed. The `~/.local/bin/tts_*.sh` links point into the plugin, so updating the plugin updates what every hotkey runs. After a plugin update, run the `health` skill's link check to confirm the links still resolve.

---

## Version Tracking

After any upgrade, `version.json` at `~/.local/share/kokoro/` should reflect current state:

```json
{
  "mlx_audio": "0.3.x",
  "backend": "mlx",
  "python": "3.14",
  "model": "mlx-community/Kokoro-82M-bf16",
  "upgraded_at": "2026-02-28T00:00:00Z",
  "source": "kokoro-install.sh --upgrade",
  "venv_path": "~/.local/share/kokoro/.venv"
}
```
