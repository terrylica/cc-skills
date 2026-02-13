# Health Checks Reference

Detailed documentation for each of the 10 system health checks.

---

## Check 1: Bot Process

**What it tests**: Whether the Telegram sync bot is running as a `bun --watch` process.

**Command**:

```bash
pgrep -la 'bun.*src/main.ts'
```

**Pass condition**: Exactly one matching process found.

**Failure meaning**:

- **Zero processes**: Bot is not running. It may have crashed, been manually stopped, or never started.
- **Multiple processes**: Duplicate instances are running, likely from repeated start commands without stopping first.

**Remediation**:

- Zero: Start bot with `cd ~/.claude/automation/claude-telegram-sync && bun --watch run src/main.ts >> /private/tmp/telegram-bot.log 2>&1 &`
- Multiple: `pkill -f 'bun.*src/main.ts'` then start fresh. See `bot-process-control` skill.

---

## Check 2: Telegram API

**What it tests**: Whether the Telegram Bot API is reachable and the bot token is valid.

**Command**:

```bash
BOT_TOKEN=$(cat ~/.claude/.secrets/ccterrybot-telegram)
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | jq .ok
```

**Pass condition**: Response contains `"ok": true`.

**Failure meaning**:

- **`false` or `401`**: Token is invalid or expired. The token file may be corrupted or the bot was deleted from BotFather.
- **Connection error**: Network issue, DNS failure, or Telegram API outage.
- **Empty response**: Secrets file missing or empty.

**Remediation**:

- Verify token file exists: `[[ -f ~/.claude/.secrets/ccterrybot-telegram ]] && echo exists`
- Test token manually: `curl -s "https://api.telegram.org/bot$(cat ~/.claude/.secrets/ccterrybot-telegram)/getMe"`
- Regenerate token via Telegram BotFather if expired.

---

## Check 3: Kokoro venv

**What it tests**: Whether the Python virtual environment for Kokoro TTS exists.

**Command**:

```bash
[[ -d ~/.local/share/kokoro/.venv ]]
```

**Pass condition**: Directory exists.

**Failure meaning**: Kokoro has never been installed, or the venv was deleted/corrupted.

**Remediation**:

- Run the `full-stack-bootstrap` skill to install Kokoro from scratch.
- Or manually: `cd ~/.local/share/kokoro && uv venv --python 3.13 .venv && uv pip install kokoro torch`

---

## Check 4: Kokoro Python Import

**What it tests**: Whether the `kokoro` Python package is importable within the venv.

**Command**:

```bash
~/.local/share/kokoro/.venv/bin/python -c "import kokoro"
```

**Pass condition**: Exit code 0 (import succeeds).

**Failure meaning**:

- **ModuleNotFoundError**: Package not installed in the venv.
- **ImportError**: Dependency conflict or corrupt installation.
- **SyntaxError**: Python version mismatch (wrong Python in venv).

**Remediation**:

- Reinstall: `~/.local/share/kokoro/.venv/bin/pip install kokoro`
- Rebuild venv if Python version is wrong: delete `.venv` and recreate with Python 3.13.

---

## Check 5: MPS Available (Apple Silicon GPU)

**What it tests**: Whether PyTorch can access the Metal Performance Shaders backend for GPU-accelerated TTS inference.

**Command**:

```bash
~/.local/share/kokoro/.venv/bin/python -c "import torch; assert torch.backends.mps.is_available()"
```

**Pass condition**: Assertion passes (MPS is available).

**Failure meaning**:

- **AssertionError**: MPS not available. Could be Intel Mac, or torch built without MPS support.
- **ModuleNotFoundError (torch)**: PyTorch not installed in the venv.

**Remediation**:

- Verify hardware: `sysctl -n machdep.cpu.brand_string` (should show Apple M-series).
- Reinstall torch with MPS: `~/.local/share/kokoro/.venv/bin/pip install torch --upgrade`
- MPS requires macOS 12.3+ and Apple Silicon.

**Note**: Kokoro still works on CPU if MPS is unavailable, but inference will be significantly slower.

---

## Check 6: Lock State

**What it tests**: The state of the TTS lock file used to coordinate access to the Kokoro engine.

**Command**:

```bash
LOCK_FILE="/tmp/kokoro-tts.lock"
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_PID=$(cat "$LOCK_FILE")
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE") ))
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "ACTIVE (PID $LOCK_PID, age ${LOCK_AGE}s)"
  else
    echo "ORPHANED (PID $LOCK_PID not running)"
  fi
else
  echo "NO LOCK"
fi
```

**States**:

| State    | Lock file | PID alive | Age   | Meaning                            |
| -------- | --------- | --------- | ----- | ---------------------------------- |
| NO LOCK  | absent    | n/a       | n/a   | System idle, no TTS in progress    |
| ACTIVE   | present   | yes       | < 30s | TTS generation in progress, normal |
| STALE    | present   | yes       | > 30s | Lock not refreshed, possible hang  |
| ORPHANED | present   | no        | any   | Process crashed, lock left behind  |

**Pass condition**: NO LOCK or ACTIVE with age < 30s.

**Failure meaning**: STALE or ORPHANED locks prevent new TTS requests from being processed.

**Remediation**:

- Orphaned: `rm /tmp/kokoro-tts.lock`
- Stale with live PID: Investigate the process (`ps -p PID`), then kill if stuck.
- See `diagnostic-issue-resolver` skill for detailed lock debugging.

---

## Check 7: Audio Processes

**What it tests**: Whether `afplay` (audio file playback) or `say` (macOS text-to-speech) processes are running.

**Command**:

```bash
pgrep -x afplay
pgrep -x say
```

**Note**: This is an **informational check**, not a strict pass/fail. Running audio processes are normal during TTS playback.

**Interpretation**:

- **0 afplay, 0 say**: System idle, no audio playing.
- **1+ afplay**: WAV file being played back (normal during TTS output).
- **1+ say**: macOS system TTS active (fallback mode or separate invocation).
- **Many afplay**: Possible queue buildup, may indicate stuck playback.

**Remediation** (if stuck):

- Kill stuck audio: `pkill -x afplay` and `pkill -x say`

---

## Check 8: Secrets File

**What it tests**: Whether the Telegram bot token file exists and is non-empty.

**Command**:

```bash
[[ -f ~/.claude/.secrets/ccterrybot-telegram ]] && [[ -s ~/.claude/.secrets/ccterrybot-telegram ]]
```

**Pass condition**: File exists and is non-empty.

**Failure meaning**:

- **File missing**: Secrets never configured, or accidentally deleted.
- **File empty**: Token was cleared or file was truncated.

**Remediation**:

- Retrieve token from Telegram BotFather or from Doppler/1Password backup.
- Write token: `echo -n "YOUR_TOKEN" > ~/.claude/.secrets/ccterrybot-telegram && chmod 600 ~/.claude/.secrets/ccterrybot-telegram`

---

## Check 9: Stale WAV Files

**What it tests**: Whether orphaned TTS output files exist in `/tmp` from crashed generation runs.

**Command**:

```bash
find /tmp -maxdepth 1 -name "kokoro-tts-*.wav" -mmin +5 2>/dev/null
```

**Pass condition**: No files found (all WAVs either cleaned up or less than 5 minutes old).

**Failure meaning**: A TTS generation process crashed or was killed before it could clean up its temporary WAV file. These files consume disk space and may indicate a recurring crash pattern.

**Remediation**:

- Clean up: `rm /tmp/kokoro-tts-*.wav`
- Investigate why the generating process crashed (check logs).
- If recurring, there may be a memory or timeout issue in the Kokoro pipeline.

---

## Check 10: Shell Symlinks

**What it tests**: Whether the TTS shell script symlinks are properly installed in `~/.local/bin/`.

**Command**:

```bash
[[ -L ~/.local/bin/tts_kokoro.sh ]] && readlink ~/.local/bin/tts_kokoro.sh
```

**Pass condition**: Symlink exists and points to a valid file within the plugin scripts directory.

**Failure meaning**:

- **Symlink missing**: Bootstrap incomplete or symlinks were never created.
- **Symlink broken** (dangling): Target script was moved or deleted.

**Remediation**:

- Re-run the symlink creation step from the `full-stack-bootstrap` skill.
- Or manually: `ln -sf /path/to/plugin/scripts/tts_kokoro.sh ~/.local/bin/tts_kokoro.sh`
- Verify `~/.local/bin` is in `PATH`.
