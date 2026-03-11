---
name: code-hardcode-audit
description: Detect hardcoded values, magic numbers, and leaked secrets. TRIGGERS - hardcode audit, magic numbers, PLR2004, secret scanning.
allowed-tools: Bash, Read, Write, Glob, Grep
---

# Code Hardcode Audit

## When to Use This Skill

Use this skill when the user mentions:

- "hardcoded values", "hardcodes", "magic numbers"
- "constant detection", "find constants"
- "duplicate constants", "DRY violations"
- "code audit", "hardcode audit"
- "PLR2004", "semgrep", "jscpd", "gitleaks", "ast-grep", "SSoT violations"
- "secret scanning", "leaked secrets", "API keys"
- "passwords in code", "credential leaks"

## Quick Start

```bash
# Preflight — verify all tools installed and configured
uv run --python 3.13 --script scripts/preflight.py -- .

# Full audit (all 6 tools, preflight + both outputs)
uv run --python 3.13 --script scripts/audit_hardcodes.py -- src/

# SSoT pattern detection (ast-grep, fastest — 6ms/file)
cd plugins/itp-hooks/hooks/ast-grep-ssot && ast-grep scan src/

# AST-based hardcode detection (ast-grep with audit-specific rules)
uv run --python 3.13 --script scripts/run_ast_grep.py -- src/

# Python magic numbers only (fastest)
uv run --python 3.13 --script scripts/run_ruff_plr.py -- src/

# Pattern-based detection (URLs, ports, paths, sleep, circuit breaker)
uv run --python 3.13 --script scripts/run_semgrep.py -- src/

# Env-var coverage audit (BaseSettings cross-reference)
uv run --python 3.13 --script scripts/audit_env_coverage.py -- src/

# Copy-paste detection
uv run --python 3.13 --script scripts/run_jscpd.py -- src/

# Secret scanning (API keys, tokens, passwords)
uv run --python 3.13 --script scripts/run_gitleaks.py -- src/
```

## Tool Overview

| Tool             | Detection Focus                                | Language Support | Speed   |
| ---------------- | ---------------------------------------------- | ---------------- | ------- |
| **Preflight**    | Tool availability + config validation          | N/A              | Instant |
| **ast-grep**     | Hardcoded literals in args, sleep, URLs, paths | Multi-language   | Fast    |
| **Ruff PLR2004** | Magic value comparisons                        | Python           | Fast    |
| **Semgrep**      | URLs, ports, paths, credentials, retry config  | Multi-language   | Medium  |
| **Env-coverage** | BaseSettings cross-reference, coverage gaps    | Python           | Fast    |
| **jscpd**        | Duplicate code blocks                          | Multi-language   | Slow    |
| **gitleaks**     | Secrets, API keys, passwords                   | Any (file-based) | Fast    |

## Output Formats

### JSON (--output json)

```json
{
  "summary": {
    "total_findings": 42,
    "by_tool": { "ruff": 15, "semgrep": 20, "jscpd": 7 },
    "by_severity": { "high": 5, "medium": 25, "low": 12 }
  },
  "findings": [
    {
      "id": "MAGIC-001",
      "tool": "ruff",
      "rule": "PLR2004",
      "file": "src/config.py",
      "line": 42,
      "column": 8,
      "message": "Magic value used in comparison: 8123",
      "severity": "medium",
      "suggested_fix": "Extract to named constant"
    }
  ],
  "refactoring_plan": [
    {
      "priority": 1,
      "action": "Create constants/ports.py",
      "finding_ids": ["MAGIC-001", "MAGIC-003"]
    }
  ]
}
```

### Compiler-like Text (--output text)

```
src/config.py:42:8: PLR2004 Magic value used in comparison: 8123 [ruff]
src/probe.py:15:1: hardcoded-url Hardcoded URL detected [semgrep]
src/client.py:20-35: Clone detected (16 lines, 95% similarity) [jscpd]

Summary: 42 findings (ruff: 15, semgrep: 20, jscpd: 7)
```

## CLI Options

```
--output {json,text,both}  Output format (default: both)
--tools {all,ast-grep,ruff,semgrep,jscpd,gitleaks,env-coverage}  Tools to run
--severity {all,high,medium,low}  Filter by severity (default: all)
--exclude PATTERN  Glob pattern to exclude (repeatable)
--no-parallel  Disable parallel execution
--skip-preflight  Skip tool availability check
```

## References

- [Tool Comparison](./references/tool-comparison.md) - Detailed tool capabilities
- [Output Schema](./references/output-schema.md) - JSON schema specification
- [Troubleshooting](./references/troubleshooting.md) - Common issues and fixes

## Related

- ADR-0046: Semantic Constants Abstraction
- ADR-0047: Code Hardcode Audit Skill
- `code-clone-assistant` - PMD CPD-based clone detection (DRY focus)

---

## Troubleshooting

| Issue                    | Cause                       | Solution                                                                 |
| ------------------------ | --------------------------- | ------------------------------------------------------------------------ |
| Ruff PLR2004 zero output | PLR2004 globally suppressed | Run preflight: `uv run --python 3.13 --script scripts/preflight.py -- .` |
| Ruff PLR2004 not found   | Ruff not installed or old   | `uv tool install ruff` or upgrade                                        |
| ast-grep not found       | Binary not installed        | `cargo install ast-grep` or `brew install ast-grep`                      |
| Semgrep timeout          | Large codebase scan         | Use `--exclude` to limit scope                                           |
| jscpd memory error       | Too many files              | Increase Node heap: `NODE_OPTIONS=--max-old-space-size=4096`             |
| gitleaks false positives | Test data flagged           | Add patterns to `.gitleaks.toml` allowlist                               |
| Env-coverage misses      | Not using BaseSettings      | Only detects pydantic BaseSettings; other config patterns skipped        |
| No findings in output    | Wrong directory specified   | Verify path exists and contains source files                             |
| JSON parse error         | Tool output malformed       | Run tool individually with `--output text`                               |
| Missing tool in PATH     | Tool not installed globally | Run preflight first, then install missing tools                          |
| Severity filter empty    | No findings at that level   | Use `--severity all` to see all findings                                 |
