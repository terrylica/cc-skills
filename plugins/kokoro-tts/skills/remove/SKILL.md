---
name: remove
description: "Remove Kokoro TTS engine. TRIGGERS - remove kokoro, uninstall tts, delete kokoro, clean tts."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Remove Kokoro TTS

Clean uninstall of the Kokoro TTS engine. Preserves model cache by default.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## What Gets Removed

- Python venv at `~/.local/share/kokoro/.venv`
- Scripts: `tts_generate.py`, `kokoro_common.py`
- Metadata: `version.json`
- Directory `~/.local/share/kokoro/` (if empty after cleanup)

## What Gets Preserved

- Model cache at `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/`
- Launchd plist (if server was configured)

## Workflow

### Step 1: Confirm with user

Use AskUserQuestion to confirm removal. Mention what will be removed and what will be preserved.

### Step 2: Stop server (if running)

```bash
# Stop launchd service if exists
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist 2>/dev/null || true
```

### Step 3: Uninstall

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --uninstall
```

### Step 4: (Optional) Remove model cache

Only if user explicitly requests full cleanup:

```bash
rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16
```

### Step 5: (Optional) Remove launchd plist

```bash
rm -f ~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist
```

## Post-Removal

To reinstall later: `/kokoro-tts:install`


## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
