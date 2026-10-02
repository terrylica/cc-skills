# SSoT/Dependency Injection Principles Hook

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`posttooluse-ssot-principles.ts`](../hooks/posttooluse-ssot-principles.ts), subhook `ssot-principles` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 3000 ms).

The hook reminds Claude of SSoT/DI best practices on the first code edit per session, with ast-grep AST-based detection of anti-patterns in the edited file.

## How It Works

1. Triggers on Write/Edit of code files (`.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.rs`, `.go`, `.java`, `.kt`, `.rb`)
2. Skips test files (paths matching `/test_`, `/tests/`, `_test.`, `_spec.`, `.test.`, `.spec.`, `/conftest.py`, `/__tests__/`) and throwaway files in temp directories
3. Skips the whole check when the new content contains an `SSoT-OK` comment
4. Gates once per session via an atomic `O_EXCL` gate file at `/tmp/.claude-ssot-principles-reminder/<session-id>.reminded` (shared helper `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`)
5. Runs ast-grep with the rules in `hooks/ast-grep-ssot/` against the edited file on disk
6. Outputs the SSoT principles plus any detected anti-patterns as additional context, truncated below Claude Code's 10,000-character hook-output limit

## ast-grep Rules (9 rules, 4 languages)

| Language   | Rules | Detections                                                        |
| ---------- | ----- | ----------------------------------------------------------------- |
| Python     | 3     | Hardcoded string/int defaults, direct `os.environ`/`os.getenv`    |
| TypeScript | 2     | Hardcoded string defaults, direct `process.env` access            |
| Rust       | 2     | Direct `env::var`, hardcoded `unwrap_or` fallbacks                |
| Go         | 2     | Direct `os.Getenv`/`os.LookupEnv`, hardcoded `flag.*Var` defaults |

Rules location: `hooks/ast-grep-ssot/rules/` | Test: `cd hooks/ast-grep-ssot && ast-grep test`

## Escape Hatch

Add a `# SSoT-OK` (or `// SSoT-OK`) comment. Anywhere in the new content it suppresses the check for that edit; on a single flagged line it drops just that finding. Same convention as `pretooluse-version-guard.ts`.

## Code

The classifier is `classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifySsotPrinciplesForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard.

## GitHub Issue

[#28](https://github.com/terrylica/cc-skills/issues/28)
