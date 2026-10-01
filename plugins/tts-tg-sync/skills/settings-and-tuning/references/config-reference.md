# Configuration Reference

Every knob the text-to-speech scripts read, where it lives, its default and valid range. There is no central config file: each value is read by the script that needs it, from a BetterTouchTool variable, the companion's persisted settings, or the environment of the hotkey command.

The Telegram bot's variables that used to fill this page (notification rate limiting, summarizer and prompt-executor throttling, session picker, bot TTS queue and timeouts, audit retention, `HAIKU_MODEL`) and the `moon.yml` / `.env` layering that carried them were removed on 2026-09-26 with the retired bot.

---

## Speech Rate

| Setting                     | Default | Valid Range       | Read by                                                                 |
| --------------------------- | ------- | ----------------- | ----------------------------------------------------------------------- |
| `TTS_SPEECH_RATE` (BTT var) | `220`   | `90` to `500` WPM | `tts_read_clipboard_wrapper.sh`, `tts_speed_up.sh`, `tts_speed_down.sh` |
| Companion `speed`           | `1.0`   | `0.5` to `3.0`    | `claude-tts-companion` (set via `POST /settings/tts`)                   |

**Notes**:

- Change the rate only through `tts_speed_set.sh <wpm>` (or the up/down/reset scripts that call it). It is the one place that updates both engines: the BetterTouchTool variable for Supertonic, and `speed = wpm / 220` for the companion.
- 220 WPM is Kokoro speed 1.0. Because WPM is clamped to 90-500 first, the companion never receives more than ~2.27.
- Without BetterTouchTool the variable cannot be read or written, and every script falls back to 220 WPM.
- `tts_read_clipboard.sh` also honours a `SPEECH_RATE` environment variable, but the wrapper always sets it from the BetterTouchTool variable, so on the hotkey path the variable wins.

## Engine Selection

| Variable     | Default | Valid Values                   | Read by                         |
| ------------ | ------- | ------------------------------ | ------------------------------- |
| `TTS_ENGINE` | `auto`  | `auto`, `kokoro`, `supertonic` | `tts_read_clipboard_wrapper.sh` |

**Notes**:

- `auto` uses the companion when `http://[::1]:8780/health` answers within 2s, otherwise Supertonic.
- `kokoro` fails loudly if the companion is down; `supertonic` never contacts it.

## Voices

| What                  | Where                                                 |
| --------------------- | ----------------------------------------------------- |
| Hotkey (Kokoro) voice | The companion's own settings (`claude-tts-companion`) |
| Supertonic voice      | Fixed to style `M3` in `tts_supertonic_speak.py`      |
| Audition voices       | The `VOICES` array in `tts_kokoro_audition.sh`        |

See the [voice catalog](../../voice-quality-audition/references/voice-catalog.md) for grades.

## Supertonic Fallback

| Variable             | Default  | Valid Range    | Read by                                                                    |
| -------------------- | -------- | -------------- | -------------------------------------------------------------------------- |
| `MAX_CONTENT_LENGTH` | `100000` | characters     | `tts_read_clipboard.sh`                                                    |
| `DEBUG`              | `0`      | `0` or `1`     | `tts_read_clipboard.sh` (writes `/tmp/tts_debug.log`)                      |
| `TTS_SPEED`          | derived  | `0.5` to `3.0` | `tts_supertonic_speak.py` (set by the caller from WPM: `wpm × 1.25 / 220`) |

## Local Kokoro (audition)

| Variable        | Default                                 | Read by                  |
| --------------- | --------------------------------------- | ------------------------ |
| `KOKORO_VENV`   | `~/.local/share/kokoro/.venv`           | `tts_kokoro_audition.sh` |
| `KOKORO_SCRIPT` | `~/.local/share/kokoro/tts_generate.py` | `tts_kokoro_audition.sh` |
| `TTS_LOCK`      | `/tmp/kokoro-tts.lock`                  | `lib/tts-common.sh`      |
| `LOG`           | `/tmp/kokoro-tts.log`                   | `lib/tts-common.sh`      |

## Defined But Not Currently Read

These exist in the scripts but no entry script uses them today, so setting them changes nothing:

| Variable               | Where defined           | Why inert                                       |
| ---------------------- | ----------------------- | ----------------------------------------------- |
| `TTS_SIGNAL_SOUND`     | `lib/tts-common.sh`     | `play_tts_signal()` is not called by any script |
| `EN_VOICE`, `ZH_VOICE` | `lib/tts-common.sh`     | `detect_language()` is not called by any script |
| `PAUSE_DURATION`       | `tts_read_clipboard.sh` | Assigned, never used                            |

The speed keys' confirmation sound is hard-coded to `/System/Library/Sounds/Tink.aiff` in `tts_speed_set.sh`.
