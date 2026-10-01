---
name: diagnostic-issue-resolver
description: Diagnose and resolve hotkey text-to-speech issues - silent hotkey, stale locks, wrong engine, slow or doubled audio, Kokoro errors. TRIGGERS - tts not working, hotkey silent, kokoro error, tts stuck
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
---

# Diagnostic Issue Resolver

Diagnose and fix common text-to-speech issues through systematic symptom collection, automated diagnostics, and targeted fixes.

This plugin has no Telegram bot any more (retired 2026-09-24), so "bot not responding" is not a symptom this skill handles.

> **Platform**: macOS (Apple Silicon)

---

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

- The read-aloud hotkey does nothing, or reads the previous selection
- Audio sounds wrong, too slow or too fast, or plays twice
- Kokoro engine errors or timeouts
- A lock file appears stuck
- MLX Metal acceleration is not working

---

## Requirements

- Access to `/tmp/kokoro-tts.log` and `/tmp/tts_errors.log` (script logs)
- Access to `~/.local/share/kokoro/` (local Kokoro engine)
- `curl` to reach `claude-tts-companion` on `http://[::1]:8780`

---

## Known Issue Table

| Issue                     | Likely Cause                                                            | Diagnostic                                                                | Fix                                                                         |
| ------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Hotkey silent             | Binding points at a versioned path, or the hotkey tool lacks permission | `tail -20 /tmp/kokoro-tts.log` right after pressing                       | Bind `~/.local/bin/tts_read_clipboard_wrapper.sh`; grant Accessibility      |
| Reads previous selection  | Clipboard read before the copy landed                                   | Log shows the old text                                                    | Use the wrapper (it waits on NSPasteboard changeCount), not `tts_kokoro.sh` |
| No audio output           | Stale TTS lock                                                          | `stat /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock`                          | `tts_stop.sh`                                                               |
| Slow first word           | Companion down, Supertonic fallback                                     | `curl -s --max-time 2 "http://[::1]:8780/health"`                         | Start `claude-tts-companion`; or accept the fallback                        |
| Speed keys do nothing     | Companion unreachable when the rate was set                             | `grep speed: /tmp/kokoro-tts.log \| tail -3`                              | Press again once the companion is up                                        |
| Kokoro timeout (audition) | First-run model load                                                    | Check `~/.cache/huggingface/`                                             | Wait for download, or re-run `kokoro-install.sh --install`                  |
| Lock stuck forever        | Heartbeat process died                                                  | `stat /tmp/kokoro-tts.lock` + `pgrep -x afplay`                           | If lock stale >30s AND no audio process, `tts_stop.sh`                      |
| Slow MLX acceleration     | Wrong Python or deps                                                    | `python -c "from mlx_audio.tts.utils import load_model; print('MLX OK')"` | Reinstall via `kokoro-install.sh --upgrade`                                 |
| Double audio playback     | Two engines or two presses racing                                       | Check for multiple afplay processes                                       | `tts_stop.sh`, then press once                                              |

---

## Workflow Phases

### Phase 1: Symptom Collection

Use AskUserQuestion to understand what the user is experiencing. Key questions:

- What happened? (silence, wrong text, wrong speed, doubled audio, error notification)
- When did it start? (after an upgrade, after moving the checkout, suddenly, always)
- What were you doing? (hotkey read-aloud, speed keys, voice audition, manual script run)

### Phase 2: Automated Diagnostics

Based on symptoms, run the relevant subset of these checks:

```bash
# Lock state (both locks)
for f in /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock; do
  ls -la "$f" 2>/dev/null && stat -f "%Sm" "$f" || echo "No $f"
done

# Audio processes
pgrep -la afplay; pgrep -la say

# Which engine the last presses used, and any errors
tail -30 /tmp/kokoro-tts.log 2>/dev/null
tail -20 /tmp/tts_errors.log 2>/dev/null

# Primary engine
curl -s --max-time 2 "http://[::1]:8780/health" || echo "companion down"

# Local Kokoro health
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('MLX-Audio OK')"

# Links the hotkeys call
ls -la ~/.local/bin/tts_*.sh
```

### Phase 3: Root Cause Analysis

Map diagnostic output to the Known Issue Table above. Common patterns:

- Lock file exists + mtime > 30s ago + no afplay = **stale lock**
- Log shows `engine=supertonic` on every press = **companion down**
- Log shows nothing after a press = **hotkey never ran the script** (binding or permission)
- `from mlx_audio.tts.utils import load_model` fails = **MLX-Audio broken**
- Multiple afplay PIDs = **race condition**

### Phase 4: Fix Application

Apply the targeted fix from the Known Issue Table. Always use the least disruptive fix first; `tts_stop.sh` is the safe reset for anything playback-related.

### Phase 5: Verification

After applying the fix, verify the issue is resolved:

```bash
# Same path a hotkey takes
echo "Diagnostic test complete" | pbcopy && ~/.local/bin/tts_read_clipboard_wrapper.sh; echo "exit=$?"

# Local engine
bash "$(cc-plugin-root tts-tg-sync)/scripts/kokoro-install.sh" --health
```

---

## TodoWrite Task Templates

```
1. [Symptoms] Collect symptoms via AskUserQuestion
2. [Triage] Map symptoms to likely causes
3. [Lock] Check both TTS locks (mtime, PID, stale detection)
4. [Engine] Check the companion and the Supertonic fallback via /tmp/kokoro-tts.log
5. [Kokoro] Verify Kokoro venv and MLX-Audio availability
6. [Fix] Apply targeted fix for identified root cause
7. [Verify] Run the wrapper and the health check to confirm resolution
```

---

## Post-Change Checklist

- [ ] Root cause identified and documented
- [ ] Fix applied successfully
- [ ] Health check passes
- [ ] Test audio plays correctly
- [ ] No stale locks or orphan processes remain

## Troubleshooting

This skill IS the troubleshooting skill. If the standard diagnostics do not identify the issue:

1. Re-run the Supertonic path with debug logging: `DEBUG=1 TTS_ENGINE=supertonic ~/.local/bin/tts_read_clipboard_wrapper.sh`, then read `/tmp/tts_debug.log` (the Kokoro path logs only to `/tmp/kokoro-tts.log`)
2. Check system audio: `afplay /System/Library/Sounds/Tink.aiff` (if this fails, it is a macOS audio issue, not TTS)
3. Force each engine in turn: `TTS_ENGINE=kokoro …` and `TTS_ENGINE=supertonic …`
4. Run a manual Kokoro generation with `tts_generate.py` to isolate the local engine
5. If all else fails, do a full teardown and reinstall using `clean-component-removal` then `full-stack-bootstrap`

---

## Reference Documentation

- [Common Issues](./references/common-issues.md) -- Expanded diagnostic procedures for each known issue
- [Lock Debugging](./references/lock-debugging.md) -- Deep dive into the lock mechanism
- [Evolution Log](./references/evolution-log.md) -- Change history for this skill

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
