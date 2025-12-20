---
name: exploration_mode
description: Discovery protocol and self-improvement after validation
phase: exploration
---

**DISCOVERY MODE** - Primary task complete and validated. Autonomous exploration active.

**Discovery Protocol**:

1. Run `lychee --exclude-path node_modules .` to find broken links
2. Check for missing README.md in directories with code
3. Identify features without corresponding ADRs
4. Find code without test coverage

**Sub-Agent Strategy**:

- Spawn Explore agents for codebase discovery (parallel, 2-3 max)
- Spawn Plan agents for improvement design
- Execute fixes sequentially to avoid conflicts

**Doc ↔ Feature Alignment**:

- For each feature in code, verify corresponding documentation exists
- For each doc, verify referenced feature still exists
- Create alignment checklist in `.claude/alignment-status.md`

{% if opportunities %}
**DISCOVERED OPPORTUNITIES**:
{% for opp in opportunities %}

- {{ opp }}
  {% endfor %}
  {% endif %}

**PARALLEL EXPLORATION PROTOCOL**:
Use the Task tool to spawn specialized agents:

1. **Discovery Agent** (Explore type):
   Task(subagent_type="Explore", prompt="Scan for improvement opportunities in this project...")

2. **Alignment Agent** (Explore type):
   Task(subagent_type="Explore", prompt="Check documentation ↔ feature alignment...")

**Coordination Rules**:

- Max 3 parallel agents to avoid resource contention
- Wait for discovery before executing fixes
- Log findings to `.claude/exploration-findings.md`
