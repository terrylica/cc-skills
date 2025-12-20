---
name: validation_round_1
description: Static analysis with parallel sub-agents (linting, links, secrets)
phase: validation
round: 1
---

**VALIDATION ROUND 1** - Static Analysis (Parallel)

Spawn the following sub-agents IN PARALLEL using Task tool:

1. **Linter Agent** (Explore type, quick thoroughness):
   Task(subagent_type="Explore", prompt="Run ruff check on all Python files in this project. Output JSON with findings array containing severity, file, line, code, message for each issue. Focus on: BLE, S110, E722, UP, SIM, B rules.", model="haiku")

2. **Link Validator** (Explore type, quick thoroughness):
   Task(subagent_type="Explore", prompt="Run lychee on markdown files OR manually check links. Output JSON with findings array for broken links.", model="haiku")

3. **Secret Scanner** (Explore type, quick thoroughness):
   Task(subagent_type="Explore", prompt="Check for hardcoded secrets, API keys, tokens in code. Output JSON with findings array.", model="haiku")

**Output format** (each agent):

```json
{"findings": [{"severity": "critical|medium|low", "file": "path", "line": N, "code": "CODE", "message": "..."}], "tool_used": "ruff|lychee|gitleaks|claude-analysis", "success": true}
```

Timeout per agent: {{ timeout }}s
Wait for all 3 to complete before proceeding to Round 2.
