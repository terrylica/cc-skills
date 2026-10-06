# PreToolUse:Bash guard orchestrator

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Issue: [#111](https://github.com/terrylica/cc-skills/issues/111).

`hooks/pretooluse-bash-guard-orchestrator.ts` runs the plugin's 24 Bash guards in one bun process. Before it, every Bash tool call started 26 bun processes from this plugin alone, one per guard, and every one of them was unconditional.

## How a guard runs inside it

Nothing about a guard's logic changes. Each guard file exports its existing `main()` and only calls it itself when run directly (`if (import.meta.main)`), so its standalone entry point and its tests are untouched. The orchestrator imports every `main()` and runs each through `runGuardMainInProcess()` in `pretooluse-helpers.ts`, which works like this:

- each run gets its own `AsyncLocalStorage` context holding the parsed input and an empty response list;
- `parseStdinOrAllow()` returns that input instead of reading stdin;
- `output()` (and therefore `allow`, `deny`, `ask`, `allowWithInput`) appends to the list instead of printing.

A guard that overruns its time budget is abandoned, not killed. If it calls `output()` later, the response lands in its own discarded list, never in another guard's. Once the orchestrator has started, an `output()` outside any run is dropped, so nothing can print a second JSON line. The orchestrator exits explicitly after printing its one response, so an abandoned guard cannot keep the process alive.

## Precedence

The orchestrator folds the guards' responses the way Claude Code folds parallel hooks: deny > ask > allow.

| Responses seen             | Result                                                                            |
| -------------------------- | --------------------------------------------------------------------------------- |
| any deny                   | The first deny in registry order. Later guards do not run.                        |
| an ask and no deny         | The first ask. Later guards still run, because a later deny outranks it.          |
| only allows                | Allow, with every guard's `additionalContext` joined by blank lines.              |
| a guard throws or overruns | That guard is skipped (fail-open), as a crashed or timed-out standalone hook was. |

Reasons are the deciding guard's own text, verbatim. `pretooluse-bash-guard-orchestrator.test.ts` checks this differentially. For every command in its corpus, it runs all 24 guards standalone as Claude Code did, folds them with the rules above, and requires the orchestrator's response to be identical.

## What stays outside it

- **`pretooluse-subprocess-stdin-inlet-guard.ts`** and **`pretooluse-pueue-wrap-guard.ts`** rewrite the command through `updatedInput`. Claude Code keeps only the last hook's `updatedInput` ([anthropics/claude-code#15897](https://github.com/anthropics/claude-code/issues/15897)), so they stay separate entries, and pueue-wrap stays last (invariant 3 in the hub).
- **`pretooluse-process-storm-guard.mjs`** and **`pretooluse-broad-process-signal-guard.ts`** also inspect files written with Write and Edit. Their Bash path runs inside the orchestrator, and they keep a `Write|Edit` entry of their own.

### pueue-wrap-guard

[`pretooluse-pueue-wrap-guard.ts`](../hooks/pretooluse-pueue-wrap-guard.ts) does two things, combined in one hook because only one hook's `updatedInput` survives:

1. **Token injection**: prepends `OP_SERVICE_ACCOUNT_TOKEN="$(…)"` to commands that target the "Claude Automation" 1Password vault, avoiding biometric prompts. The substitution comes from a source you configure in Claude Code's environment: `OP_SA_TOKEN_CMD`, a command that prints the token (for example `vault get op-service-account token`), emitted as single-quoted words so the shell runs it with no expansion; or else `OP_SA_TOKEN_FILE`, a token file you name. There is no default path. Only the command or the path goes into the rewritten command, never the token, because Claude Code records the rewritten command in transcripts. Skipped when the command already sets the variable, when `OP_SERVICE_ACCOUNT_TOKEN` is already exported (the Bash tool inherits it), or when nothing is configured.
2. **Pueue wrapping**: wraps known long-running Bash commands (an allowlist, `LONG_RUNNING_PATTERNS`) as `pueue add` → `pueue wait` → `pueue log`, so the output still flows back to Claude, and records the task ID for session-scoped cleanup. If queueing fails it runs the command directly. A `# PUEUE-WRAP` comment forces wrapping; `# PUEUE-SKIP` prevents it. Pueue commands, pueue scripts, already-backgrounded commands, fast local tools (`git`, linters, `cargo` subcommands) and SSH commands are never auto-wrapped.

It **must be the last PreToolUse entry** in `hooks.json`: Claude Code applies `updatedInput` last-writer-wins, so a later hook's `updatedInput`, even an undefined one, would replace the rewritten command. [`tasks/hook-lint/pueue-wrap-last.sh`](../../../tasks/hook-lint/pueue-wrap-last.sh) enforces this; it runs in `moon run repo:hook-lint` and as Check 4g of `tasks/release/preflight`.

Related: [pueue-local-guard.md](./pueue-local-guard.md), [pueue-reminder.md](./pueue-reminder.md), and `devops-tools`' [claude-code-integration.md](/plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md).

## Why not the `if` field

The [`if` field](https://code.claude.com/docs/en/hooks#common-fields) skips a hook unless a subcommand matches a permission rule, and it costs nothing to add. It was measured first, on 2026-10-01. Fifteen command forms were run through a hook gated by `"if": "Bash(gh *)"` and through an ungated control, which fired 15 of 15. The gated hook did not run for nine of them:

- `bash -c '…'` and `sh -c "…"`
- an absolute path such as `/opt/homebrew/bin/gh`
- `env gh`, `command gh` and `time gh`
- `eval "…"`
- a heredoc fed to `bash`
- `ssh host '…'`

Every guard here matches its regex against the whole command string, so it sees all fifteen. The official docs also call the filter best-effort:

> Because the `if` filter is best-effort, use the [permission system](https://code.claude.com/docs/en/permissions) rather than a hook to enforce a hard allow or deny.

The full table is on [#111](https://github.com/terrylica/cc-skills/issues/111).

## Adding a Bash guard

1. Write the guard as usual with the `pretooluse-helpers.ts` outputs. Use `export async function main()`, and make the top-level call `if (import.meta.main) void main().catch(…)`.
2. Add it to `BASH_GUARD_REGISTRY`, with a `timeoutMs` and a `description`. Do not add it to `hooks.json`.
3. Add a command that exercises it to the differential test's corpus.

A guard that must rewrite the command through `updatedInput` is the exception. Register it in `hooks.json`, before `pretooluse-pueue-wrap-guard.ts`.
