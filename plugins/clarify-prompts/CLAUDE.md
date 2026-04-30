# clarify-prompts

Single-purpose Stop-hook plugin: nudges the main agent to invoke `AskUserQuestion` when ambiguity remains, with autonomous-loop suppression so overnight campaigns don't get blocked.

**Hub:** [Root CLAUDE.md](../../CLAUDE.md) | **Sibling:** [plugins/CLAUDE.md](../CLAUDE.md)

## Files

| Path                          | Purpose                                                       |
| ----------------------------- | ------------------------------------------------------------- |
| `hooks/clarify-nudge.sh`      | Stop-hook script. Five guards + nudge.                        |
| `hooks/hooks.json`            | Claude Code Stop registration (uses `${CLAUDE_PLUGIN_ROOT}`). |
| `tests/test-clarify-nudge.sh` | 12 cases: all guards, robustness, content verification.       |
| `README.md`                   | User-facing doc.                                              |
| `plugin.json`                 | Plugin manifest.                                              |

## Critical invariants

1. **Fail open.** Any error path must `exit 0`. A wedged main agent is worse than a missed nudge. Verified by the "robustness" cases in the test harness.
2. **Autonomous-loop guards must come BEFORE the already-asked check.** If a loop session also happened to invoke `AskUserQuestion` for some reason, we still want to suppress the nudge (the agent should be quiet during overnight runs, period). Loop guards are checked at step 3, already-asked at step 4.
3. **Match by both `session_id` and `cwd`.** `session_id` is the precise check (loop owner identity); `cwd` is paranoia for sessions where the registry's `owner_session_id` rotated mid-campaign or is `pending-bind`. Both reach the same suppression outcome.
4. **`LOOP_REGISTRY_PATH` env override.** The test harness uses this to inject a synthetic registry. Default `~/.claude/loops/registry.json`. Don't hardcode the path inside the jq filter.
5. **`/agents/` path segment is the subagent marker.** Claude Code stores subagent transcripts under `<project>/agents/<task-uuid>.jsonl`. Main-agent transcripts use the project root directly. If Anthropic changes this convention, the test harness "subagent guard" case will pass while real subagents stop being suppressed — re-validate against a real subagent transcript when bumping Claude Code versions.

## How nudging works

Stop hooks can't directly invoke tools. Returning `{"decision":"block","reason":"..."}` causes Claude Code to:

1. Refuse the stop and resume the conversation.
2. Pass the `reason` string to Claude as a system message on the next turn.
3. Set `stop_hook_active=true` in subsequent Stop-hook firings until the agent finally stops.

Claude _reads_ the reason and decides whether to act. If nothing's ambiguous, it just stops — the loop guard then lets it through. The `reason` is intentionally specific (mentions `AskUserQuestion` by name + the schema constraints) but soft (doesn't demand action).

## Recent changes

- `2026-04-30`: initial — five guards, 12-case test harness, all green. Live-registry verified against the four currently-active autonomous loops on this machine.

## Edit conventions

- Touching `clarify-nudge.sh`? Run the test harness before commit:

  ```bash
  bash plugins/clarify-prompts/tests/test-clarify-nudge.sh
  ```

- Adding a new guard? Add a case to the harness in the same commit. The harness is the contract.
- Changing the nudge `reason`? Verify it still mentions `AskUserQuestion` so the agent knows which tool to use.
