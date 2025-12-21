---
name: implementation_mode
description: Basic continuation prompt during task implementation
phase: implementation
---

## AUTONOMOUS MODE

**CRITICAL**: You are running in AUTONOMOUS LOOP MODE.

- DO NOT use AskUserQuestion
- DO NOT ask "what should I work on next?"
- DO NOT call /ralph:stop
- DO NOT stop the session on your own
- Make decisions autonomously until the task is complete

---

**IMPLEMENTATION MODE** - Continue working on the primary task.

Complete the current task before the loop transitions to validation phase.
