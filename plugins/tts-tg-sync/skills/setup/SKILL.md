---
name: setup
description: One-time bootstrap for hotkey text-to-speech - Kokoro engine install, ~/.local/bin links for the tts_* scripts, verification. TRIGGERS - tts setup, kokoro install, link tts scripts
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TodoWrite, TodoRead, AskUserQuestion
argument-hint: "[--check|--install]"
disable-model-invocation: false
---

> **Prerequisite — `cc-plugin-root`.** This skill resolves its scripts with `cc-plugin-root <plugin>` (the `CLAUDE_PLUGIN_ROOT` placeholder is not a shell variable and expands to empty). If the command is missing, run `/itp:setup` (its first step installs it), or link it directly:
>
> ```bash
> mkdir -p ~/.local/bin && ln -sfn \
>   ~/.claude/plugins/marketplaces/cc-skills/scripts/cc-plugin-root ~/.local/bin/cc-plugin-root
> ```

# TTS Setup

Bootstrap hotkey text-to-speech: the local Kokoro engine, the `~/.local/bin` links the hotkeys call, and a verification pass. For the long-form version with every phase explained, use `full-stack-bootstrap`.

This plugin no longer sets up a Telegram bot. The bot it used to manage was retired on 2026-09-24; do not create a BotFather token or a secrets file for it.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Prerequisites

| Component   | Required | Check                                   |
| ----------- | -------- | --------------------------------------- |
| uv          | Yes      | `uv --version`                          |
| Python 3.14 | Yes      | `uv run --python 3.14 python --version` |
| Homebrew    | Yes      | `brew --version`                        |
| jq, curl    | Yes      | `jq --version && curl --version`        |

## Workflow

### Step 1: Preflight

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF'
echo "=== TTS Preflight ==="
for cmd in uv brew jq curl; do
    if command -v "$cmd" &>/dev/null; then
        echo "  [OK] $cmd: $($cmd --version 2>&1 | head -1)"
    else
        echo "  [FAIL] $cmd not found"
    fi
done
[[ "$(uname -m)" == "arm64" ]] && echo "  [OK] Apple Silicon" || echo "  [FAIL] MLX needs Apple Silicon"
PREFLIGHT_EOF
```

### Step 2: Kokoro Install

Run the Kokoro TTS engine installer:

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --install
```

This creates a Python 3.14 venv at `~/.local/share/kokoro/`, installs MLX-Audio deps, downloads the Kokoro-82M-bf16 MLX model, and verifies MLX Metal acceleration. It is what `tts_kokoro_audition.sh` uses; the hotkey path itself speaks through `claude-tts-companion`.

### Step 3: Links

Create links in `~/.local/bin/` for all TTS shell scripts:

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"
mkdir -p ~/.local/bin
for script in tts_kokoro.sh tts_kokoro_audition.sh tts_read_clipboard.sh tts_read_clipboard_wrapper.sh tts_speed_up.sh tts_speed_down.sh tts_speed_reset.sh tts_stop.sh; do
    ln -sf "$PLUGIN_DIR/scripts/$script" ~/.local/bin/"$script"
done
```

### Step 4: Hotkey

Use AskUserQuestion to confirm which hotkey tool the user binds with, then point it at the link, not at a versioned plugin path:

- **Karabiner-Elements**: a `shell_command` rule running `~/.local/bin/tts_read_clipboard_wrapper.sh`
- **BetterTouchTool**: an "Execute Shell Script" action running the same path; speed and stop keys run `tts_speed_up.sh`, `tts_speed_down.sh`, `tts_speed_reset.sh` and `tts_stop.sh`

### Step 5: Verify

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --health

# Primary engine reachable? (claude-tts-companion)
curl -s --max-time 2 "http://[::1]:8780/health" >/dev/null && echo "companion OK" || echo "companion down — hotkeys will use the Supertonic fallback"

# End to end, the same path a hotkey takes
echo "Setup complete." | pbcopy && ~/.local/bin/tts_read_clipboard_wrapper.sh; echo "exit=$?"
```

## Troubleshooting

| Issue               | Cause                  | Solution                                                 |
| ------------------- | ---------------------- | -------------------------------------------------------- |
| uv not found        | Not installed          | `brew install uv`                                        |
| Not Apple Silicon   | Intel Mac or Linux     | Requires M1+ Mac (MLX Metal)                             |
| Model download slow | Large first download   | ~400MB, wait for completion                              |
| Hotkey silent       | Hotkey PATH is minimal | Bind the `~/.local/bin` link; read `/tmp/kokoro-tts.log` |
| Links broken        | Plugin path changed    | Re-run the link step                                     |

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
