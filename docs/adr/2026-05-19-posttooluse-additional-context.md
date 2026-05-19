---
status: implemented
date: 2026-05-19
decision-maker: Terry Li
consulted: [web-search, github-issues]
research-method: docs-and-issue-research
supersedes: 2025-12-17-posttooluse-hook-visibility.md
---

# ADR: Use `hookSpecificOutput.additionalContext` for PostToolUse Reminders

## Context and Problem Statement

[ADR 2025-12-17](./2025-12-17-posttooluse-hook-visibility.md) documented that PostToolUse hooks
had to emit `{"decision": "block", "reason": "..."}` to make stdout visible to Claude. That
workaround had two known downsides:

1. Transcript labels the output as `"PostToolUse:Bash hook returned blocking error"` — alarming
   and misleading, since nothing is blocked.
2. `decision: "block"` is documented to **halt the agent loop** before the next model call, which
   is wrong semantics for an informational reminder.

Reported by user 2026-05-19 while running v1.172.0: the `rust-tools` SOTA reminder hook showed up
as a "blocking error" in the transcript after a benign `Read` call in `ccmax-monitor`.

## Research

- [Issue #24788](https://github.com/anthropics/claude-code/issues/24788) — reporter expects
  `hookSpecificOutput.additionalContext` to inject context for the model. Open bug is **MCP-tool
  specific** (Windows MSYS, MCP server via Docker stdio). Standard tools work as documented.
- [Issue #40380](https://github.com/anthropics/claude-code/issues/40380) — `systemMessage` alone
  is silently dropped on PreToolUse/PostToolUse; must be paired with `hookSpecificOutput`.
- Current Claude Code hooks documentation (per 2026-05 web search):
  > "Claude Code wraps the string in a system reminder and inserts it into the conversation at
  > the point where the hook fired. Claude reads the reminder on the next model request, but it
  > does not appear as a chat message in the interface."
  > — applies to `hookSpecificOutput.additionalContext` for PreToolUse, PostToolUse,
  > PostToolUseFailure, and PostToolBatch.
- Hook output cap: 10,000 characters; overflow saved to file, replaced with preview + path.

## Decision

For PostToolUse hooks that need to inject an informational reminder into Claude's context **on
standard tools** (Read, Glob, Grep, Bash, Edit, Write), use:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "[HOOK-NAME] message to Claude"
  }
}
```

Exit code 0. No `decision: "block"`.

### When to still use `decision: "block"`

Only when the hook genuinely needs to **stop the agent loop** before the next model call (e.g., a
security gate that detected a violation and wants the model to handle it before continuing). For
informational reminders, never.

### MCP tool exception

If your matcher targets MCP tools (`mcp__*` patterns), `additionalContext` may not surface per
issue #24788. Fall back to `decision: "block"` with reason, or use stderr + exit 2 (which the
issue reporter confirmed still works for MCP).

## Implementation Pattern

```typescript
function emitAdditionalContext(context: string): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: context,
      },
    }),
  );
}
```

```bash
#!/usr/bin/env bash
jq -n --arg ctx "[HOOK] Your message" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
```

## Migration

Search for `decision: "block"` in PostToolUse hooks; for each, decide:

- **Informational reminder** → migrate to `additionalContext` (this ADR)
- **Intentional agent-loop halt** → leave as is, but document why

Known migrations done:

- `plugins/rust-tools/hooks/posttooluse-rust-sota-reminder.ts` — 2026-05-19

Pending audit (run `rg 'decision.*block' plugins/*/hooks/`):

```bash
rg -l 'decision.*block' plugins/*/hooks/
```

## Consequences

### Positive

- Transcript no longer shows misleading "blocking error" label
- Agent loop is not interrupted for informational reminders (correct semantics)
- Reminder still visible to Claude (wrapped in system-reminder block next to the tool result)
- Multiple hooks can each contribute `additionalContext` — all surface to Claude

### Negative

- MCP-tool matchers can't use this format yet (issue #24788) — must use the old pattern
- 10,000 char cap (vs. apparently uncapped for `decision.reason` historically — needs
  verification if writing a verbose reminder)

## Verification Protocol

After deploying this change, verify on next Claude Code restart:

1. Open a fresh session in any Rust project (e.g., `ccmax-monitor`)
2. Run any tool that matches the hook (e.g., `Read` of any file)
3. **Expected**: No "blocking error" label appears in the transcript.
4. **Expected**: The model demonstrates awareness of the rust-tools reminder (e.g., references
   `cargo-nextest` or `samply` when discussing Rust performance) on a subsequent prompt.
5. **Failure mode**: If the model has no awareness of the reminder, revert to
   `decision: "block"` and re-open this ADR.

## References

- [Superseded ADR 2025-12-17](./2025-12-17-posttooluse-hook-visibility.md)
- [Claude Code issue #24788 — additionalContext MCP visibility bug](https://github.com/anthropics/claude-code/issues/24788)
- [Claude Code issue #40380 — systemMessage drop bug](https://github.com/anthropics/claude-code/issues/40380)
- [hooks-development skill](/plugins/itp-hooks/skills/hooks-development/SKILL.md)
