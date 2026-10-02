# PostToolUse Write/Edit Orchestrator

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Inlined context-injecting subhooks

## Overview

`hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts` is registered in `hooks/hooks.json` as one PostToolUse entry with matcher `Write|Edit`. It runs every edit-time reminder and lint check in a single bun process and merges what they report into one Claude-visible message.

## Subhook registry

The registry is `POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY` in the orchestrator source; it is the source of truth for this table. It holds 12 subhooks, all run concurrently:

| #   | Subhook                       | Reports, after a Write/Edit…                                                                        | Timeout  | Spoke                                                                |
| --- | ----------------------------- | --------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------- |
| 1   | `leakage-taxonomy-reminder`   | the temporal-leakage taxonomy card, once per session, when new text adjudicates leakage             | 2000 ms  | `~/.claude/leakage-taxonomy-CLAUDE.md`                               |
| 2   | `ty-type-check`               | `ty` type errors in an edited `.py`/`.pyi`                                                          | 5000 ms  | [ty-type-checker.md](./ty-type-checker.md)                           |
| 3   | `tsc-type-check`              | project-scoped `tsc` errors in an edited `.ts`/`.tsx`                                               | 5000 ms  | [tsc-type-check.md](./tsc-type-check.md)                             |
| 4   | `oxlint-check`                | oxlint correctness and suspicious findings in JS/TS                                                 | 5000 ms  | [oxlint-check.md](./oxlint-check.md)                                 |
| 5   | `biome-lint`                  | biome findings that complement oxlint in JS/TS                                                      | 5000 ms  | [biome-lint.md](./biome-lint.md)                                     |
| 6   | `vale-claude-md`              | vale terminology findings in an edited `CLAUDE.md` (informational)                                  | 12000 ms | [vale-terminology-enforcement.md](./vale-terminology-enforcement.md) |
| 7   | `memory-efficiency-reminder`  | a memory-efficiency reminder, once per session, on the first eligible code-file edit                | 1000 ms  | [memory-efficiency-reminder.md](./memory-efficiency-reminder.md)     |
| 8   | `ssot-principles`             | SSoT / dependency-injection anti-patterns found with ast-grep, once per session                     | 3000 ms  | [ssot-principles.md](./ssot-principles.md)                           |
| 9   | `claude-md-size-budget`       | a hub-and-spoke refactor reminder when a `CLAUDE.md` reaches 36,000 characters (90% of 40,000)      | 2000 ms  | this page (escape `CLAUDE-MD-SIZE-OK`)                               |
| 10  | `python-preference-nudge`     | a language-preference reminder on a `.py` edit not allowed by an ancestor `python-allowlist.toml`   | 2000 ms  | [python-preference-nudge.md](./python-preference-nudge.md)           |
| 11  | `typescript-upgrade-reminder` | a TypeScript 7 upgrade reminder, once per session, on the first TS / `package.json` / tsconfig edit | 2000 ms  | `Skill(typescript-7)`                                                |
| 12  | `markdown-hard-wrap-reminder` | hard-wrapped prose that the edit added to a `.md` file                                              | 2000 ms  | [markdown-hard-wrap-reminder.md](./markdown-hard-wrap-reminder.md)   |

## Run semantics

- Every subhook runs at once under `Promise.all`; none can stop another. A PostToolUse hook cannot undo the tool call, so there is nothing to short-circuit.
- Each subhook returns `noop` or `additional_context`. The orchestrator prints nothing when every subhook returns `noop`.
- Otherwise it prints one `{"decision": "block", "reason": …}` object whose reason concatenates every contribution. When two or more subhooks contribute, each section is prefixed `[orchestrator-subhook: <name>]`. `decision: "block"` here does not undo the edit; it is the PostToolUse channel that shows `reason` to Claude.
- A subhook that exceeds its timeout contributes a short "timed out — verify manually" note instead of silence; one that throws is logged and contributes nothing.
- The merged reason is truncated to stay below Claude Code's 10,000-character hook-output limit.

## Contract

The subhook contract is [`lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`](../hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts). A subhook:

- does no stdin/stdout I/O and never calls `process.exit`;
- tests the tool name with `isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook()`, whose allow-set is exactly `Write` and `Edit`;
- runs subprocesses with the async helpers in `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`, never `Bun.spawnSync`, which would block the event loop and serialise the whole `Promise.all` ([Bun docs](https://bun.com/docs/api/spawn)); `tasks/hook-lint/orchestrator-spawnsync.sh` enforces this;
- claims once-per-session reminders through the shared atomic `O_EXCL` gate-file helpers in the same file;
- skips throwaway files in temp directories with the shared temp-scratch helper when it reminds on edited content.

See [HOOKS.md "In-Process Orchestrators"](../../../docs/HOOKS.md#in-process-orchestrators).
