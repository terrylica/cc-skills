---
name: validation_round_1
description: Static analysis with parallel sub-agents (linting, links, secrets)
phase: validation
round: 1
---

## AUTONOMOUS MODE

**CRITICAL**: You are running in AUTONOMOUS LOOP MODE.

- DO NOT use AskUserQuestion
- DO NOT ask "what should I work on next?"
- DO NOT call /ralph:stop
- DO NOT stop the session on your own
- Make decisions autonomously and proceed to the next round

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

---

## AFTER ROUND 1 COMPLETES

1. Wait for all 3 agents to complete
2. Fix any CRITICAL issues found (do NOT ask user - fix autonomously)
3. The loop will automatically advance to Round 2
4. **DO NOT stop** - the validation phase requires completing all 3 rounds
