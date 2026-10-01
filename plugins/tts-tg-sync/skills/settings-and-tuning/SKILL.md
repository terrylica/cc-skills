---
name: settings-and-tuning
description: Configure hotkey text-to-speech - speech rate, engine choice, Kokoro voices, signal sound, Supertonic knobs. TRIGGERS - configure tts, change voice, tts speed, tts engine
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# Settings and Tuning

Configure the adjustable parameters of the hotkey text-to-speech scripts. There is no central config file: each knob lives where the script that reads it can see it — a BetterTouchTool variable, the companion's persisted settings, or an environment variable in the hotkey's command. See [config-reference.md](./references/config-reference.md).

The Telegram bot's settings (notification rate limits, prompt executor, session picker, bot queue and timeouts, `moon.yml` `env:` and the bot's `.env`) are gone: the bot was retired on 2026-09-24 and its configuration docs were removed on 2026-09-26.

> **Platform**: macOS (Apple Silicon)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

- Changing speech speed
- Forcing an engine (Kokoro via the companion, or Supertonic)
- Changing which voices the audition plays
- Tuning the Supertonic fallback (maximum length, debug logging)

---

## Workflow Phases

### Phase 0: Read Current Configuration

```bash
# Speech rate (words per minute) as the hotkeys see it
BTTCLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
[[ -x "$BTTCLI" ]] && "$BTTCLI" get_string_variable variable_name=TTS_SPEECH_RATE || echo "no BetterTouchTool — default 220"

# Last rate change applied to the companion
grep 'speed:' /tmp/kokoro-tts.log | tail -3

# Any environment overrides baked into the hotkey binding (Karabiner rule)
grep -o '"shell_command": *"[^"]*tts_[^"]*"' ~/.config/karabiner/karabiner.json 2>/dev/null
```

### Phase 1: Identify What to Change

Present the config groups to the user via AskUserQuestion:

| Group           | Settings                                               | Where it lives                                     |
| --------------- | ------------------------------------------------------ | -------------------------------------------------- |
| Speech rate     | `TTS_SPEECH_RATE` (WPM) → companion `speed` multiplier | `tts_speed_*.sh` keys, or `tts_speed_set.sh <wpm>` |
| Engine          | `TTS_ENGINE` = `auto` / `kokoro` / `supertonic`        | Environment of the hotkey command                  |
| Kokoro voice    | Companion voice settings                               | `claude-tts-companion` (its own plugin)            |
| Audition voices | The `VOICES` list                                      | `scripts/tts_kokoro_audition.sh`                   |
| Local Kokoro    | `KOKORO_VENV`, `KOKORO_SCRIPT`                         | Environment of `tts_kokoro_audition.sh`            |
| Supertonic      | `MAX_CONTENT_LENGTH`, `DEBUG`                          | Environment of the hotkey command                  |

### Phase 2: Apply

- **Speech rate**: run `"$(cc-plugin-root tts-tg-sync)/scripts/tts_speed_set.sh" <wpm>` (90-500). Use the plugin copy: `tts_speed_set.sh` has no `~/.local/bin` link, because the linked up/down/reset scripts resolve their own real directory and call it from there (`cc-plugin-root` is installed by `/itp:setup`). It writes the BetterTouchTool variable for the Supertonic path and posts `{"speed": wpm/220}` (clamped to 0.5-3.0) to the companion for the Kokoro path. `tts_speed_reset.sh` returns to 220 WPM, which is Kokoro speed 1.0.
- **Environment knobs**: prefix the hotkey's command, e.g. `TTS_ENGINE=supertonic ~/.local/bin/tts_read_clipboard_wrapper.sh`, in the Karabiner-Elements `shell_command` or the BetterTouchTool action. Edit the user's hotkey configuration only with their confirmation.
- **Kokoro voice for hotkeys**: the companion owns it; change it through the `claude-tts-companion` plugin.

### Phase 3: Verify

Press the hotkey (or run the wrapper by hand) and confirm the change in `/tmp/kokoro-tts.log`, which records the engine and rate for every press.

---

## TodoWrite Task Templates

### Template: Settings Adjustment

```
1. [Read] Read the current rate, recent speed log lines and the hotkey command
2. [Identify] Present config groups to user via AskUserQuestion
3. [Apply] Run the plugin's scripts/tts_speed_set.sh (it has no ~/.local/bin link), or add the env prefix to the hotkey command with confirmation
4. [Validate] Verify values are in valid range (see config-reference.md)
5. [Verify] Press the hotkey and confirm engine/rate in /tmp/kokoro-tts.log
```

---

## Post-Change Checklist

After modifying this skill:

1. [ ] Every knob listed here is still read by a script in `scripts/` (grep for it)
2. [ ] Update config-reference.md if a knob was added or removed
3. [ ] Update `references/evolution-log.md` with change description

## Troubleshooting

| Issue                      | Cause                                           | Solution                                                                       |
| -------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------ |
| Speed change not audible   | Companion was down when the key fired           | Press again once the companion is up (see the speed log)                       |
| Speed seems capped         | WPM is clamped to 90-500                        | Expected; 500 WPM is Kokoro speed ~2.27, and below 110 WPM Kokoro stays at 0.5 |
| Voice change ignored       | Voice set in env, but hotkeys use the companion | Change the voice in `claude-tts-companion`                                     |
| Engine override ignored    | Env prefix on a different binding               | Put it on the command the pressed key actually runs                            |
| Voice not found (audition) | Invalid voice name                              | Check voice catalog (Kokoro voices are case-sensitive)                         |

---

## Reference Documentation

- [Config Reference](./references/config-reference.md) - Every knob, its default, valid range and the script that reads it
- [Evolution Log](./references/evolution-log.md) - Change history for this skill

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
