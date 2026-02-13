# Common Issues -- Expanded Diagnostic Procedures

Detailed step-by-step procedures for diagnosing and resolving each known issue.

---

## 1. No Audio Output

**Symptom**: TTS generates silently -- no sound is heard.

**Diagnostic Steps**:

```bash
# Step 1: Check if lock file is blocking playback
ls -la /tmp/kokoro-tts.lock 2>/dev/null
stat -f "%Sm %N" /tmp/kokoro-tts.lock 2>/dev/null

# Step 2: Check if any audio process is active
pgrep -la afplay
pgrep -la say

# Step 3: Check macOS audio output (is sound muted?)
osascript -e 'output volume of (get volume settings)'

# Step 4: Test raw audio playback
afplay /System/Library/Sounds/Tink.aiff
```

**Resolution Tree**:

- Lock file exists + stale mtime (>30s) + no audio process --> Remove lock: `rm -f /tmp/kokoro-tts.lock`
- Lock file exists + fresh mtime --> Another TTS is in progress, wait for it to finish
- No lock + no audio + system sound works --> Check bot logs for generation errors
- System sound does not play --> macOS audio issue (check Sound preferences, output device)

---

## 2. Bot Not Responding

**Symptom**: Telegram messages are sent but bot does not reply.

**Diagnostic Steps**:

```bash
# Step 1: Check if bot process is running
pgrep -la 'bun.*src/main.ts'

# Step 2: Check recent log output
tail -30 /private/tmp/telegram-bot.log 2>/dev/null

# Step 3: Check if bun is available
which bun && bun --version

# Step 4: Check network (Telegram API reachable)
curl -s -o /dev/null -w "%{http_code}" https://api.telegram.org/
```

**Resolution Tree**:

- No process found --> Restart: `cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts &`
- Process running but not responding --> Check logs for error loops, consider restart
- Network unreachable --> Check internet connectivity
- Bun not found --> `mise install` in the bot directory

---

## 3. Kokoro Timeout

**Symptom**: TTS generation hangs or times out after `TTS_GENERATE_TIMEOUT_MS` (default 15s).

**Diagnostic Steps**:

```bash
# Step 1: Check if model is cached
ls -la ~/.cache/huggingface/hub/models--hexgrad--Kokoro-82M/ 2>/dev/null

# Step 2: Test manual generation with verbose output
time ~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
  --text "Test" --voice af_heart --lang en-us --speed 1.0 \
  --output /tmp/kokoro-tts-timeout-test.wav

# Step 3: Check MPS (slow generation may indicate CPU fallback)
~/.local/share/kokoro/.venv/bin/python -c "import torch; print('MPS:', torch.backends.mps.is_available())"
```

**Resolution Tree**:

- Model not cached --> First run downloads ~400MB. Wait or run `kokoro-install.sh --install`
- MPS not available --> `kokoro-install.sh --upgrade` to reinstall torch with MPS support
- Generation works manually but times out from bot --> Increase `TTS_GENERATE_TIMEOUT_MS` in mise.toml

---

## 4. Queue Full / Backed Up

**Symptom**: New TTS requests are dropped with "Dropped stale item" in logs.

**Diagnostic Steps**:

```bash
# Step 1: Check audit log for queue events
grep -h 'tts.drop\|tts.enqueue\|tts.drain' \
  ~/.local/share/tts-telegram-sync/logs/audit/*.ndjson 2>/dev/null | tail -20

# Step 2: Check current queue config
grep TTS_MAX_QUEUE_DEPTH ~/.claude/automation/claude-telegram-sync/mise.toml
grep TTS_STALE_TTL_MS ~/.claude/automation/claude-telegram-sync/mise.toml
```

**Resolution Tree**:

- Frequent drops --> Increase `TTS_MAX_QUEUE_DEPTH` in mise.toml (default: 5)
- Items going stale --> Decrease `TTS_STALE_TTL_MS` or investigate why generation is slow
- Burst of notifications --> Normal during rapid prompting; queue is working as designed

---

## 5. Lock Stuck Forever

**Symptom**: TTS never starts; lock file never disappears.

See [Lock Debugging](./lock-debugging.md) for the full protocol. Quick resolution:

```bash
# Check lock state
stat -f "%Sm" /tmp/kokoro-tts.lock 2>/dev/null
pgrep -x afplay
pgrep -x say

# If lock is stale (>30s) AND no audio process: safe to remove
rm -f /tmp/kokoro-tts.lock
```

---

## 6. No MPS Acceleration

**Symptom**: TTS generation is slow (~5-10s instead of ~1-2s).

**Diagnostic Steps**:

```bash
# Step 1: Check MPS availability
~/.local/share/kokoro/.venv/bin/python -c "
import torch
print('MPS available:', torch.backends.mps.is_available())
print('MPS built:', torch.backends.mps.is_built())
print('Torch version:', torch.__version__)
"

# Step 2: Check Python version
~/.local/share/kokoro/.venv/bin/python --version
```

**Resolution Tree**:

- MPS not available --> `kokoro-install.sh --upgrade` (reinstalls torch with MPS)
- Wrong Python version --> Must be 3.13. Rebuild venv: `kokoro-install.sh --uninstall && kokoro-install.sh --install`
- MPS available but still slow --> Check if other GPU-heavy processes are running

---

## 7. Double Audio Playback

**Symptom**: The same text plays twice, or two different TTS outputs overlap.

**Diagnostic Steps**:

```bash
# Step 1: Check for multiple audio processes
pgrep -la afplay
pgrep -la say

# Step 2: Check for lock file
ls -la /tmp/kokoro-tts.lock 2>/dev/null

# Step 3: Check audit log for race conditions
grep -h 'tts.play.start' \
  ~/.local/share/tts-telegram-sync/logs/audit/*.ndjson 2>/dev/null | tail -10
```

**Resolution Tree**:

- Multiple afplay processes --> Kill all: `pkill -x afplay`, then check what triggered them
- Bot + shell script racing --> The lock protocol should prevent this. Check if both are acquiring locks properly
- Same notification processed twice --> Check bot logs for duplicate webhook deliveries
