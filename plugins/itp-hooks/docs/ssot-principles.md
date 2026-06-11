# SSoT/Dependency Injection Principles Hook

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## SSoT/Dependency Injection Principles Hook

The `posttooluse-ssot-principles.ts` hook reminds Claude of SSoT/DI best practices on the first code edit per session, with ast-grep AST-based detection of anti-patterns.

### How It Works

1. Triggers on Write/Edit of code files (`.py`, `.ts`, `.rs`, `.go`, `.java`, `.kt`, `.rb`)
2. Skips test files (`test_*`, `*_test.*`, `*_spec.*`, `__tests__/`)
3. Gates once per session via atomic file in `/tmp/.claude-ssot-reminder/`
4. Runs ast-grep with rules from `hooks/ast-grep-ssot/` for AST-based detection
5. Outputs SSoT principles + any detected anti-patterns

### ast-grep Rules (9 rules, 4 languages)

| Language   | Rules | Detections                                                        |
| ---------- | ----- | ----------------------------------------------------------------- |
| Python     | 3     | Hardcoded string/int defaults, direct `os.environ`/`os.getenv`    |
| TypeScript | 2     | Hardcoded string defaults, direct `process.env` access            |
| Rust       | 2     | Direct `env::var`, hardcoded `unwrap_or` fallbacks                |
| Go         | 2     | Direct `os.Getenv`/`os.LookupEnv`, hardcoded `flag.*Var` defaults |

Rules location: `hooks/ast-grep-ssot/rules/` | Test: `cd hooks/ast-grep-ssot && ast-grep test`

### Escape Hatch

Add `# SSoT-OK` (or `// SSoT-OK`) comment to suppress findings. Same convention as `pretooluse-version-guard.ts`.

### GitHub Issue

[#28](https://github.com/terrylica/cc-skills/issues/28)


## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: (inlined in iter-97 orchestrator)

SSoT/DI principles reminder with ast-grep anti-pattern detection (once per session) on .py/.ts/.tsx/.js/.jsx/.rs/.go/.java/.kt/.rb edits (test files excluded). **Iter-97 SIXTH inlined PostToolUse subhook (6/15 in arc) and FIRST migration that creates REAL Promise.all parallel fan-out**. **Iter-98 uplift**: gate-file claim logic delegated to the new shared lib helper `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName` (parallel to iter-95's async-spawn helper hoist — DRY-out across iter-97 ssot-principles and iter-98 memory-efficiency-reminder). Algorithm encoded in `classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator`; alias `classifySsotPrinciplesForPostToolUseOrchestrator`. Standalone hook still runnable via `import.meta.main` guard.
