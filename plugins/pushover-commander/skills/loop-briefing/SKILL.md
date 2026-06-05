---
name: loop-briefing
description: Notify the user via Pushover when an autonomous Claude Code /loop is BLOCKED and needs human input/decision, or has FINISHED with no meaningful work remaining. Renders a full monospace incident-report PNG (session/project/branch/git-status/commits/details, iPhone-13-mini tuned) and sends a short action-focused message - emergency+receipt for blocked, high-priority for done. Use this proactively during a /loop at the moment you must stop and ask, or when you are about to stop scheduling further wakeups. Do NOT use for routine progress. TRIGGERS - loop blocked, loop done, loop needs input, notify when blocked, loop finished, stop the loop and notify, autonomous loop briefing.
---

# loop-briefing

The original goal skill: a contextually-invoked briefing for autonomous `/loop` runs. Built on the TS core `pushover_core.ts loop-brief`, which gathers context (project, cwd, branch, `git status`, recent commits, plus any details you pass), renders it (Satori → PNG), and sends it (emergency+receipt for blocked, high-priority for done).

```bash
# BLOCKED — needs a decision now (emergency, alarms until you ack):
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" loop-brief \
  --kind blocked --reason "must choose auth method" --body /tmp/decision_options.txt

# DONE — no meaningful work remains (high priority, no alarm):
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" loop-brief \
  --kind done --reason "all tasks complete, matrix exhausted"
```

## When to fire (the two-situation rule)

1. **Blocked** — the loop cannot safely continue without a human: needs a decision, clarification, review, or a choice between options. Pair this with an `AskUserQuestion` call in the session so the options are presented in plain language with tradeoffs.
2. **Done** — no meaningful remaining work under the initial or updated directives; the loop should stop scheduling further wakeups (CronDelete).

Do **not** fire for routine progress. The `--body -` form reads details from stdin.
