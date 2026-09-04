# itp-hooks Plugin

> Claude Code hooks for ITP workflow enforcement, code correctness, and commit validation.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [gh-tools CLAUDE.md](../gh-tools/CLAUDE.md) | **Spoke index**: [docs/spoke-index.md](./docs/spoke-index.md)

## Invariants — read before editing

1. **Keep this file a slim hub.** The size guard warns at 36k and Claude Code stops fully loading a `CLAUDE.md` over **40,000 characters** (counted in UTF-16 code units, not bytes — see `hooks/posttooluse-claude-md-size-budget-reminder.ts`). Prettier repads every cell in a table to its widest row, so one long cell inflates the whole table; **keep every Purpose cell to a short clause** and put the narrative in the hook's own spoke. Measure after formatting, never before.
2. **`hooks.json` is the SSoT for registration**, not this file. A hook listed here but unregistered there does not run.
3. **`pretooluse-pueue-wrap-guard.ts` MUST stay the LAST PreToolUse entry** in `hooks.json` (iter-61 audit) — it auto-wraps long-running commands, so any guard after it never sees the unwrapped command.
4. **Do not re-register `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts`** (retired 2026-08-05, premise dead, false-positives only). It is kept solely as the iter-107 helper's reference implementation.
5. **No full-table snapshot docs.** A spoke owns one subject; a doc that mirrors these tables drifts out of sync with the spokes. [docs/spoke-index.md](./docs/spoke-index.md) is an index of subjects, not a snapshot of hook rows.
6. **TypeScript/Bun is preferred for new hooks** (per `lifecycle-reference.md`); bash is acceptable only for simple pattern matching.

## Hooks

Registration lives in `hooks/hooks.json`. Each row is one clause; the spoke is the SSoT for that hook.

### PreToolUse

Orchestrator arc: [pretooluse-write-edit-orchestrator.md](./docs/pretooluse-write-edit-orchestrator.md). "iter-NN" in the Matcher column means the hook is inlined as a subhook of that orchestrator rather than registered standalone.

| Hook                                                         | Matcher                | Purpose                                       | Spoke                                                       |
| ------------------------------------------------------------ | ---------------------- | --------------------------------------------- | ----------------------------------------------------------- |
| `pretooluse-fake-data-guard.mjs`                             | Write                  | Blocks fake/placeholder data in prod code     | [→](./docs/fake-data-guard.md)                              |
| `pretooluse-version-guard.ts`                                | iter-85                | Hardcoded-version blocker for markdown        | [→](./docs/version-guard.md)                                |
| `pretooluse-process-storm-guard.mjs`                         | Bash\|Write\|Edit      | Blocks fork-bomb patterns                     | [→](./docs/process-storm-guard.md)                          |
| `pretooluse-cwd-deletion-guard.ts`                           | Bash                   | Blocks deleting the CWD                       | [→](./docs/cwd-deletion-guard.md)                           |
| `pretooluse-git-worktree-guard.ts`                           | Bash                   | Enforces worktree-per-branch                  | [→](./docs/git-worktree-guard.md)                           |
| `pretooluse-vale-claude-md-guard.ts`                         | iter-91                | Rejects CLAUDE.md edits with vale findings    | [→](./docs/vale-terminology-enforcement.md)                 |
| `pretooluse-hoisted-deps-guard.ts`                           | iter-86                | pyproject.toml hoisting/path-escape policy    | [→](./docs/hoisted-deps-guard.md)                           |
| `pretooluse-gpu-optimization-guard.ts`                       | iter-87                | GPU optimization enforcement (6 checks)       | [→](./docs/gpu-optimization-guard.md)                       |
| `pretooluse-mise-hygiene-guard.ts`                           | iter-88                | mise.toml secrets + size hygiene              | [→](./docs/mise-hygiene-guard.md)                           |
| `pretooluse-file-size-guard.ts`                              | iter-84                | Per-extension file-size bloat prevention      | [→](./docs/file-size-guard.md)                              |
| `pretooluse-edit-time-orchestrator-…-iter66-precedent.ts`    | Write\|Edit            | Iter-84→91 orchestrator; all 8 subhooks       | [→](./docs/pretooluse-write-edit-orchestrator.md)           |
| `pretooluse-native-binary-guard.ts`                          | iter-90                | Launchd services must be native binaries      | [→](./docs/native-binary-guard.md)                          |
| `pretooluse-pyi-stub-guard.ts`                               | iter-89                | Blocks top-level defs in Python `__init__`    | [→](./docs/pyi-stub-guard.md)                               |
| `pretooluse-inline-ignore-guard.ts`                          | Write\|Edit            | Blocks new inline lint suppressions           | [→](./docs/inline-ignore-policy.md)                         |
| `pretooluse-uv-enforcement-guard.ts`                         | Bash                   | Blocks non-UV Python package operations       | [→](./docs/uv-enforcement-guard.md)                         |
| `pretooluse-pueue-local-guard.ts`                            | Bash                   | Pueue commands must target the local daemon   | [→](./docs/pueue-local-guard.md)                            |
| `pretooluse-cargo-tty-guard.ts`                              | Bash                   | Redirects backgrounded cargo to PUEUE         | [→](./docs/cargo-tty-guard.md)                              |
| `pretooluse-skill-plugin-root-guard.ts`                      | Write\|Edit orch.      | Skills must use `cc-plugin-root`              | [→](./docs/skill-plugin-root-guard.md)                      |
| `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts`  | **RETIRED 2026-08-05** | Unregistered; kept as iter-107 reference impl | [→](./docs/layer3-stripped-path-guard.md)                   |
| `pretooluse-pueue-wrap-guard.ts`                             | Bash                   | Auto-wraps long-running commands (see #3)     | [→](./docs/pueue-wrap-guard.md)                             |
| `pretooluse-webfetch-fallback-guard.ts`                      | WebFetch               | Denies built-in WebFetch; no escape hatch     | `~/.claude/webfetch-fallback-CLAUDE.md`                     |
| `pretooluse-release-notes-extensiveness-guard.ts`            | Bash                   | Hard-blocks releases with thin notes          | [→](./docs/release-notes-extensiveness-guard.md)            |
| `pretooluse-gmail-body-guard.ts`                             | Bash                   | Blocks bad-rendering `gmail draft` bodies     | [→](./docs/gmail-body-guard.md)                             |
| `pretooluse-secret-exposure-guard.ts`                        | Write\|Edit\|MultiEdit | Hard-blocks live credentials in new content   | [→](./docs/secret-and-pii-exposure-guard.md)                |
| `pretooluse-headless-claude-p-guard.ts`                      | Bash                   | Blocks unworkable headless `claude -p` calls  | [→](./docs/headless-claude-p.md)                            |
| `pretooluse-askuserquestion-option-line-terminator-guard.ts` | AskUserQuestion        | Blocks newlines in option label/description   | [→](./docs/askuserquestion-option-line-terminator-guard.md) |

### PostToolUse

Orchestrator arc: [posttooluse-write-edit-orchestrator.md](./docs/posttooluse-write-edit-orchestrator.md).

| Hook                                              | Matcher                      | Purpose                                       | Spoke                                              |
| ------------------------------------------------- | ---------------------------- | --------------------------------------------- | -------------------------------------------------- |
| `posttooluse-reminder.ts`                         | Bash\|Write\|Edit            | Context-aware reminders (UV, Pueue, ADR, …)   | [→](./docs/posttooluse-reminder.md)                |
| `code-correctness-guard.sh`                       | Bash\|Write\|Edit            | Silent-failure detection ONLY                 | [→](./docs/code-correctness-philosophy.md)         |
| `posttooluse-pushover-budget-reminder.ts`         | Bash\|Write\|Edit\|MultiEdit | Pushover message-budget nudge + limits SSoT   | [→](./docs/pushover-budget-reminder.md)            |
| `posttooluse-invented-fallback-reminder.ts`       | Bash\|Write\|Edit\|MultiEdit | Official-values nudge on invented fallbacks   | [→](./docs/invented-fallback-reminder.md)          |
| `posttooluse-vale-claude-md.ts`                   | iter-96                      | Informational vale check on CLAUDE.md edits   | [→](./docs/vale-terminology-enforcement.md)        |
| `posttooluse-glossary-sync.ts`                    | Write\|Edit                  | Auto-sync GLOSSARY.md to Vale vocabulary      | [→](./docs/vale-terminology-enforcement.md)        |
| `posttooluse-terminology-sync.ts`                 | Write\|Edit                  | CLAUDE.md → GLOSSARY.md sync + dupe detection | [→](./docs/vale-terminology-enforcement.md)        |
| `posttooluse-readme-pypi-links.ts`                | Write\|Edit\|MultiEdit       | PyPI badge/link consistency in READMEs        | [→](./docs/readme-pypi-links.md)                   |
| `posttooluse-markdown-table-guard.ts`             | Write\|Edit\|MultiEdit       | Per-edit GFM table structural guard           | [→](./docs/markdown-table-guard.md)                |
| `posttooluse-ssot-principles.ts`                  | iter-97                      | SSoT/DI reminder with ast-grep detection      | [→](./docs/ssot-principles.md)                     |
| `posttooluse-memory-efficiency-reminder.ts`       | iter-98                      | Once-per-session memory-efficiency reminder   | [→](./docs/memory-efficiency-reminder.md)          |
| `posttooluse-ty-type-check.ts`                    | iter-93                      | ty type check on .py/.pyi edits               | [→](./docs/ty-type-checker.md)                     |
| `posttooluse-edit-time-orchestrator-…-iter93….ts` | Write\|Edit                  | PostToolUse multi-aggregation orchestrator    | [→](./docs/posttooluse-write-edit-orchestrator.md) |
| `posttooluse-tsc-type-check.ts`                   | iter-126                     | tsc project-scoped check on .ts/.tsx edits    | [→](./docs/tsc-type-check.md)                      |
| `posttooluse-oxlint-check.ts`                     | iter-95                      | oxlint correctness+suspicious on JS/TS        | [→](./docs/oxlint-check.md)                        |
| `posttooluse-biome-lint.ts`                       | iter-95                      | biome complementary-to-oxlint JS/TS lint      | [→](./docs/biome-lint.md)                          |
| `posttooluse-python-preference-nudge.ts`          | iter-93                      | Language-preference reminder on `.py` edits   | [→](./docs/python-preference-nudge.md)             |
| `posttooluse-mini-inngest-doctrine.ts`            | Bash\|Write\|Edit\|MultiEdit | Nudge to host web-facing services on the Mini | [→](./docs/mini-inngest-doctrine.md)               |
| `posttooluse-pii-exposure-reminder.ts`            | Write\|Edit\|MultiEdit       | Reminder on third-party email/phone on disk   | [→](./docs/secret-and-pii-exposure-guard.md)       |
| `posttooluse-markdown-hard-wrap-reminder.ts`      | iter-93                      | Reminds on net-new hard-wrapped `.md` prose   | [→](./docs/markdown-hard-wrap-reminder.md)         |
| `posttooluse-claude-md-size-budget-reminder.ts`   | iter-93                      | CLAUDE.md character-budget reminder (see #1)  | [→](./docs/posttooluse-write-edit-orchestrator.md) |

### Stop

| Hook                         | Purpose                                            | Spoke                          |
| ---------------------------- | -------------------------------------------------- | ------------------------------ |
| `stop-hook-error-summary.ts` | Summarizes session hook errors on Claude exit      | [→](./docs/stop-hooks.md)      |
| `stop-ty-project-check.ts`   | Project-wide ty check on exit (only if .py edited) | [→](./docs/ty-type-checker.md) |

## Escape hatches

Add the token to the file or command to suppress a guard. Every token requires a real reason; several demand one inline.

| Token                      | Suppresses                                   |
| -------------------------- | -------------------------------------------- |
| `SECRET-SCAN-OK: <reason>` | Secret-exposure guard (reason ≥10 chars)     |
| `PII-SCAN-OK`              | PII-exposure reminder                        |
| `SKILL-PLUGIN-ROOT-OK`     | Skill plugin-root guard                      |
| `RELEASE-NOTES-OK`         | Release-notes extensiveness guard            |
| `GMAIL-BODY-OK`            | Gmail draft body guard                       |
| `ASK-OPTION-NEWLINE-OK`    | AskUserQuestion option line-terminator guard |
| `HEADLESS-P-OK`            | Headless `claude -p` guard                   |
| `MD-TABLE-OK`              | Markdown table guard                         |
| `MD-HARD-WRAP-OK`          | Markdown hard-wrap reminder                  |
| `INVENTED-FALLBACK-OK`     | Invented-fallback reminder                   |
| `MINI-INNGEST-OK`          | Mini-Inngest doctrine nudge                  |
| `CLAUDE-MD-SIZE-OK`        | CLAUDE.md size-budget reminder               |
| `ALLOW_BARE_BRANCH=1`      | Git worktree guard (env var, not a marker)   |

`pretooluse-webfetch-fallback-guard.ts` has **no** escape hatch, by design.

## Environment variables (hook context)

Set by Claude Code when a hook fires — hooks read them, users do not set them.

| Variable                 | Description                                                         |
| ------------------------ | ------------------------------------------------------------------- |
| `CLAUDE_SESSION_ID`      | Session UUID; per-session gate files and session-scoped caches      |
| `CLAUDE_CONVERSATION_ID` | Conversation UUID (alias surfaced by some hook events)              |
| `CLAUDE_PROJECT_DIR`     | Project root Claude is working in; resolves `.claude/` config       |
| `CLAUDE_HOOK_SPAWNED`    | `1` when running via a wrapper; guards against recursive invocation |

## Skills

- [hooks-development](./skills/hooks-development/SKILL.md)
- [setup](./skills/setup/SKILL.md)

## References

- [docs/spoke-index.md](./docs/spoke-index.md) — annotated index of all spokes in [`docs/`](./docs/)
- [lifecycle-reference.md](skills/hooks-development/references/lifecycle-reference.md) — hook lifecycle and best practices
- [bootstrap-monorepo.md](../itp/skills/mise-tasks/references/bootstrap-monorepo.md) — monorepo scaffolding patterns
