# Common Issues -- Expanded Diagnostic Procedures

Detailed step-by-step procedures for diagnosing and resolving each known issue. The "Bot Not Responding" and bot queue sections that used to be here were removed on 2026-09-26 with the retired Telegram bot.

---

## 1. Hotkey Does Nothing

**Symptom**: Pressing the read-aloud key produces no sound and no notification.

**Diagnostic Steps**:

```bash
# Step 1: Did the script run at all? Press the key, then:
tail -5 /tmp/kokoro-tts.log

# Step 2: Is the binding pointing at the stable link?
grep -o '"[^"]*tts_read_clipboard_wrapper.sh"' ~/.config/karabiner/karabiner.json 2>/dev/null
ls -la ~/.local/bin/tts_read_clipboard_wrapper.sh

# Step 3: Run the exact same path by hand
echo "manual test" | pbcopy && ~/.local/bin/tts_read_clipboard_wrapper.sh; echo "exit=$?"
```

**Resolution Tree**:

- No new log line after a press --> the hotkey tool never ran the script: fix the binding, or grant the tool Accessibility permission
- Binding points at a versioned plugin path --> rebind to `~/.local/bin/tts_read_clipboard_wrapper.sh`
- Manual run works, hotkey does not --> environment difference; the wrapper restores PATH itself, so check the tool's own error output
- Manual run fails too --> continue with sections 2 and 3

---

## 2. No Audio Output

**Symptom**: The log shows the request, but no sound is heard.

**Diagnostic Steps**:

```bash
# Step 1: Check whether a lock file is blocking playback
ls -la /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock 2>/dev/null

# Step 2: Check if any audio process is active
pgrep -la afplay

# Step 3: Check macOS audio output (is sound muted?)
osascript -e 'output volume of (get volume settings)'

# Step 4: Test raw audio playback
afplay /System/Library/Sounds/Tink.aiff
```

**Resolution Tree**:

- Lock file exists + stale mtime (>30s) + no audio process --> `tts_stop.sh`
- Lock file exists + fresh mtime --> Another utterance is in progress; wait, or `tts_stop.sh`
- No lock + no audio + system sound works --> Check `/tmp/kokoro-tts.log` and `/tmp/tts_errors.log` for the engine error
- System sound does not play --> macOS audio issue (check Sound preferences, output device)

---

## 3. Wrong Engine or Slow Start

**Symptom**: Speech starts after a noticeable delay, or subtitles do not appear.

**Diagnostic Steps**:

```bash
grep -E 'engine=' /tmp/kokoro-tts.log | tail -5
curl -s --max-time 2 "http://[::1]:8780/health" || echo "companion down"
```

**Resolution Tree**:

- `engine=supertonic` with the companion down --> start `claude-tts-companion` (its own plugin); the fallback is working as designed
- `engine=supertonic` with the companion up --> `TTS_ENGINE=supertonic` is set somewhere in the hotkey's environment
- `engine=kokoro` but slow --> the companion's Kokoro server is warming up after a restart; see the companion's own diagnostics

---

## 4. Speed Keys Have No Effect

**Symptom**: Faster/slower keys play the confirmation sound but speech speed does not change.

**Diagnostic Steps**:

```bash
grep 'speed:' /tmp/kokoro-tts.log | tail -5
```

**Resolution Tree**:

- `companion unreachable — kokoro speed NOT applied` --> the rate reached the BetterTouchTool variable (Supertonic) but not the companion; press again once the companion is up
- No `speed:` lines --> the key is not bound to `tts_speed_up.sh` / `tts_speed_down.sh`
- Lines present, speed unchanged --> the multiplier is clamped to [0.5, 3.0]; check you are not already at a limit

---

## 5. Kokoro Timeout (local engine)

**Symptom**: `tts_kokoro_audition.sh` or a manual `tts_generate.py` run hangs or times out.

**Diagnostic Steps**:

```bash
# Step 1: Check if model is cached
ls -la ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/ 2>/dev/null

# Step 2: Test manual generation with timing
time ~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Test" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-tts-timeout-test.wav

# Step 3: Check MLX-Audio is importable
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('MLX OK')"
```

**Resolution Tree**:

- Model not cached --> First run downloads from HuggingFace. Wait or run `kokoro-install.sh --install`
- MLX-Audio not importable --> `kokoro-install.sh --upgrade` to reinstall dependencies

---

## 6. Lock Stuck Forever

**Symptom**: Presses queue up and nothing ever plays; a lock file never disappears.

See [Lock Debugging](./lock-debugging.md) for the full protocol. Quick resolution:

```bash
stat -f "%Sm" /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock 2>/dev/null
pgrep -x afplay

# Safe reset: kills playback and queued scripts, clears both locks, cancels the companion queue
~/.local/bin/tts_stop.sh
```

---

## 7. Slow MLX Metal Acceleration

**Symptom**: Local Kokoro generation is slow (~5-10s instead of ~1-2s).

**Diagnostic Steps**:

```bash
~/.local/share/kokoro/.venv/bin/python -c "
from mlx_audio.tts.utils import load_model
from importlib.metadata import version
print('mlx-audio version:', version('mlx-audio'))
print('MLX OK')
"
~/.local/share/kokoro/.venv/bin/python --version
uname -m  # Should be arm64
```

**Resolution Tree**:

- Not arm64 --> MLX-Audio requires Apple Silicon (M1+). No Intel/Linux fallback.
- Wrong Python version --> Must be 3.14. Rebuild venv: `kokoro-install.sh --uninstall && kokoro-install.sh --install`
- MLX OK but still slow --> Check if other GPU-heavy processes are running, or if the model needs re-download

---

## 8. Double Audio Playback

**Symptom**: The same text plays twice, or two outputs overlap.

**Diagnostic Steps**:

```bash
pgrep -la afplay
ls -la /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock 2>/dev/null
grep -E 'engine=' /tmp/kokoro-tts.log | tail -5
```

**Resolution Tree**:

- Multiple afplay processes --> `tts_stop.sh`, then press once
- Two `engine=` lines per press --> two bindings fire the wrapper (for example both Karabiner-Elements and BetterTouchTool); remove one
- Kokoro and Supertonic both spoke --> the wrapper exits on the Kokoro path's status; check for a locally modified copy that pipes into `exec`
