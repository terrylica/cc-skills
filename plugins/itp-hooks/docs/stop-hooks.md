# Stop-hook schema correctness (iter-66 trinity + iter-69 pentad)

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

### iter-66 Stop-hook schema-correctness note (iter-68 trinity + iter-69 pentad expansion)

Per the official Anthropic Claude Code hook schema (verbatim example documented in [GitHub issue #19115](https://github.com/anthropics/claude-code/issues/19115) and the official docs at code.claude.com/docs/en/hooks), the **additionalContext-silently-dropped pentad** comprises five event types with three distinct schema sub-rules but a unified silent-drop symptom:

- **Stop, SubagentStop, PreCompact** support only `{decision: "block", reason}` in their stdout JSON. SubagentStop "uses the same decision control format as Stop"; PreCompact shares the same schema family (the `decision` field is documented as shared across Stop / SubagentStop / PreCompact / PostToolUse / PostToolUseFailure / PostToolBatch / UserPromptSubmit / UserPromptExpansion / ConfigChange — only value is "block").
- **SessionEnd** has an even narrower schema: per Go type definitions ([CorridorSecurity/hookshot](https://pkg.go.dev/github.com/CorridorSecurity/hookshot/claude)), `SessionEndOK` returns _empty output_ — SessionEnd cannot inject any context at all because the session is terminating.
- **Notification** is purely informational with NO decision-control capability ("Exit Code 2 Behavior: N/A — shows stderr to user only, no blocking capability"). Subtypes: `permission_prompt`, `idle_prompt`, `auth_success`. Only stderr on exit 2 reaches the user.

Any `additionalContext` field — top-level OR nested in `hookSpecificOutput` — on any of these five event types is read by NO field consumer in Claude Code and is silently dropped.

This is a different schema from PostToolUse / UserPromptSubmit / SessionStart, where `hookSpecificOutput.additionalContext` IS supported.

**Implication for itp-hooks Stop subhooks**: `stop-markdown-lint.ts`, `stop-ty-project-check.ts`, and `stop-hook-error-summary.ts` each emit `{additionalContext: "summary"}` to their stdout. The `stop-orchestrator.ts` aggregates these — pre-iter-66 it then re-emitted `{additionalContext: aggregated}` to its own stdout, where Claude Code silently dropped it. **iter-66 routes the aggregated summary to stderr** (transcript-visible via Ctrl-R), so operators can still see subhook summaries during debugging. Claude itself does NOT see these on next-turn context — but it never did via the broken stdout route either.

If a future subhook needs to inject context that Claude actually reads, the orchestrator must instead emit `{decision: "block", reason: "<context as instruction>"}`, which keeps Claude running and surfaces the reason as a system reminder. This is reserved for **truly critical** findings (currently only `stop-loop-stall-guard.ts` uses this path via `asyncRewake`).

**Preventive infrastructure** (iter-67 + iter-68 + iter-69): the marketplace-wide audit at `.mise/tasks/audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json.sh` scans every registered Stop / SubagentStop / SessionEnd / PreCompact / Notification hook (the full pentad) for unjustified `additionalContext` emissions and blocks tag publish on violation (release:preflight Check 4j). The escape hatch is a `STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>` source comment. Marketplace currently has 5 Stop hooks (4 CLEAN, 1 WITH-OK-MARKER) and 0 SubagentStop / SessionEnd / PreCompact / Notification hooks — the gate is preventive for the four event types not currently used.

