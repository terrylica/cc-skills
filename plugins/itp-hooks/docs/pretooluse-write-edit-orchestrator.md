# PreToolUse Write/Edit Orchestrator

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Topic**: Inlined blocking subhooks

## Overview

`hooks/pretooluse-write-edit-orchestrator.ts` is registered in `hooks/hooks.json` as one PreToolUse entry with matcher `Write|Edit`. It runs every edit-time blocking check in a single bun process, so a Write or Edit pays one bun cold start instead of one per check.

Any tool name other than `Write` or `Edit` is allowed before the registry runs.

## Subhook registry

The registry is `PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY` in the orchestrator source; it is the source of truth for this table. It holds 11 subhooks, run serially in this order (lightest first):

| #   | Subhook                     | Blocks a Write/Edit that…                                                                  | Timeout  | Spoke                                                                |
| --- | --------------------------- | ------------------------------------------------------------------------------------------ | -------- | -------------------------------------------------------------------- |
| 1   | `version-guard`             | adds a hardcoded version string to markdown outside CHANGELOG/HISTORY/ADR/planning paths   | 3000 ms  | [version-guard.md](./version-guard.md)                               |
| 2   | `shell-script-safety-guard` | adds `$?` after an `else`-less `fi`, or `local`/`export`/… `VAR=$(cmd)`, to a shell script | 3000 ms  | `~/.claude/shell-script-safety-CLAUDE.md`                            |
| 3   | `skill-plugin-root-guard`   | references `CLAUDE_PLUGIN_ROOT` in skill markdown in a shape the runtime cannot substitute | 3000 ms  | [skill-plugin-root-guard.md](./skill-plugin-root-guard.md)           |
| 4   | `typescript-version-guard`  | declares TypeScript below 7.x in a `package.json`                                          | 3000 ms  | `Skill(typescript-7)`                                                |
| 5   | `hoisted-deps-guard`        | breaks the `pyproject.toml` root-only dependency and `[tool.uv.sources]` path policies     | 4000 ms  | [hoisted-deps-guard.md](./hoisted-deps-guard.md)                     |
| 6   | `mise-hygiene-guard`        | puts secrets in, or over-grows, a `mise.toml`                                              | 3000 ms  | [mise-hygiene-guard.md](./mise-hygiene-guard.md)                     |
| 7   | `pyi-stub-guard`            | adds top-level definitions to a Python `__init__.py` / `__init__.pyi`                      | 3000 ms  | [pyi-stub-guard.md](./pyi-stub-guard.md)                             |
| 8   | `native-binary-guard`       | introduces a shell script or bare interpreter as a launchd program                         | 4000 ms  | [native-binary-guard.md](./native-binary-guard.md)                   |
| 9   | `gpu-optimization-guard`    | writes a PyTorch training script missing the mandatory GPU optimizations                   | 4000 ms  | [gpu-optimization-guard.md](./gpu-optimization-guard.md)             |
| 10  | `file-size-guard`           | would push a file past its per-extension line limit                                        | 4500 ms  | [file-size-guard.md](./file-size-guard.md)                           |
| 11  | `vale-claude-md-guard`      | leaves vale warning-or-error findings in a `CLAUDE.md` (spawns `vale`; heaviest, so last)  | 12000 ms | [vale-terminology-enforcement.md](./vale-terminology-enforcement.md) |

## Run semantics

- Each subhook is a pure `classify…ForOrchestrator(input)` function that returns `allow`, `deny` or `ask`.
- Precedence is deny > ask > allow. The first `deny` stops the run. The first `ask` is held while the remaining subhooks are checked for a `deny`, and becomes the decision if none denies.
- Deny and ask are both written to stdout as `hookSpecificOutput.permissionDecision` JSON with exit 0, plus a stderr diagnostic that reaches only the debug log. Exit 2 is never used: the [hooks reference](https://code.claude.com/docs/en/hooks#exit-code-2) says it "blocks whether or not you print JSON", so it would turn every `ask` into a hard block. An earlier exit-2-on-deny defence cited [anthropics/claude-code#37210](https://github.com/anthropics/claude-code/issues/37210), which was closed not-planned after its reporter found exit 0 with the `hookSpecificOutput` wrapper denied Edit and Write correctly.
- A subhook that exceeds its timeout (`AbortSignal.timeout()`) or throws is logged to stderr and treated as `allow`; the run continues with the next subhook.
- If every subhook allows, the orchestrator allows.

## Contract

The subhook contract is [`lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts`](../hooks/lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts). A subhook:

- does no stdin/stdout I/O and never calls `process.exit`;
- catches its own errors and returns `allow`;
- tests the tool name with `isFileEditToolNameHonoredByPreToolUseBlockingSubhook()`, whose allow-set is exactly `Write` and `Edit`;
- keeps a standalone entry point under `if (import.meta.main)`.

`tasks/hook-lint/orchestrator-subhook-contract.sh` checks the contract statically. Adding a subhook is described in [HOOKS.md "Adding a subhook"](../../../docs/HOOKS.md#adding-a-subhook).
