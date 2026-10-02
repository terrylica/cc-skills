# Stop-hook output: where summaries go

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md).

## What each event does with hook output

From the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) (decision-control table, "Stop decision control" and the exit-code table):

| Event              | `additionalContext`                                                                                                                                                                                                                                                 | Blocking                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Stop, SubagentStop | Accepted as `hookSpecificOutput.additionalContext`, but it **continues the conversation**: "The conversation continues so Claude can act on it", under the same loop protections as `decision: "block"` (`stop_hook_active` and the 8-consecutive-continuation cap) | `decision: "block"` or exit 2 prevents Claude from stopping |
| PreCompact         | Not part of its decision pattern                                                                                                                                                                                                                                    | `decision: "block"` or exit 2 blocks compaction             |
| SessionEnd         | Discarded: "Claude Code discards their JSON output fields"                                                                                                                                                                                                          | No decision control; stderr is shown to the user only       |
| Notification       | Not part of its decision pattern                                                                                                                                                                                                                                    | No blocking; "Exit code and stderr are ignored"             |

So on Stop, `additionalContext` is not a passive note: every emission keeps Claude running for another turn. An informational summary must not use it.

## How itp-hooks routes Stop summaries

`stop-orchestrator.ts` runs the Stop subhooks (`stop-subprocess-session-cleanup.ts`, `stop-hook-error-summary.ts`, `stop-ty-project-check.ts`, `stop-markdown-lint.ts`) and writes their aggregated summary to **stderr**, where it is visible in the transcript for debugging but does not keep the session going.

A subhook that genuinely needs Claude to act before stopping returns `decision: "block"` with a `reason`; the orchestrator joins those reasons and emits them on stdout. No itp-hooks Stop subhook does so today.

## The guard

`tasks/hook-lint/stop-additional-context.sh` (part of `moon run repo:hook-lint`, so it runs on every push) scans every registered Stop, SubagentStop, SessionEnd, PreCompact and Notification hook and fails on an `additionalContext` emission without a justification. The escape hatch is a `STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>` source comment, for a hook that deliberately continues the conversation.
