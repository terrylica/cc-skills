---
name: full-stack-bootstrap
description: Detailed one-time bootstrap of hotkey text-to-speech - prerequisites, Kokoro engine (MLX-Audio), ~/.local/bin links, hotkey binding, end-to-end test. TRIGGERS - setup tts, install kokoro, bootstrap tts, bind tts hotkey
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
disable-model-invocation: false
---

# Full Stack Bootstrap

One-time bootstrap of the whole text-to-speech stack this plugin owns: the Kokoro TTS engine (MLX-Audio on Apple Silicon), the `~/.local/bin` links that hotkeys call, the hotkey binding itself, and an end-to-end test. `setup` is the short version of the same steps.

The Telegram bot, BotFather token and bot secrets that used to be part of this bootstrap are gone: the bot was retired on 2026-09-24 and its setup was removed from this plugin on 2026-09-26.

> **Platform**: macOS (Apple Silicon)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

- First-time setup of the tts-tg-sync plugin
- Reinstalling after a clean OS install or hardware migration
- Setting up a new machine with hotkey text-to-speech
- Recovering from a broken installation (run `kokoro-install.sh --uninstall` first)

---

## Requirements

| Component            | Required | Installation                                                      |
| -------------------- | -------- | ----------------------------------------------------------------- |
| uv                   | Yes      | `brew install uv`                                                 |
| Python 3.14          | Yes      | `uv python install 3.14`                                          |
| jq, curl             | Yes      | `brew install jq` (curl ships with macOS)                         |
| Homebrew             | Yes      | Already installed on macOS dev machines                           |
| Apple Silicon (M1+)  | Yes      | Required for MLX Metal acceleration                               |
| claude-tts-companion | Primary  | The resident Kokoro engine the hotkey prefers; see its own plugin |
| A hotkey tool        | Yes      | Karabiner-Elements or BetterTouchTool                             |

---

## Workflow Phases

### Phase 0: Preflight Check

Verify all prerequisites are installed and accessible:

```bash
command -v uv     # Python package manager
uv python list | grep 3.14  # Python 3.14 available
command -v jq     # JSON payloads for the companion API
[[ "$(uname -m)" == "arm64" ]] && echo "Apple Silicon"
```

Install uv and jq via Homebrew (`brew install <tool>`). Python 3.14 is installed via `uv python install 3.14`.

### Phase 1: Kokoro TTS Engine Install

Run the bundled installer script:

```bash
bash "$(cc-plugin-root tts-tg-sync)/scripts/kokoro-install.sh" --install
```

<!-- SSoT-OK: kokoro-install.sh is the SSoT for versions and deps -->

This performs:

1. Requires Apple Silicon (fails fast on Intel/Linux)
2. Creates venv at `~/.local/share/kokoro/.venv` with Python 3.14 via uv
3. Installs PyPI deps (mlx-audio, soundfile, numpy)
4. Copies `kokoro_common.py` and `tts_generate.py` from plugin bundle to `~/.local/share/kokoro/`
5. Downloads Kokoro-82M-bf16 MLX model from HuggingFace (`mlx-community/Kokoro-82M-bf16`)
6. Writes `version.json` with mlx_audio version, backend, and model ID

### Phase 2: Shell Links

Create links in `~/.local/bin/` pointing to the plugin's shell scripts. Hotkeys call these links, so a plugin update never has to be re-bound:

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"
mkdir -p ~/.local/bin
for script in tts_kokoro.sh tts_kokoro_audition.sh tts_read_clipboard.sh tts_read_clipboard_wrapper.sh tts_speed_up.sh tts_speed_down.sh tts_speed_reset.sh tts_stop.sh; do
    ln -sf "$PLUGIN_DIR/scripts/$script" ~/.local/bin/"$script"
done
```

### Phase 3: Hotkey Binding

Use AskUserQuestion to learn which hotkey tool the user has, then bind:

| Action               | Script (via `~/.local/bin`)                       |
| -------------------- | ------------------------------------------------- |
| Read clipboard aloud | `tts_read_clipboard_wrapper.sh`                   |
| Faster / slower      | `tts_speed_up.sh` / `tts_speed_down.sh` (±30 WPM) |
| Reset speed          | `tts_speed_reset.sh` (220 WPM)                    |
| Stop playback        | `tts_stop.sh`                                     |

- **Karabiner-Elements**: a complex-modification rule whose `to` is a `shell_command` running the script. Karabiner's shell has a minimal environment, which is why every script restores its own PATH.
- **BetterTouchTool**: an "Execute Shell Script" action per row. The speed scripts read and write the BetterTouchTool variable `TTS_SPEECH_RATE`; without BetterTouchTool they fall back to 220 WPM.

The wrapper waits for the copy to land before reading the clipboard, so a binding that fires ⌘C and then the script with no delay is correct.

### Phase 4: Verification

1. Generate a test WAV with the local engine and play it:

```bash
~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
    --text "Hello, bootstrap complete." --voice af_heart --lang en-us --speed 1.0 --output /tmp/test-bootstrap.wav
afplay /tmp/test-bootstrap.wav
rm -f /tmp/test-bootstrap.wav
```

1. Run the hotkey path end to end, then press the bound key and confirm the same:

```bash
echo "Hotkey path works." | pbcopy && ~/.local/bin/tts_read_clipboard_wrapper.sh; echo "exit=$?"
tail -3 /tmp/kokoro-tts.log   # shows engine=kokoro or the Supertonic fallback
```

---

## TodoWrite Task Templates

### Template: Full Stack Bootstrap

```
1. [Preflight] Verify uv, Python 3.14, jq, Apple Silicon
2. [Kokoro] Run kokoro-install.sh --install
3. [Kokoro] Verify MLX-Audio acceleration
4. [Links] Create ~/.local/bin/ links for all TTS shell scripts
5. [Hotkey] Bind read / speed / stop keys in Karabiner-Elements or BetterTouchTool
6. [Verify] Generate test WAV with Kokoro and play with afplay
7. [Verify] Run tts_read_clipboard_wrapper.sh and check /tmp/kokoro-tts.log
```

---

## Post-Change Checklist

After modifying this skill:

1. [ ] Verify `kokoro-install.sh --health` passes all 6 checks
2. [ ] Test links resolve correctly (`ls -la ~/.local/bin/tts_*.sh`)
3. [ ] Run a full TTS round-trip: clipboard text to audio playback via the hotkey
4. [ ] Update `references/evolution-log.md` with change description

## Troubleshooting

| Issue                               | Cause                                                      | Solution                                                          |
| ----------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------- |
| uv not found                        | Not installed                                              | `brew install uv`                                                 |
| Python 3.14 not available           | Not installed via uv                                       | `uv python install 3.14`                                          |
| Not Apple Silicon                   | Intel Mac or Linux                                         | Requires M1 or newer Mac (MLX Metal)                              |
| Model download fails                | Network issue or HuggingFace outage                        | Check internet connectivity, retry                                |
| kokoro-install.sh permission denied | Script not executable                                      | `chmod +x scripts/kokoro-install.sh`                              |
| Venv already exists                 | Previous partial install                                   | Run `kokoro-install.sh --uninstall` then `--install`              |
| tts_generate.py not found           | Bundle copy failed                                         | Check `scripts/tts_generate.py` exists in plugin                  |
| Hotkey does nothing                 | Bound to a versioned plugin path, or tool lacks permission | Bind the `~/.local/bin` link; grant the hotkey tool Accessibility |

---

## Reference Documentation

- [Kokoro Bootstrap](./references/kokoro-bootstrap.md) - Detailed venv setup, Python 3.14 via uv, MLX-Audio, model download
- [Upstream Fork](./references/upstream-fork.md) - MLX-Audio Kokoro upstream and bundled script rationale
- [Evolution Log](./references/evolution-log.md) - Change history for this skill

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
