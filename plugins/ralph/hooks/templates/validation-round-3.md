---
name: validation_round_3
description: Consistency audit with parallel sub-agents (doc-code, coverage)
phase: validation
round: 3
---

## AUTONOMOUS MODE

**CRITICAL**: You are running in AUTONOMOUS LOOP MODE.

- DO NOT use AskUserQuestion
- DO NOT ask "what should I work on next?"
- DO NOT call /ralph:stop
- DO NOT stop the session on your own
- Make decisions autonomously and proceed to exploration phase

---

**VALIDATION ROUND 3** - Consistency Audit (Parallel)

Spawn in parallel:

1. **Doc-Code Agent** (Explore type):
   Task(subagent_type="Explore", prompt="Check if all code changes have corresponding documentation updates. Output JSON: {'findings': [{'severity': 'medium', 'file': '...', 'message': 'Missing doc for...'}], 'doc_issues': [...]}", model="haiku")

2. **Coverage Agent** (Explore type):
   Task(subagent_type="Explore", prompt="Identify changed files without test coverage. Output JSON: {'findings': [...], 'coverage_gaps': ['file1.py', 'file2.py']}", model="haiku")

Timeout per agent: {{ timeout }}s

After both complete, compute validation score:

- 0 Critical = 0.5 base
- 0 Medium = +0.3
- All docs aligned = +0.1
- Coverage gaps ≤2 = +0.1
- Score >= 0.8 = VALIDATION COMPLETE → proceed to EXPLORATION

---

## AFTER ROUND 3 COMPLETES

1. Calculate validation score based on findings
2. If score >= 0.8, validation is COMPLETE - proceed to EXPLORATION phase
3. If score < 0.8, the loop will continue improving until thresholds are met
4. **DO NOT stop** - the loop will automatically transition to exploration phase
