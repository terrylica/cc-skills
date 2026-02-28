---
name: upgrade
description: "Upgrade Kokoro TTS engine dependencies and model. TRIGGERS - upgrade kokoro, update tts, kokoro update, update mlx-audio."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Upgrade Kokoro TTS

Upgrade MLX-Audio dependencies, re-download the model, and update bundled scripts.

## Workflow

### Step 1: Pre-upgrade health check

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --health
cat ~/.local/share/kokoro/version.json
```

### Step 2: Execute upgrade

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --upgrade
```

This upgrades:

- Python packages: `mlx-audio`, `soundfile`, `numpy`
- Model weights: re-downloaded from `mlx-community/Kokoro-82M-bf16`
- Bundled scripts: `kokoro_common.py` and `tts_generate.py` re-copied from plugin
- `version.json`: rewritten with new versions

### Step 3: Post-upgrade verification

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --health
cat ~/.local/share/kokoro/version.json

# Test synthesis
~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Upgrade verification" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-upgrade-test.wav && echo "OK"
```

## Rollback

If upgrade breaks TTS, do a clean reinstall:

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --uninstall
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --install
```

Model cache is preserved across uninstall, so reinstall reuses the cached model.

## Troubleshooting

| Issue               | Cause                     | Solution                                        |
| ------------------- | ------------------------- | ----------------------------------------------- |
| Upgrade fails       | No internet or PyPI down  | Check connectivity, retry                       |
| Import error after  | mlx-audio incompatibility | Clean reinstall: `--uninstall` then `--install` |
| Model download slow | Large download            | Wait for HuggingFace download to complete       |
