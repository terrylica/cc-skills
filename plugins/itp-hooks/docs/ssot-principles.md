# SSoT/Dependency Injection Principles Hook

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`posttooluse-ssot-principles.ts`](../hooks/posttooluse-ssot-principles.ts), subhook `ssot-principles` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) (orchestrator timeout 3000 ms).

The hook reminds Claude of SSoT/DI best practices, once per session, on the first code edit in which ast-grep finds an anti-pattern, and lists the findings under the principles. A file that scans clean gets nothing: until 2026-11-15 the card fired on the first code file of the session even with no finding, including a clean Cloudflare Worker redirect (operator report).

## How It Works

1. Triggers on Write/Edit of code files in the languages the rules cover: `.py`, `.ts`, `.mts`, `.cts`, `.rs`, `.go` (ast-grep's `typescript` language does not cover `.tsx`, `.js` or `.jsx`; add an extension only together with rules that can match it)
2. Skips test files (paths matching `/test_`, `/tests/`, `_test.`, `_spec.`, `.test.`, `.spec.`, `/conftest.py`, `/__tests__/`) and throwaway files in temp directories
3. Skips the whole check when the new content contains an `SSoT-OK` comment
4. Runs ast-grep with the rules in `hooks/ast-grep-ssot/` against the edited file on disk (about 10 ms) and drops findings on a line marked `SSoT-OK`
5. Stops when nothing is left: no card, and the session's gate stays unclaimed for the first file with a real finding
6. Gates once per session via an atomic `O_EXCL` gate file at `/tmp/.claude-ssot-principles-reminder-<uid>/<session-id>.reminded` (shared helper `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`)
7. Outputs the SSoT principles plus the detected anti-patterns as additional context, truncated below Claude Code's 10,000-character hook-output limit

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

The classifier is `classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator`, exported to the orchestrator under the alias `classifySsotPrinciplesForPostToolUseOrchestrator`. The file also runs standalone through its `import.meta.main` guard. Tests: `hooks/posttooluse-ssot-principles.test.ts`.

## GitHub Issue

[#28](https://github.com/terrylica/cc-skills/issues/28)
