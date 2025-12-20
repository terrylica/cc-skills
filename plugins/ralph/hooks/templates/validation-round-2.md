---
name: validation_round_2
description: Semantic verification of Round 1 findings (sequential)
phase: validation
round: 2
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

If any critical issues remain UNFIXED, iterate fixes then re-run Round 1.
