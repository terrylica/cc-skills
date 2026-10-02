# pueue-wrap-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-pueue-wrap-guard.ts`](../hooks/pretooluse-pueue-wrap-guard.ts), its own `Bash` entry in `hooks/hooks.json` (not part of the Bash guard orchestrator, because it rewrites the command through `updatedInput`).

It does two things, combined in one hook because only one hook's `updatedInput` survives (below):

1. **Token injection**: prepends `OP_SERVICE_ACCOUNT_TOKEN` (read from `~/.claude/.secrets/op-service-account-token`) to commands that target the "Claude Automation" 1Password vault, avoiding biometric prompts. Skipped when the command already sets the variable.
2. **Pueue wrapping**: wraps known long-running Bash commands (an allowlist, `LONG_RUNNING_PATTERNS`) with pueue. A `# PUEUE-WRAP` comment forces wrapping; `# PUEUE-SKIP` prevents it.

Related: [pueue-local-guard.md](./pueue-local-guard.md), [pueue-reminder.md](./pueue-reminder.md), and `devops-tools`' [claude-code-integration.md](/plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md).

## Ordering invariant

It **must be the last PreToolUse entry** in `hooks.json`. Claude Code applies `updatedInput` from multiple hooks last-writer-wins ([anthropics/claude-code#15897](https://github.com/anthropics/claude-code/issues/15897)), so a later hook's `updatedInput` — even an undefined one — would replace the rewritten command. [`tasks/hook-lint/pueue-wrap-last.sh`](../../../tasks/hook-lint/pueue-wrap-last.sh) enforces this; it runs in `moon run repo:hook-lint` and as Check 4g of `tasks/release/preflight`.
