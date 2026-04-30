# clarify-prompts

Stop-hook nudge that asks Claude to invoke `AskUserQuestion` (in plain non-technical terms) whenever the just-finished turn left ambiguity unresolved. Self-suppresses when the agent already asked, when running inside an autoloop session, or when triggered by a subagent.

## Why

Claude often stops a turn even when there's a meaningful unresolved choice — scope, implementation direction, missing requirement. This hook lightly pushes the main agent to surface those decisions through the structured `AskUserQuestion` tool (multi-choice, layman language) instead of stopping silently or making an assumption.

## Behavior

The Stop hook returns `{"decision": "block", "reason": "..."}` — Claude reads the reason on its next turn and decides whether to invoke `AskUserQuestion`. If nothing is genuinely ambiguous, Claude stops on the next pass (the `stop_hook_active` loop guard prevents repeat blocks).

## Five guards

| Guard               | Triggers                                      | Outcome    |
| ------------------- | --------------------------------------------- | ---------- |
| `stop_hook_active`  | Claude Code re-fire flag set                  | Allow stop |
| Subagent transcript | `transcript_path` contains `/agents/`         | Allow stop |
| Autonomous-loop     | `session_id` matches a registry loop owner    | Allow stop |
| Autonomous-loop cwd | `cwd` matches any loop's contract directory   | Allow stop |
| Already-asked       | Last assistant turn invoked `AskUserQuestion` | Allow stop |
| (default)           | None of the above                             | **Nudge**  |

The autoloop guards are critical: an `AskUserQuestion` invocation inside an overnight loop session would block the agent until morning. The hook reads `~/.claude/loops/registry.json` to detect loop sessions and stays silent in those.

## Failure mode

Any unexpected error (missing transcript, jq failure, registry corruption) fails open — exit 0 → normal stop. The hook should never wedge the main agent.

## Files

- `hooks/clarify-nudge.sh` — the Stop-hook script
- `hooks/hooks.json` — Claude Code hook registration
- `tests/test-clarify-nudge.sh` — 12-case test harness covering all five guards + robustness

## Test

```bash
bash plugins/clarify-prompts/tests/test-clarify-nudge.sh
```

## Tuning the nudge

Edit the `reason` string in `clarify-nudge.sh` to adjust how Claude is instructed. Keep it specific enough to surface `AskUserQuestion` as the right tool, soft enough that Claude can decline when nothing's ambiguous.
