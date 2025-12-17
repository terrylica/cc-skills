---
status: implemented
date: 2025-12-17
decision-maker: Terry Li
consulted: [claude-code-guide, web-research]
research-method: empirical-testing
---

# ADR: PostToolUse Hook Output Visibility to Claude

## Context and Problem Statement

When creating a PostToolUse hook for chezmoi sync reminders, the hook's stdout output was not visible to Claude despite executing correctly. Debug logging confirmed the hook ran and produced output, but Claude never received the message.

**Investigation revealed**: Claude Code only surfaces PostToolUse hook output when the JSON contains `"decision": "block"`.

### Before/After

**Before**: Plain text or JSON without `decision: block` - output lost

```bash
# Plain text - NOT visible to Claude
echo "INSTRUCTION: ~/.gitconfig is tracked by chezmoi..."

# JSON without decision:block - NOT visible to Claude
echo '{"hookSpecificOutput":{"additionalContext":"..."}}'
```

**After**: JSON with `decision: block` - output visible

```bash
# JSON with decision:block - VISIBLE to Claude
jq -n --arg reason "..." '{decision: "block", reason: $reason}'
```

## Decision Drivers

- Hook executed successfully (verified via debug logging)
- Output was produced (verified via manual testing)
- Claude never received the message
- [GitHub Issue #3983](https://github.com/anthropics/claude-code/issues/3983) confirmed this is expected behavior

## Research Findings

From [official Claude Code hooks documentation](https://code.claude.com/docs/en/hooks):

| Exit Code | stdout Behavior                         | Claude Visibility             |
| --------- | --------------------------------------- | ----------------------------- |
| **0**     | JSON parsed, shown in verbose mode only | Only if `"decision": "block"` |
| **2**     | Ignored, uses stderr instead            | stderr shown to Claude        |
| **Other** | stderr shown in verbose mode            | Not shown to Claude           |

### JSON Output Format (Exit Code 0)

```json
{
  "decision": "block",
  "reason": "Explanation shown to Claude",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Extra context (informational only)"
  },
  "continue": true,
  "suppressOutput": true,
  "systemMessage": "Optional warning for user"
}
```

**Critical**: The `"decision": "block"` field is **required** for the `"reason"` to be visible to Claude, even if you're not actually blocking the operation.

## Decision Outcome

For PostToolUse hooks that need to communicate with Claude:

1. **Use JSON format** with `"decision": "block"` and `"reason"` fields
2. **Exit with code 0** (JSON output ignored for exit code 2)
3. **Accept the "blocking error" label** in transcript (it's just a label, operation continues)

### Implementation Pattern

```bash
#!/usr/bin/env bash
# PostToolUse hook that communicates with Claude

if [[ condition_met ]]; then
    jq -n \
        --arg reason "[HOOK] Your message to Claude here" \
        '{decision: "block", reason: $reason}'
fi

exit 0
```

## Consequences

### Positive

- Hook output now visible to Claude
- Claude can act on hook guidance
- Pattern documented for future hooks

### Negative

- "Blocking error" label in transcript is misleading (operation is not actually blocked)
- Counterintuitive requirement (must use `decision: block` even when not blocking)

## References

- [GitHub Issue #3983 - PostToolUse hook JSON output not processed](https://github.com/anthropics/claude-code/issues/3983)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- Related: [PreToolUse/PostToolUse Hooks ADR](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
