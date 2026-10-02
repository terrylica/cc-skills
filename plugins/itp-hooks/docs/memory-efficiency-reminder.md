# Memory Efficiency Reminder

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Once-per-session best-practices nudge

## Overview

[`posttooluse-memory-efficiency-reminder.ts`](../hooks/posttooluse-memory-efficiency-reminder.ts) is subhook `memory-efficiency-reminder` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 1000 ms). It shows a static memory-efficiency reminder once per session, on the first eligible code-file Write/Edit. It spawns no subprocess; the only work is the gate-file claim.

The reminder reaches Claude as `additional_context` through the orchestrator's merged `{"decision": "block", "reason": …}` output. A PostToolUse hook that prints plain text instead lands only in the transcript, so any standalone use must keep emitting JSON.

## What It Covers

The message is a four-row table plus a line of anti-patterns:

- Avoid copies: zero-copy, views, slices, borrowing, move semantics
- Avoid allocation: pre-allocation, buffer reuse, arenas, object pools
- Cache efficiency: contiguous data, locality, SoA
- Lazy evaluation: streaming, iterators, generators, predicate pushdown, lazy frames
- Anti-patterns: Python list → Arrow copies, `df.to_dict()` in loops, materializing lazy frames with `.values()`, repeated `pd.concat` instead of a pre-sized buffer

## When it fires

- Tool is `Write` or `Edit`, and the file extension is one of `.py .rs .ts .tsx .js .go .java .kt .rb .cpp .c .h .zig`.
- Not a test file (paths containing `test_`, `tests/`, `__tests__/`, `_test.`, `_spec.`, `.test.` or `.spec.`), and not a throwaway file in a temp directory.
- First such edit in the session: the gate is an atomic `O_EXCL` file at `/tmp/.claude-memory-efficiency-reminder/<session-id>.reminded`, claimed through `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`.

## Escape Hatch

There is none. The reminder fires at most once per session, so there is nothing to suppress per file.

## Code

The classifier is `classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifyMemoryEfficiencyReminderForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard.
