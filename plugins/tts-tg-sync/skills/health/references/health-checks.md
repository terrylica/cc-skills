# Health Checks Reference

Detailed documentation for each of the 10 text-to-speech health checks. The Telegram bot checks that used to be here (bot process, Telegram API, bot secrets file) were removed on 2026-09-26; the bot was retired on 2026-09-24.

---

## Check 1: Companion Engine

**What it tests**: Whether `claude-tts-companion`, the resident Kokoro engine the hotkey prefers, answers on its HTTP control API.

**Command**:

```bash
curl -s --max-time 2 "http://[::1]:8780/health"
```

**Pass condition**: Any successful response.

**Failure meaning**: The companion is not running or not listening. `tts_read_clipboard_wrapper.sh` then falls back to Supertonic, which spawns uv and loads its model on every press, so speech still works but starts slower and shows no subtitles. `tts_kokoro.sh` called directly fails outright.

**Remediation**: Start or repair the companion through the `claude-tts-companion` plugin. Nothing in this plugin manages its process.

---

## Check 2: Kokoro venv

**What it tests**: Whether the Python virtual environment for the local Kokoro engine exists.

**Command**:

```bash
[[ -d ~/.local/share/kokoro/.venv ]]
```

**Pass condition**: Directory exists.

**Failure meaning**: Kokoro has never been installed, or the venv was deleted/corrupted. Only `tts_kokoro_audition.sh` and manual `tts_generate.py` runs depend on it.

**Remediation**:

- Run `kokoro-install.sh --install` to install Kokoro from scratch.

---

## Check 3: MLX-Audio Import

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

- Reinstall: `kokoro-install.sh --upgrade`
- Rebuild venv if Python version is wrong: `kokoro-install.sh --uninstall` then `--install`.

---

## Check 4: Apple Silicon

**What it tests**: Whether the system is Apple Silicon with MLX Metal acceleration available.

**Command**:

```bash
[[ "$(uname -m)" == "arm64" ]]
```

**Pass condition**: Architecture is arm64 (Apple Silicon).

**Remediation**: MLX-Audio only runs on Apple Silicon (M1+). There is no Intel or Linux fallback.

---

## Check 5: Lock State

**What it tests**: The two lock files the scripts use.

| Lock                   | Holder                                                                    | Released by                                    |
| ---------------------- | ------------------------------------------------------------------------- | ---------------------------------------------- |
| `/tmp/tts_kokoro.lock` | `tts_kokoro.sh` (a `shlock` queue: one request at a time)                 | its EXIT trap, or `tts_stop.sh`                |
| `/tmp/kokoro-tts.lock` | `tts_read_clipboard.sh` (Supertonic) and `tts-common.sh` users (audition) | release on exit, stale-check, or `tts_stop.sh` |

**Command**: see check 5 in [SKILL.md](../SKILL.md).

**States**:

| State    | Lock file | PID alive | Age   | Meaning                           |
| -------- | --------- | --------- | ----- | --------------------------------- |
| NO LOCK  | absent    | n/a       | n/a   | System idle, no TTS in progress   |
| ACTIVE   | present   | yes       | < 30s | TTS in progress, normal           |
| STALE    | present   | yes       | > 30s | Lock not refreshed, possible hang |
| ORPHANED | present   | no        | any   | Process crashed, lock left behind |

**Pass condition**: NO LOCK or ACTIVE with age < 30s, for both files. A long Kokoro utterance legitimately holds `/tmp/tts_kokoro.lock` for longer than 30s, so treat STALE on that file as a failure only when no `afplay` is running and the companion reports nothing playing.

**Remediation**:

- Orphaned: `tts_stop.sh` clears both locks and cancels the companion's queue.
- Stale with live PID: Investigate the process (`ps -p PID`), then run `tts_stop.sh` if stuck.
- See `diagnostic-issue-resolver` skill for detailed lock debugging.

---

## Check 6: Audio Processes

**What it tests**: Whether `afplay` (audio file playback) or `say` processes are running.

**Command**:

```bash
pgrep -x afplay
pgrep -x say
```

**Note**: This is an **informational check**, not a strict pass/fail. Running audio processes are normal during playback.

**Interpretation**:

- **0 afplay, 0 say**: System idle, no audio playing.
- **1+ afplay**: WAV playback (Supertonic, audition, or the signal sound).
- **1+ say**: Something outside this plugin; the scripts follow a Kokoro-only policy and never call `say`.
- **Many afplay**: Possible queue buildup, may indicate stuck playback.

**Remediation** (if stuck): `tts_stop.sh`

---

## Check 7: Stale WAV Files

**What it tests**: Whether orphaned TTS output files exist in `/tmp` from crashed generation runs.

**Command**:

```bash
find /tmp -maxdepth 1 -name "kokoro-tts-*.wav" -mmin +5 2>/dev/null
```

**Pass condition**: No files found (all WAVs either cleaned up or less than 5 minutes old).

**Remediation**:

- Clean up: `rm /tmp/kokoro-tts-*.wav`
- If recurring, investigate why the generating process crashed (check `/tmp/kokoro-tts.log`).

---

## Check 8: Shell Links

**What it tests**: Whether the links hotkeys call exist in `~/.local/bin/` and resolve into the plugin.

**Command**: see check 8 in [SKILL.md](../SKILL.md).

**Pass condition**: Every link exists and resolves. `tts_speed_set.sh` needs no link: the speed scripts resolve their own real directory and call it from there.

**Failure meaning**:

- **Link missing**: Bootstrap incomplete or links were never created.
- **Link dangling**: The plugin moved (for example a checkout was relocated).

**Remediation**: Re-run the link step from the `setup` or `full-stack-bootstrap` skill.

---

## Check 9: Hotkey Binding

**What it tests**: Whether a Karabiner-Elements rule calls the read-aloud wrapper.

**Command**:

```bash
grep -c "tts_read_clipboard_wrapper.sh" ~/.config/karabiner/karabiner.json
```

**Note**: Informational. Zero hits is fine when BetterTouchTool holds the binding instead; BetterTouchTool's configuration is not a plain file this check can read.

**Remediation**: Bind the key to `~/.local/bin/tts_read_clipboard_wrapper.sh` (see Phase 3 of `full-stack-bootstrap`).

---

## Check 10: Supertonic Fallback

**What it tests**: Whether the fallback engine can start when the companion is down.

**Command**: see check 10 in [SKILL.md](../SKILL.md).

**Pass condition**: `uv` resolves from Homebrew, `~/.local/bin` or proto. A missing `~/.cache/supertonic2/onnx` only means the first fallback run downloads the model.

**Remediation**: `brew install uv`.
