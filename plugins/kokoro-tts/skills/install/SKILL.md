---
name: install
description: "Install Kokoro TTS engine on Apple Silicon. TRIGGERS - install kokoro, setup tts, kokoro install, tts setup."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Install Kokoro TTS

Install the Kokoro TTS engine: Apple Silicon verification, Python 3.13 venv, MLX-Audio dependencies, model download, and verification synthesis.

> **Platform**: macOS Apple Silicon (M1+) only. Fails fast on Intel/Linux.

## Prerequisites

| Component     | Required | Check                |
| ------------- | -------- | -------------------- |
| Apple Silicon | Yes      | `uname -m` = `arm64` |
| uv            | Yes      | `uv --version`       |
| Python 3.13   | Yes      | `uv python list`     |

## Workflow

### Step 1: Preflight

```bash
# Check Apple Silicon
[[ "$(uname -m)" == "arm64" ]] && echo "OK: Apple Silicon" || echo "FAIL: Requires Apple Silicon (M1+)"

# Check uv
command -v uv && echo "OK: uv found" || echo "FAIL: Install with 'brew install uv'"
```

### Step 2: Install

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --install
```

This performs:

1. Verifies Apple Silicon (fails fast on Intel/Linux)
2. Creates Python 3.13 venv at `~/.local/share/kokoro/.venv` via uv
3. Installs MLX-Audio dependencies (mlx-audio, soundfile, numpy)
4. Copies `kokoro_common.py`, `tts_generate.py` from plugin bundle
5. Downloads Kokoro-82M-bf16 MLX model from HuggingFace
6. Writes `version.json` with mlx_audio version and model ID
7. Runs verification synthesis ("Warm up.")

### Step 3: Verify

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --health
```

All 6 checks should pass. Print "Installation complete — run /kokoro-tts:health to verify".

## Troubleshooting

| Issue               | Cause                | Solution                             |
| ------------------- | -------------------- | ------------------------------------ |
| Not Apple Silicon   | Intel Mac or Linux   | MLX-Audio requires M1+ Mac           |
| uv not found        | Not installed        | `brew install uv`                    |
| Model download slow | Large first download | Wait for HuggingFace download        |
| Permission denied   | Script not +x        | `chmod +x scripts/kokoro-install.sh` |
| Venv already exists | Previous install     | Run `--uninstall` then `--install`   |


## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
