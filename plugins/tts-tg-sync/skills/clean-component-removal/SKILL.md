---
name: clean-component-removal
description: Remove hotkey text-to-speech components cleanly - Kokoro venv, ~/.local/bin links, temp files and locks, in a safe order with confirmation. TRIGGERS - uninstall tts, remove tts scripts, uninstall kokoro
allowed-tools: Read, Bash, Glob, AskUserQuestion
disable-model-invocation: false
---

# Clean Component Removal

Orderly teardown of the text-to-speech components this plugin installs, sequenced to avoid orphaned playback and stale locks.

There is no Telegram bot to stop any more: the bot this plugin used to manage was retired on 2026-09-24, and its removal steps were dropped from this skill on 2026-09-26. `claude-tts-companion` and the `kokoro-tts` server are separate plugins with their own removal paths; this skill does not touch them.

> **Platform**: macOS (Apple Silicon)

---

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

- User wants to uninstall the local Kokoro TTS engine
- User wants to remove the hotkey scripts from `~/.local/bin`
- User wants to clean up all TTS-related temp files
- User wants to do a full teardown before reinstallation
- User wants to remove specific components selectively

---

## Requirements

- No special tools needed (removal uses only `rm`, `tts_stop.sh`, and the install script)
- User confirmation before destructive operations

---

## Removal Order

The removal sequence matters. Components must be torn down in this order to avoid orphaned playback or lock contention.

| Step | Component       | Command                                                                 | Reversible?     |
| ---- | --------------- | ----------------------------------------------------------------------- | --------------- |
| 1    | Active playback | `~/.local/bin/tts_stop.sh`                                              | N/A             |
| 2    | Kokoro venv     | `kokoro-install.sh --uninstall`                                         | Yes (reinstall) |
| 3    | Shell links     | remove each `~/.local/bin/tts_*.sh` link that points into this plugin   | Yes (re-link)   |
| 4    | Temp files      | `rm -f /tmp/kokoro-tts-*.wav /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock` | N/A             |

Hotkey bindings (Karabiner-Elements rules, BetterTouchTool actions) are the user's configuration. Tell the user which bindings will now point at a missing file; do not edit their configuration for them.

---

## What Is NOT Removed (Unless Explicitly Asked)

These are preserved by default to allow easy reinstallation:

| Resource               | Path                                                              | Why Preserved               |
| ---------------------- | ----------------------------------------------------------------- | --------------------------- |
| Kokoro model cache     | `~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16` | ~400MB download, reusable   |
| Supertonic model cache | `~/.cache/supertonic2/`                                           | Reusable download           |
| Logs                   | `/tmp/kokoro-tts.log`, `/tmp/tts_errors.log`                      | Evidence if something broke |

---

## Workflow Phases

### Phase 1: Confirmation

Use AskUserQuestion to confirm which components to remove. Present options:

1. **Full teardown** -- Steps 1-4
2. **Engine only** -- Stop playback + remove the Kokoro venv (steps 1-2)
3. **Links only** -- Remove the `~/.local/bin` links (step 3); hotkeys stop working
4. **Selective** -- Let user pick individual steps

### Phase 2: Stop Playback

```bash
~/.local/bin/tts_stop.sh 2>/dev/null || pkill -x afplay || echo "Nothing playing"
```

### Phase 3: Remove Kokoro Venv

```bash
# Uses kokoro-install.sh --uninstall (removes venv, keeps model cache)
bash "$(cc-plugin-root tts-tg-sync)/scripts/kokoro-install.sh" --uninstall
```

### Phase 4: Remove Links

Preview first, and only remove links that point into this plugin:

```bash
PLUGIN_DIR="$(cc-plugin-root tts-tg-sync)"
for link in ~/.local/bin/tts_*.sh; do
  [[ -L "$link" ]] || continue
  target=$(readlink "$link")
  echo "$link -> $target"
done
# After the user confirms the list, remove exactly those links, e.g.:
# rm -f ~/.local/bin/tts_read_clipboard_wrapper.sh
```

Links whose targets are a different checkout of this plugin (for example a development clone) are still this plugin's scripts; ask before removing them.

### Phase 5: Clean Temp Files

```bash
rm -f /tmp/kokoro-tts-*.wav
rm -f /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock
```

---

## TodoWrite Task Templates

```
1. [Confirm] Ask user which components to remove via AskUserQuestion
2. [Stop] Stop playback with tts_stop.sh
3. [Venv] Run kokoro-install.sh --uninstall
4. [Links] Preview, confirm, then remove ~/.local/bin/ links
5. [Temp] Clean /tmp/ TTS files and both locks
6. [Bindings] Tell the user which hotkey bindings now point at missing files
7. [Verify] Confirm all selected components removed
```

---

## Post-Change Checklist

- [ ] Kokoro venv removed (`ls ~/.local/share/kokoro/.venv` returns "No such file")
- [ ] Selected links removed (`ls ~/.local/bin/tts_*.sh`)
- [ ] No stale lock files (`ls /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock` returns "No such file")
- [ ] No orphan audio processes (`pgrep -x afplay` returns nothing)

## Troubleshooting

| Problem                            | Likely Cause                                | Fix                                                                                  |
| ---------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------ |
| Links still exist after removal    | Glob mismatch or permission                 | `ls -la ~/.local/bin/tts_*` then `rm -f` each one                                    |
| Stale lock after removal           | Process died without cleanup                | `rm -f /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock`                                    |
| Model cache taking space           | ~400MB in HuggingFace cache                 | `rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16` (ask first) |
| Speech still works after teardown  | `claude-tts-companion` is a separate plugin | Expected; remove it through its own plugin if wanted                                 |
| Audio still playing after teardown | `afplay` process outlives the script        | `pkill -x afplay`                                                                    |

---

## Reference Documentation

- [Evolution Log](./references/evolution-log.md) -- Change history for this skill

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
