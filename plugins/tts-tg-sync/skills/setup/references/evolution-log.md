# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: TTS-only setup

**Trigger**: The Telegram sync bot this plugin managed was retired on 2026-09-24, but setup still walked the user through BotFather, wrote a bot token into a secrets file and verified it with `getMe`. Its link list also missed `tts_stop.sh`, which the stop hotkey calls.

**Fix**: Removed the BotFather, secrets and bot-connectivity steps. Setup now installs the Kokoro engine, links every hotkey script (including `tts_stop.sh`), asks which hotkey tool binds them, and verifies by running `tts_read_clipboard_wrapper.sh` end to end.

**Files**: `SKILL.md`

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
