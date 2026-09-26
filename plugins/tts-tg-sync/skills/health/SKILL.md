---
name: health
description: Health check for hotkey text-to-speech - companion engine, Kokoro venv, Supertonic fallback, locks, audio processes, links and hotkey binding. TRIGGERS - tts health check, kokoro health, tts status
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# System Health Check

Run a 10-subsystem health check across the text-to-speech engines, locks, links and hotkey binding. Produces a pass/fail report table with actionable fix recommendations.

This plugin no longer has a Telegram bot to check; the bot it used to manage was retired on 2026-09-24.

> **Platform**: macOS (Apple Silicon)

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

- Diagnose why the read-aloud hotkey is silent or slow
- Verify system readiness after bootstrap or configuration changes
- Investigate intermittent failures in the TTS pipeline
- Check for stale locks, zombie audio processes, or orphaned temp files

## Requirements

- Python 3.14 with Kokoro venv at `~/.local/share/kokoro/.venv`
- `claude-tts-companion` for the primary engine (optional; the Supertonic fallback covers its absence)

## Workflow Phases

### Phase 1: Run All 10 Health Checks

Execute each check and collect results. Each check returns `[OK]` or `[FAIL]` with a brief diagnostic message. Check 6 and check 9 are informational.

#### Check 1: Companion Engine

```bash
curl -s --max-time 2 "http://[::1]:8780/health"
```

Pass if it answers. Fail means hotkeys fall back to Supertonic (slower first press, no subtitles).

#### Check 2: Kokoro venv

```bash
[[ -d ~/.local/share/kokoro/.venv ]]
```

Pass if the directory exists.

#### Check 3: MLX-Audio Import

```bash
~/.local/share/kokoro/.venv/bin/python -c "from mlx_audio.tts.utils import load_model; print('MLX OK')"
```

Pass if import succeeds with exit code 0.

#### Check 4: Apple Silicon

```bash
[[ "$(uname -m)" == "arm64" ]]
```

Pass if architecture is arm64. MLX-Audio requires Apple Silicon (M1+).

#### Check 5: Lock State

```bash
for LOCK_FILE in /tmp/kokoro-tts.lock /tmp/tts_kokoro.lock; do
  if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE")
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE") ))
    if kill -0 "$LOCK_PID" 2>/dev/null; then
      if [[ $LOCK_AGE -gt 30 ]]; then
        echo "$LOCK_FILE STALE (PID $LOCK_PID alive but lock age ${LOCK_AGE}s > 30s threshold)"
      else
        echo "$LOCK_FILE ACTIVE (PID $LOCK_PID, age ${LOCK_AGE}s)"
      fi
    else
      echo "$LOCK_FILE ORPHANED (PID $LOCK_PID not running, age ${LOCK_AGE}s)"
    fi
  else
    echo "$LOCK_FILE NO LOCK (idle)"
  fi
done
```

Pass if neither lock exists, or an existing one is active and under 30s old. Fail if orphaned, or stale while nothing is playing. `/tmp/tts_kokoro.lock` has no heartbeat, so it legitimately passes 30s during a long Kokoro utterance.

#### Check 6: Audio Processes

```bash
pgrep -x afplay
pgrep -x say
```

Informational check. Reports count of running audio processes. Not a pass/fail -- just reports state.

#### Check 7: Stale WAV Files

```bash
find /tmp -maxdepth 1 -name "kokoro-tts-*.wav" -mmin +5 2>/dev/null
```

Pass if no stale WAV files found (older than 5 minutes). Fail if orphaned WAVs exist.

#### Check 8: Shell Links

```bash
for s in tts_read_clipboard_wrapper.sh tts_read_clipboard.sh tts_kokoro.sh tts_kokoro_audition.sh tts_speed_up.sh tts_speed_down.sh tts_speed_reset.sh tts_stop.sh; do
  [[ -L ~/.local/bin/$s && -e ~/.local/bin/$s ]] && echo "OK $s -> $(readlink ~/.local/bin/$s)" || echo "FAIL $s missing or dangling"
done
```

Pass if every link exists and resolves to a file in the plugin. `tts_speed_set.sh` needs no link: the speed scripts resolve their own real directory and call it from there.

#### Check 9: Hotkey Binding

```bash
grep -c "tts_read_clipboard_wrapper.sh" ~/.config/karabiner/karabiner.json 2>/dev/null || echo "0 (no Karabiner rule — check BetterTouchTool)"
```

Informational. At least one hit means a Karabiner-Elements rule calls the wrapper; zero is fine if BetterTouchTool holds the binding instead.

#### Check 10: Supertonic Fallback

```bash
{ command -v uv || ls ~/.proto/shims/uv ~/.proto/bin/uv; } 2>/dev/null | head -1
[[ -d ~/.cache/supertonic2/onnx ]] && echo "Supertonic model cached" || echo "Supertonic model not cached (first fallback run downloads it)"
```

Pass if `uv` resolves. The fallback is only used when the companion is down.

### Phase 2: Report

Display results as a table:

```
| # | Subsystem          | Status | Detail                               |
|---|--------------------|--------|--------------------------------------|
| 1 | Companion Engine   | [OK]   | [::1]:8780 healthy                   |
| 2 | Kokoro venv        | [OK]   | ~/.local/share/kokoro/.venv          |
| 3 | MLX-Audio Import   | [OK]   | mlx_audio module loaded              |
| 4 | Apple Silicon      | [OK]   | arm64 (MLX Metal)                    |
| 5 | Lock State         | [OK]   | No locks (idle)                      |
| 6 | Audio Processes    | [OK]   | 0 afplay, 0 say                      |
| 7 | Stale WAVs         | [OK]   | No orphaned files                    |
| 8 | Shell Links        | [OK]   | 8/8 resolve into the plugin          |
| 9 | Hotkey Binding     | [OK]   | Karabiner rule calls the wrapper     |
|10 | Supertonic Fallback| [OK]   | uv found, model cached               |
```

### Phase 3: Summary and Recommendations

- Report total pass/fail counts (e.g., "9/10 checks passed")
- For each failure, recommend the appropriate fix or skill to invoke

## TodoWrite Task Templates

```
1. [Run] Execute all 10 health checks and collect results
2. [Report] Display results table with [OK]/[FAIL] status for each subsystem
3. [Summary] Show pass/fail counts (e.g., 9/10 passed)
4. [Recommend] Suggest fixes for any failures, referencing relevant skills
```

## Post-Change Checklist

- [ ] All 10 checks executed (none skipped due to early exit)
- [ ] Results table displayed with consistent formatting
- [ ] Each failure has an actionable recommendation

---

## Troubleshooting

| Issue                         | Cause                               | Solution                                                              |
| ----------------------------- | ----------------------------------- | --------------------------------------------------------------------- |
| All checks fail               | Environment not set up              | Run `full-stack-bootstrap` skill first                                |
| Companion down (check 1)      | `claude-tts-companion` not running  | See the `claude-tts-companion` plugin; hotkeys still use Supertonic   |
| Only Kokoro checks fail (2-3) | Kokoro venv missing or broken       | Run `kokoro-install.sh --health` for detailed report                  |
| Not Apple Silicon (check 4)   | Running on Intel Mac or Linux       | MLX-Audio requires Apple Silicon (M1+)                                |
| Lock stuck (check 5)          | Stale lock from crashed TTS process | Check lock age and PID; see `diagnostic-issue-resolver` skill         |
| Stale WAVs found (check 7)    | TTS process crashed mid-generation  | Clean with `rm /tmp/kokoro-tts-*.wav`; investigate crash cause        |
| Shell links missing (check 8) | Bootstrap incomplete                | Re-run the link step from the `setup` or `full-stack-bootstrap` skill |
| No uv (check 10)              | uv not installed                    | `brew install uv`                                                     |

## Reference Documentation

- [Health Checks](./references/health-checks.md) - Detailed description of each check, failure meaning, and remediation
- [Evolution Log](./references/evolution-log.md) - Change history for this skill

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
