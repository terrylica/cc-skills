---
name: full-stack-bootstrap
description: One-time bootstrap for Kokoro TTS engine, Telegram bot, and BotFather setup. TRIGGERS - setup tts, install kokoro, botfather, bootstrap tts-telegram-sync, configure telegram bot, full stack setup.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Full Stack Bootstrap

One-time bootstrap of the entire TTS + Telegram bot stack: Kokoro TTS engine (Apple Silicon MPS), Telegram bot via BotFather, secrets management, environment configuration, and shell symlinks.

> **Platform**: macOS (Apple Silicon)

## When to Use This Skill

- First-time setup of the tts-telegram-sync plugin
- Reinstalling after a clean OS install or hardware migration
- Setting up a new machine with the full TTS + Telegram stack
- Recovering from a broken installation (run `kokoro-install.sh --uninstall` first)

---

## Requirements

| Component           | Required | Installation                            |
| ------------------- | -------- | --------------------------------------- |
| Bun                 | Yes      | `brew install oven-sh/bun/bun`          |
| mise                | Yes      | `brew install mise`                     |
| uv                  | Yes      | `brew install uv`                       |
| Python 3.13         | Yes      | `uv python install 3.13`                |
| Homebrew            | Yes      | Already installed on macOS dev machines |
| Apple Silicon (M1+) | Yes      | Required for MPS acceleration           |

---

## Workflow Phases

### Phase 0: Preflight Check

Verify all prerequisites are installed and accessible:

```bash
command -v bun    # Bun runtime for TypeScript bot
command -v mise   # Environment manager
command -v uv     # Python package manager
uv python list | grep 3.13  # Python 3.13 available
```

If any tool is missing, install via Homebrew (`brew install <tool>`). Python 3.13 is installed via `uv python install 3.13`.

### Phase 1: Kokoro TTS Engine Install

Run the bundled installer script:

```bash
bash scripts/kokoro-install.sh --install
```

<!-- SSoT-OK: kokoro-install.sh is the SSoT for versions and deps -->

This performs:

1. Creates venv at `~/.local/share/kokoro/.venv` with Python 3.13 via uv
2. Installs PyPI deps (kokoro, misaki, torch, soundfile, numpy, transformers, huggingface_hub, loguru) -- versions pinned in `scripts/kokoro-install.sh`
3. Copies `tts_generate.py` from plugin bundle to `~/.local/share/kokoro/`
4. Downloads Kokoro-82M model from HuggingFace (`hexgrad/Kokoro-82M`)
5. Verifies Apple Silicon MPS is available via `torch.backends.mps.is_available()`
6. Writes `version.json` with kokoro, torch, and Python versions

### Phase 2: BotFather Token Setup

Guide the user through Telegram BotFather to create a bot token:

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`, follow prompts (name + username)
3. Copy the HTTP API token
4. Verify token: `curl -s "https://api.telegram.org/bot<TOKEN>/getMe" | jq .ok`
5. Get chat_id by sending a message to the bot, then: `curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'`

If a token already exists at `~/.claude/.secrets/ccterrybot-telegram`, verify it works and skip this phase.

### Phase 3: Secrets Storage

Store the bot token securely:

```bash
mkdir -p ~/.claude/.secrets
chmod 700 ~/.claude/.secrets
echo "BOT_TOKEN=<token>" > ~/.claude/.secrets/ccterrybot-telegram
echo "CHAT_ID=<chat_id>" >> ~/.claude/.secrets/ccterrybot-telegram
chmod 600 ~/.claude/.secrets/ccterrybot-telegram
```

Create `.mise.local.toml` (gitignored) in the bot directory to load secrets:

```toml
# ~/.claude/automation/claude-telegram-sync/.mise.local.toml
[env]
_.file = "{{env.HOME}}/.claude/.secrets/ccterrybot-telegram"
```

### Phase 4: Environment Configuration

Add Kokoro paths to `mise.toml`:

```toml
# In ~/.claude/automation/claude-telegram-sync/mise.toml [env] section
KOKORO_VENV = "{{env.HOME}}/.local/share/kokoro/.venv"
KOKORO_SCRIPT = "{{env.HOME}}/.local/share/kokoro/tts_generate.py"
```

### Phase 5: Shell Symlinks

Create symlinks in `~/.local/bin/` pointing to plugin shell scripts:

```bash
mkdir -p ~/.local/bin
ln -sf <plugin>/scripts/tts_kokoro.sh ~/.local/bin/tts_kokoro.sh
ln -sf <plugin>/scripts/tts_read_clipboard.sh ~/.local/bin/tts_read_clipboard.sh
ln -sf <plugin>/scripts/tts_read_clipboard_wrapper.sh ~/.local/bin/tts_read_clipboard_wrapper.sh
ln -sf <plugin>/scripts/tts_speed_up.sh ~/.local/bin/tts_speed_up.sh
ln -sf <plugin>/scripts/tts_speed_down.sh ~/.local/bin/tts_speed_down.sh
ln -sf <plugin>/scripts/tts_speed_reset.sh ~/.local/bin/tts_speed_reset.sh
```

### Phase 6: Verification

1. Generate a test WAV and play it:

```bash
~/.local/share/kokoro/.venv/bin/python ~/.local/share/kokoro/tts_generate.py \
    --text "Hello, bootstrap complete." --voice af_heart --lang en-us --speed 1.0 --output /tmp/test-bootstrap.wav
afplay /tmp/test-bootstrap.wav
rm -f /tmp/test-bootstrap.wav
```

1. Verify bot responds to /status via Telegram API:

```bash
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | jq .ok
```

---

## TodoWrite Task Templates

### Template: Full Stack Bootstrap

```
1. [Preflight] Verify Bun installed
2. [Preflight] Verify mise installed
3. [Preflight] Verify uv installed
4. [Preflight] Verify Python 3.13 available via uv
5. [Kokoro] Run kokoro-install.sh --install
6. [Kokoro] Verify MPS acceleration
7. [BotFather] Guide BotFather token creation (or verify existing)
8. [Secrets] Store token in ~/.claude/.secrets/ccterrybot-telegram
9. [Secrets] Create .mise.local.toml with _.file reference to secrets
10. [Environment] Add KOKORO_VENV and KOKORO_SCRIPT to mise.toml
11. [Symlinks] Create ~/.local/bin/ symlinks for all TTS shell scripts
12. [Verify] Generate test WAV with Kokoro and play with afplay
13. [Verify] Check bot responds to /status via Telegram API
```

---

## Post-Change Checklist

After modifying this skill:

1. [ ] Verify `kokoro-install.sh --health` passes all 8 checks
2. [ ] Confirm `.mise.local.toml` is gitignored
3. [ ] Test symlinks resolve correctly (`ls -la ~/.local/bin/tts_*.sh`)
4. [ ] Verify bot token works via `getMe` API call
5. [ ] Run a full TTS round-trip: clipboard text to audio playback
6. [ ] Update `references/evolution-log.md` with change description

---

## Troubleshooting

| Issue                               | Cause                               | Solution                                                    |
| ----------------------------------- | ----------------------------------- | ----------------------------------------------------------- |
| uv not found                        | Not installed                       | `brew install uv`                                           |
| Python 3.13 not available           | Not installed via uv                | `uv python install 3.13`                                    |
| MPS not available                   | Not Apple Silicon                   | Requires M1 or newer Mac                                    |
| Model download fails                | Network issue or HuggingFace outage | Check internet connectivity, retry                          |
| BotFather token invalid             | Typo or revoked token               | Verify via `curl https://api.telegram.org/bot<TOKEN>/getMe` |
| kokoro-install.sh permission denied | Script not executable               | `chmod +x scripts/kokoro-install.sh`                        |
| Venv already exists                 | Previous partial install            | Run `kokoro-install.sh --uninstall` then `--install`        |
| tts_generate.py not found           | Bundle copy failed                  | Check `scripts/tts_generate.py` exists in plugin            |

---

## Reference Documentation

- [Kokoro Bootstrap](./references/kokoro-bootstrap.md) - Detailed venv setup, Python 3.13 via uv, torch + MPS, model download
- [BotFather Guide](./references/botfather-guide.md) - Step-by-step Telegram bot creation and token management
- [Upstream Fork](./references/upstream-fork.md) - hexgrad/kokoro fork provenance and tts_generate.py bundling rationale
- [Evolution Log](./references/evolution-log.md) - Change history for this skill
