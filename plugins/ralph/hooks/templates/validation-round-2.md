---
name: validation_round_2
description: Semantic verification of Round 1 findings (sequential)
phase: validation
round: 2
---

## AUTONOMOUS MODE

**CRITICAL**: You are running in AUTONOMOUS LOOP MODE.

- DO NOT use AskUserQuestion
- DO NOT ask "what should I work on next?"
- DO NOT call /ralph:stop
- DO NOT stop the session on your own
- Make decisions autonomously and proceed to the next round

---

**VALIDATION ROUND 2** - Semantic Verification (Sequential)

Round 1 found: {{ critical_count }} critical, {{ medium_count }} medium issues.

Spawn verification agent:

Task(subagent_type="Plan", prompt="Review these Round 1 findings and verify: 1) Were issues fixed? 2) Any regressions introduced? 3) Cross-reference against original task requirements.

Critical issues to verify:
{{ critical_issues }}

Medium issues to verify:
{{ medium_issues }}

Output JSON: {'verified': [...], 'failed': [...], 'success': true}", model="sonnet")

---

## AFTER ROUND 2 COMPLETES

1. If critical issues remain UNFIXED, fix them autonomously (do NOT ask user)
2. After fixes, re-run Round 1 agents to verify
3. Once verified, the loop will automatically advance to Round 3
4. **DO NOT stop** - the validation phase requires completing all 3 rounds
