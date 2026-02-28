# Common Issues — Expanded Diagnostic Procedures

Detailed step-by-step procedures for diagnosing and resolving each known Kokoro TTS issue.

---

## 1. MLX-Audio Import Error

**Symptom**: `ModuleNotFoundError: No module named 'mlx_audio'` or similar import error.

**Diagnostic Steps**:

```bash
# Step 1: Check venv exists
[[ -d ~/.local/share/kokoro/.venv ]] && echo "Venv: OK" || echo "Venv: MISSING"

# Step 2: Check Python version
~/.local/share/kokoro/.venv/bin/python --version

# Step 3: Try import
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('OK')"

# Step 4: Check installed packages
~/.local/share/kokoro/.venv/bin/pip list 2>/dev/null | grep -i mlx
```

**Resolution Tree**:

- Venv missing --> Run `kokoro-install.sh --install`
- Wrong Python version --> Rebuild: `kokoro-install.sh --uninstall && kokoro-install.sh --install`
- mlx-audio not installed --> `uv pip install --python ~/.local/share/kokoro/.venv/bin/python mlx-audio`

---

## 2. Model Download Failure

**Symptom**: Model load hangs or fails with network error.

**Diagnostic Steps**:

```bash
# Check if model is cached
ls -la ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/ 2>/dev/null

# Test HuggingFace connectivity
curl -s -o /dev/null -w "%{http_code}" https://huggingface.co/
```

**Resolution Tree**:

- Model not cached --> Check internet, retry `kokoro-install.sh --install`
- Partial download --> Delete cache and retry: `rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/`

---

## 3. Not Apple Silicon

**Symptom**: Installation fails with "Requires macOS Apple Silicon (M1+)".

**Diagnostic**:

```bash
uname -m  # Should be arm64
uname -s  # Should be Darwin
```

**Resolution**: MLX-Audio only runs on macOS Apple Silicon. There is no Intel or Linux fallback. Consider cloud-based TTS alternatives.

---

## 4. Slow Synthesis

**Symptom**: TTS generation takes >5s for short text.

**Diagnostic Steps**:

```bash
# Time a test synthesis
time ~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Quick test" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-speed-test.wav

# Check if first run (model loading adds ~5-10s)
```

**Resolution Tree**:

- First run after boot --> Normal, model loads from disk (~5-10s cold start)
- Always slow --> Check if other GPU-heavy processes are running
- Getting slower over time --> Restart the server or Python process (memory leak)

---

## 5. Server Port Conflict

**Symptom**: HTTP server fails to start, "Address already in use".

**Diagnostic**:

```bash
lsof -i :8779
```

**Resolution**: Kill the existing process using port 8779, or change `KOKORO_SERVER_PORT` environment variable.
