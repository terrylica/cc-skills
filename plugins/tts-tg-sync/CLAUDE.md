# tts-tg-sync Plugin

> Hotkey-driven text-to-speech on macOS: read the clipboard aloud, change the speech rate, stop playback, audition Kokoro voices. Depends on `kokoro-tts` for the local engine installer.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gmail-commander CLAUDE.md](../gmail-commander/CLAUDE.md) | **Engine**: [kokoro-tts CLAUDE.md](../kokoro-tts/CLAUDE.md) | **Companion**: [claude-tts-companion CLAUDE.md](../claude-tts-companion/CLAUDE.md)

## Overview

This plugin is now **TTS only**. It ships the `tts_*` shell scripts that hotkeys call (linked into `~/.local/bin/`), their shared library, the bundled Kokoro CLI, and the skills that install, tune, diagnose and remove them.

The Telegram half is gone. The local Telegram sync bot this plugin used to manage (`claude-telegram-sync`) was retired on 2026-09-24, and on 2026-09-26 the plugin dropped every skill, hook and reference that installed, started, configured or health-checked it: `bot-process-control`, `tether`, the BotFather guide, the bot config architecture, and the `telegram-notify-stop.ts` Stop hook. The plugin keeps its name so existing installs and `~/.local/bin` links keep resolving; the `tg` in it is historical.

The Kokoro engine itself is managed by the `kokoro-tts` plugin — use `/kokoro-tts:install`, `/kokoro-tts:health`, `/kokoro-tts:augment` (renamed from `upgrade`), `/kokoro-tts:remove`, and `/kokoro-tts:diagnose` for engine management.

> **`scripts/kokoro-install.sh` is a thin delegating wrapper, not the SSoT** (2026-07-08). It `exec`s the canonical installer in the sibling `kokoro-tts` plugin (`../../kokoro-tts/scripts/kokoro-install.sh`) — reliable because both ship from the same cc-skills marketplace and this plugin `requires: [kokoro-tts]`. Edit the installer logic in `kokoro-tts` only; this wrapper just forwards `--install|--upgrade|--health|--uninstall`.

## How a keypress becomes speech

```
Hotkey (Karabiner-Elements shell_command, or a BetterTouchTool action)
  → ~/.local/bin/tts_read_clipboard_wrapper.sh
      restores a usable PATH, waits for the ⌘C to land (NSPasteboard changeCount),
      reads the speech rate from the BetterTouchTool variable TTS_SPEECH_RATE
      ├─ engine=kokoro (default when claude-tts-companion answers [::1]:8780/health)
      │    → tts_kokoro.sh → POST /tts/speak (the companion's resident Kokoro)
      └─ fallback: tts_read_clipboard.sh → uv run --with supertonic tts_supertonic_speak.py → afplay

Speed:     tts_speed_up.sh / tts_speed_down.sh / tts_speed_reset.sh → tts_speed_set.sh <wpm>
           (writes TTS_SPEECH_RATE for Supertonic AND POST /settings/tts {"speed": wpm/220} for Kokoro)
Stop:      tts_stop.sh (kills afplay and queued scripts, clears both locks, POST /tts/stop)
Audition:  tts_kokoro_audition.sh → local Kokoro venv (~/.local/share/kokoro) via tts_generate.py
```

`TTS_ENGINE=kokoro` or `TTS_ENGINE=supertonic` forces an engine; the default `auto` prefers the companion. The companion (a separate plugin, `claude-tts-companion`) owns the resident Kokoro server, its voice settings and the subtitle overlay; this plugin only calls its HTTP API.

## Conventions

- **Runtime**: Bash for the hotkey scripts, Python 3.14 for Kokoro and Supertonic (via uv)
- **Hotkey environment**: BetterTouchTool runs actions with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, so every entry script restores PATH itself — never assume a login shell
- **Paths**: XDG-compliant (`~/.local/share/kokoro/` for the engine, `~/.local/bin/` for the links)
- **Lock protocol**: `/tmp/tts_kokoro.lock` (`shlock` queue in `tts_kokoro.sh`) and `/tmp/kokoro-tts.lock` (Supertonic path and `tts-common.sh`, 5s heartbeat, 30s stale threshold + `afplay` check)
- **Signal sound**: the speed keys play a hard-coded `Tink.aiff`. `tts-common.sh` also defines `play_tts_signal` (`TTS_SIGNAL_SOUND`, empty to disable), but no entry script calls it today

## Key Paths

| Resource         | Path                                                                        |
| ---------------- | --------------------------------------------------------------------------- |
| Hotkey links     | `~/.local/bin/tts_*.sh` → this plugin's `scripts/`                          |
| Kokoro venv      | `~/.local/share/kokoro/.venv`                                               |
| Kokoro CLI       | `~/.local/share/kokoro/tts_generate.py`                                     |
| Companion API    | `http://[::1]:8780` (`/health`, `/tts/speak`, `/tts/stop`, `/settings/tts`) |
| Supertonic cache | `~/.cache/supertonic2/`                                                     |
| Log              | `/tmp/kokoro-tts.log` (plus `/tmp/tts_errors.log`)                          |
| Locks            | `/tmp/tts_kokoro.lock`, `/tmp/kokoro-tts.lock`                              |

## Shared Shell Library

`scripts/lib/tts-common.sh` provides common functions for the local-Kokoro scripts. Today only `tts_kokoro_audition.sh` sources it, using the lock and kill helpers; `detect_language` and `play_tts_signal` have no caller:

- `tts_log` - Plain text logging to `$LOG` (default: `/tmp/kokoro-tts.log`)
- `acquire_tts_lock` / `release_tts_lock` - Lock with heartbeat
- `detect_language` - CJK ratio heuristic (`EN_VOICE` / `ZH_VOICE`)
- `kill_existing_tts` - Stop active playback
- `play_tts_signal` - Signal sound (Tink.aiff)

## Hooks

`hooks/hooks.json` registers no hooks. `hooks/notification-tts-hook.sh` (speaks Claude Code idle and permission prompts through the companion) is kept on disk, unregistered; the Stop-hook speech path was removed at the operator's request on 2026-09-04 and its script, `telegram-notify-stop.ts`, was deleted on 2026-09-26.

## References

- [Lock debugging](./skills/diagnostic-issue-resolver/references/lock-debugging.md)
- [Config reference](./skills/settings-and-tuning/references/config-reference.md)
- [Voice catalog](./skills/voice-quality-audition/references/voice-catalog.md)

## Skills

- [clean-component-removal](./skills/clean-component-removal/SKILL.md)
- [component-version-upgrade](./skills/component-version-upgrade/SKILL.md)
- [diagnostic-issue-resolver](./skills/diagnostic-issue-resolver/SKILL.md)
- [full-stack-bootstrap](./skills/full-stack-bootstrap/SKILL.md)
- [health](./skills/health/SKILL.md)
- [settings-and-tuning](./skills/settings-and-tuning/SKILL.md)
- [setup](./skills/setup/SKILL.md)
- [voice-quality-audition](./skills/voice-quality-audition/SKILL.md)
