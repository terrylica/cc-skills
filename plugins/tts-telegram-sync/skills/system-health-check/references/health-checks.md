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

- Run `kokoro-install.sh --install` to install Kokoro from scratch.
- Or manually: `cd ~/.local/share/kokoro && uv venv --python 3.13 .venv && uv pip install mlx-audio soundfile numpy`

---

## Check 4: MLX-Audio Import

**What it tests**: Whether the `mlx_audio` Python package is importable within the venv.

**Command**:

```bash
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('MLX OK')"
```

**Pass condition**: Exit code 0 (import succeeds).

**Failure meaning**:

- **ModuleNotFoundError**: Package not installed in the venv.
- **ImportError**: Dependency conflict or corrupt installation.
- **SyntaxError**: Python version mismatch (wrong Python in venv).

**Remediation**:

- Reinstall: `uv pip install --python ~/.local/share/kokoro/.venv/bin/python mlx-audio`
- Rebuild venv if Python version is wrong: delete `.venv` and recreate with Python 3.13.

---

## Check 5: MLX Metal (Apple Silicon GPU)

**What it tests**: Whether the system is Apple Silicon with MLX Metal acceleration available.

**Command**:

```bash
[[ "$(uname -m)" == "arm64" ]]
```

**Pass condition**: Architecture is arm64 (Apple Silicon).

**Failure meaning**:

- **Not arm64**: Intel Mac or non-macOS system. MLX-Audio requires Apple Silicon.

**Remediation**:

- Verify hardware: `uname -m` (should show `arm64`).
- MLX-Audio only runs on Apple Silicon (M1+). There is no Intel or Linux fallback.

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
