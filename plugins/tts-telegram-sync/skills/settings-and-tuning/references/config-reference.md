# Configuration Reference

Complete reference for all environment variables in `~/.claude/automation/claude-telegram-sync/mise.toml`.

## Config SSoT

All settings live in the `[env]` section of `mise.toml`. The bot and shell scripts read these as environment variables. All values are strings in TOML (mise convention).

---

## TTS Voice Configuration

| Variable           | Default      | Valid Values             | Component              |
| ------------------ | ------------ | ------------------------ | ---------------------- |
| `TTS_VOICE_EN`     | `af_heart`   | Any Kokoro voice name    | tts_kokoro.sh, bot TTS |
| `TTS_VOICE_ZH`     | `zf_xiaobei` | Any Kokoro Chinese voice | tts_kokoro.sh, bot TTS |
| `TTS_VOICE_SAY_EN` | `Samantha`   | macOS `say` voice name   | tts_read_clipboard.sh  |
| `TTS_VOICE_SAY_ZH` | `Ting-Ting`  | macOS `say` voice name   | tts_read_clipboard.sh  |

**Notes**:

- Kokoro voices are case-sensitive. Use `tts_kokoro_audition.sh` to preview voices.
- macOS `say` voices: list available with `say -v '?'`
- `TTS_VOICE_EN` and `TTS_VOICE_ZH` are used by the Kokoro engine (higher quality)
- `TTS_VOICE_SAY_EN` and `TTS_VOICE_SAY_ZH` are fallback voices using macOS `say`

## TTS Speed

| Variable    | Default | Valid Range    | Component              |
| ----------- | ------- | -------------- | ---------------------- |
| `TTS_SPEED` | `1.25`  | `0.5` to `2.0` | tts_kokoro.sh, bot TTS |

**Notes**:

- `1.0` is normal speed
- `1.25` is the default (slightly faster for efficiency)
- Values below `0.5` or above `2.0` may produce distorted audio

## TTS Timeouts

| Variable                  | Default | Valid Range         | Component         |
| ------------------------- | ------- | ------------------- | ----------------- |
| `TTS_GENERATE_TIMEOUT_MS` | `15000` | `5000` to `60000`   | bot kokoro-client |
| `TTS_SAY_TIMEOUT_MS`      | `60000` | `10000` to `300000` | bot kokoro-client |

**Notes**:

- `TTS_GENERATE_TIMEOUT_MS`: Maximum time to wait for Kokoro to generate a WAV chunk
- `TTS_SAY_TIMEOUT_MS`: Maximum time for the entire TTS playback (all chunks)
- First-run generation is slower due to model warmup; subsequent calls are faster

## TTS Queue

| Variable              | Default  | Valid Range         | Component     |
| --------------------- | -------- | ------------------- | ------------- |
| `TTS_MAX_QUEUE_DEPTH` | `5`      | `1` to `20`         | bot TTS queue |
| `TTS_STALE_TTL_MS`    | `120000` | `30000` to `600000` | bot TTS queue |
| `TTS_MAX_TEXT_LEN`    | `800`    | `100` to `5000`     | bot TTS queue |

**Notes**:

- `TTS_MAX_QUEUE_DEPTH`: Maximum pending TTS jobs. New requests are dropped if queue is full.
- `TTS_STALE_TTL_MS`: Time-to-live for queued items. Stale items are discarded (2 min default).
- `TTS_MAX_TEXT_LEN`: Maximum text length accepted for TTS. Longer text is truncated.

## TTS Signal Sound

| Variable           | Default                            | Valid Range                       | Component     |
| ------------------ | ---------------------------------- | --------------------------------- | ------------- |
| `TTS_SIGNAL_SOUND` | `/System/Library/Sounds/Tink.aiff` | Any `.aiff`/`.wav` path, or empty | tts-common.sh |

**Notes**:

- Plays a short sound to indicate TTS is processing (non-blocking)
- Set to empty string `""` to disable the signal sound
- macOS system sounds are in `/System/Library/Sounds/`

## Notification Rate Limiting

| Variable                        | Default  | Valid Range          | Component                |
| ------------------------------- | -------- | -------------------- | ------------------------ |
| `NOTIFICATION_MIN_INTERVAL_MS`  | `5000`   | `1000` to `60000`    | bot notification-watcher |
| `SUMMARIZER_MIN_INTERVAL_MS`    | `10000`  | `5000` to `120000`   | bot summarizer           |
| `SUMMARIZER_CIRCUIT_BREAKER_MS` | `300000` | `60000` to `3600000` | bot summarizer           |
| `SUMMARIZER_MAX_FAILURES`       | `3`      | `1` to `10`          | bot summarizer           |

**Notes**:

- `NOTIFICATION_MIN_INTERVAL_MS`: Minimum gap between Telegram notifications (prevents spam)
- `SUMMARIZER_MIN_INTERVAL_MS`: Minimum gap between summarization API calls
- `SUMMARIZER_CIRCUIT_BREAKER_MS`: Cooldown period after `SUMMARIZER_MAX_FAILURES` consecutive failures (5 min default)
- Circuit breaker resets after the cooldown period, allowing retries

## Prompt Executor

| Variable                      | Default  | Valid Range          | Component           |
| ----------------------------- | -------- | -------------------- | ------------------- |
| `PROMPT_MIN_INTERVAL_MS`      | `30000`  | `10000` to `300000`  | bot prompt-executor |
| `PROMPT_EXECUTION_TIMEOUT_MS` | `120000` | `30000` to `600000`  | bot prompt-executor |
| `PROMPT_EDIT_THROTTLE_MS`     | `1500`   | `500` to `10000`     | bot prompt-executor |
| `PROMPT_CIRCUIT_BREAKER_MS`   | `600000` | `60000` to `3600000` | bot prompt-executor |
| `PROMPT_MAX_FAILURES`         | `3`      | `1` to `10`          | bot prompt-executor |

**Notes**:

- `PROMPT_MIN_INTERVAL_MS`: Minimum gap between prompt executions (30s default)
- `PROMPT_EXECUTION_TIMEOUT_MS`: Maximum time for a single prompt execution (2 min default)
- `PROMPT_EDIT_THROTTLE_MS`: Debounce for edit detection (prevents rapid re-execution)
- `PROMPT_CIRCUIT_BREAKER_MS`: Cooldown after consecutive failures (10 min default)

## Session Picker

| Variable                 | Default  | Valid Range          | Component          |
| ------------------------ | -------- | -------------------- | ------------------ |
| `SESSION_SCAN_LIMIT`     | `200`    | `50` to `1000`       | bot session-lister |
| `SESSION_DISPLAY_LIMIT`  | `30`     | `5` to `100`         | bot session-lister |
| `SESSION_MAX_AGE_DAYS`   | `7`      | `1` to `90`          | bot session-lister |
| `SESSION_PENDING_TTL_MS` | `300000` | `60000` to `3600000` | bot session-lister |

**Notes**:

- `SESSION_SCAN_LIMIT`: Maximum sessions to scan from filesystem
- `SESSION_DISPLAY_LIMIT`: Maximum sessions shown in Telegram picker UI
- `SESSION_MAX_AGE_DAYS`: Sessions older than this are excluded
- `SESSION_PENDING_TTL_MS`: Time to wait for user to pick a session before timing out (5 min default)

## Audit Logging

| Variable               | Default | Valid Range  | Component |
| ---------------------- | ------- | ------------ | --------- |
| `AUDIT_RETENTION_DAYS` | `14`    | `1` to `365` | bot audit |

**Notes**:

- Audit logs older than this are eligible for cleanup
- Logs are stored in `~/.local/share/tts-telegram-sync/logs/audit/`

## Model Configuration

| Variable      | Default                     | Valid Range              | Component           |
| ------------- | --------------------------- | ------------------------ | ------------------- |
| `HAIKU_MODEL` | `claude-haiku-4-5-20251001` | Valid Anthropic model ID | bot Agent SDK calls |

**Notes**:

- Used for summarization and other Agent SDK calls in the bot
- Change this when a newer Haiku model is released
