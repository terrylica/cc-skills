---
name: diagnose
description: "Diagnose Kokoro TTS issues. TRIGGERS - kokoro not working, tts diagnose, kokoro error, tts troubleshoot."
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
---

# Diagnose Kokoro TTS

Troubleshoot Kokoro TTS engine issues through systematic diagnostics.

## Known Issues

| Issue              | Likely Cause        | Diagnostic                                                            | Fix                                          |
| ------------------ | ------------------- | --------------------------------------------------------------------- | -------------------------------------------- |
| Import error       | Venv corrupted      | `python -c "from mlx_audio.tts.utils import load_model"`              | `kokoro-install.sh --uninstall && --install` |
| Model not found    | Download incomplete | `ls ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/` | `kokoro-install.sh --install` to re-download |
| Slow synthesis     | First-run warmup    | Time a test synthesis                                                 | Normal — subsequent runs use cached model    |
| Not Apple Silicon  | Intel/Linux system  | `uname -m` != `arm64`                                                 | MLX-Audio requires Apple Silicon (M1+)       |
| Wrong Python       | Not 3.13            | `~/.local/share/kokoro/.venv/bin/python --version`                    | Rebuild venv with `--uninstall && --install` |
| Server won't start | Port in use         | `lsof -i :8779`                                                       | Kill existing process or change port         |
| No audio from CLI  | Empty text          | Check `--text` argument                                               | Provide non-empty text                       |

## Diagnostic Workflow

### Step 1: Collect symptoms

Use AskUserQuestion:

- What happened? (import error, no audio, slow, server won't start)
- When? (after upgrade, first time, suddenly)

### Step 2: Run automated diagnostics

```bash
# Platform check
echo "Arch: $(uname -m)"
echo "macOS: $(sw_vers -productVersion)"

# Venv check
[[ -d ~/.local/share/kokoro/.venv ]] && echo "Venv: OK" || echo "Venv: MISSING"

# Python version
~/.local/share/kokoro/.venv/bin/python --version 2>/dev/null || echo "Python: NOT FOUND"

# MLX-Audio import
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('MLX-Audio: OK')" 2>&1 || echo "MLX-Audio: FAIL"

# Scripts present
for f in kokoro_common.py tts_generate.py tts_server.py; do
  [[ -f ~/.local/share/kokoro/$f ]] && echo "$f: OK" || echo "$f: MISSING"
done

# Version info
cat ~/.local/share/kokoro/version.json 2>/dev/null || echo "version.json: MISSING"
```

### Step 3: Map to known issue and apply fix

Use the Known Issues table above to identify the root cause and apply the targeted fix.

### Step 4: Verify

```bash
# Quick synthesis test
~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Diagnostic test" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-diag-test.wav && echo "Synthesis: OK"
```


## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
