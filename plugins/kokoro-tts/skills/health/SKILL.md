---
name: health
description: "Kokoro TTS health check. TRIGGERS - kokoro health, tts health, kokoro status."
allowed-tools: Read, Bash, Glob
model: haiku
---

# Kokoro TTS Health Check

Run 6 health checks to verify the Kokoro TTS engine installation.

## Checks

| #   | Check            | Command                                                         |
| --- | ---------------- | --------------------------------------------------------------- |
| 1   | Venv exists      | `[[ -d ~/.local/share/kokoro/.venv ]]`                          |
| 2   | Python 3.13      | `~/.local/share/kokoro/.venv/bin/python --version \| grep 3.13` |
| 3   | mlx_audio import | `python -c "from mlx_audio.tts.utils import load_model"`        |
| 4   | kokoro_common.py | `[[ -f ~/.local/share/kokoro/kokoro_common.py ]]`               |
| 5   | tts_generate.py  | `[[ -f ~/.local/share/kokoro/tts_generate.py ]]`                |
| 6   | version.json     | `[[ -f ~/.local/share/kokoro/version.json ]]`                   |

## Execution

```bash
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/kokoro-tts}"
bash "$PLUGIN_DIR/scripts/kokoro-install.sh" --health
```

## Failure Recommendations

| Failure         | Recommended Skill  |
| --------------- | ------------------ |
| Venv missing    | install            |
| Import fails    | install or upgrade |
| Scripts missing | install            |
| version.json    | install            |

## Troubleshooting

| Issue             | Cause          | Solution                                         |
| ----------------- | -------------- | ------------------------------------------------ |
| All checks fail   | Not installed  | Run `/kokoro-tts:install` first                  |
| Only import fails | Venv corrupted | `kokoro-install.sh --uninstall` then `--install` |


## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
