---
name: session-debrief
description: Analyze Claude Code sessions in three expert modes — Handoff Document (exhaustive context extraction for the next developer or session), Error Forensics (complete inventory of warnings and errors Claude ignored or deferred), and Chronological Summary (dense technical timeline with key outcomes). Use when the user wants a session handoff, asks what happened, wants to know what errors were missed or ignored, requests a retrospective or debrief, mentions session history or session analysis, or wants to understand past work in the current repo. Do not use for live debugging or code review.
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, Agent
---

## Execution Model — MANDATORY

**You MUST use AskUserQuestion TWICE before spawning an Agent.** Ask for the goal first, then the time range. Then spawn the Agent with resolved parameters.

---

## Step 1 — Ask Which Goal

Use `AskUserQuestion` to present exactly these three choices:

> **Which analysis mode?**
>
> 1. **Handoff Document** — Exhaustive context for the next developer or Claude session continuing this work. Extracts every decision, file, command, gotcha, incomplete item, and next step. Multiple MiniMax chunks if needed for full coverage.
> 2. **Error Forensics** — Complete inventory of every warning, error, deprecation, failed command, and anomaly that occurred — especially ones Claude acknowledged but ignored or deferred. Full verbatim detail with file paths and commands.
> 3. **Chronological Summary** — Dense technical timeline of everything that happened: every decision, change, problem, discovery, and outcome in turn order. As concise as possible while capturing maximum events.

---

## Step 2 — Ask Time Range

Use `AskUserQuestion` to ask:

> **How far back should sessions be included?**
>
> - **48 hours** (default — last 2 days)
> - **1 week** (168 hours)
> - **1 month** (720 hours)
> - **Custom** — enter any natural language like "3 days", "2 weeks", "5 hours", "since Monday"

Convert their answer to hours for `--since <N>`:

- "3 days" → `72`
- "2 weeks" → `336`
- "5 hours" → `5`
- "since Monday" → calculate hours from now to last Monday

---

## Step 3 — Spawn Agent

```
Agent(
  description: "Session analysis - Goal <N>: <name>",
  prompt: "Run session analysis for the current project. Execute:

    bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \\
      --goal <1|2|3> \\
      --since <hours> \\
      --verbose

  Print all output exactly as-is. Do not filter or summarize.
  If the command fails, show the full error and suggest troubleshooting.",
  run_in_background: true
)
```

**Do NOT add `--shots` — it only applies to legacy 50-perspectives mode.**

When the Agent returns, present the output directly to the user with no additional summarization — the MiniMax output IS the result.

---

# Session Blind Spots — Reference

## The Three Goals

### Goal 1: Handoff Document

The most comprehensive output mode. Extracts everything the next developer or AI session needs to continue work without asking questions.

Output structure:

- **WHAT WAS ACCOMPLISHED** — every completed task, file, command (exhaustive)
- **CURRENT STATE** — what works right now, what was modified
- **INCOMPLETE / BROKEN** — unfinished items, unresolved errors, deferred work
- **KEY DECISIONS & RATIONALE** — why things were done this way
- **CRITICAL GOTCHAS & CONTEXT** — non-obvious facts, workarounds, landmines
- **NEXT STEPS (PRIORITY ORDER)** — concrete actions to start next session with

If the session history spans more than MiniMax's context window (~260K tokens), the script automatically chunks by session and produces multiple parts.

### Goal 2: Error Forensics

Every warning, error, and anomaly — especially the ones Claude moved past.

Each finding includes:

- Exact turn number
- Trigger (command/tool that caused it)
- File/path involved
- Complete verbatim error text (not paraphrased)
- Resolution status: UNRESOLVED / PARTIAL / RESOLVED
- What Claude did (acknowledged? ignored? deferred?)

### Goal 3: Chronological Summary

Dense technical timeline: one bullet per significant event, in turn order.

- Groups into phases when clear phases emerge
- Marks unresolved errors with ⚠
- Captures decisions + rationale
- Ends with **Key Outcomes** (3-7 most important results)

---

## How Sessions Are Discovered

The script automatically finds all sessions for the **current project** (derived from the working directory) modified within the time window:

1. Scans `~/.claude/projects/<project-key>/` for `.jsonl` files
2. Includes files modified within the `--since` window
3. For each session, follows parent chains (continuation sessions) for full context
4. Sorts chronologically (oldest first) for coherent narrative

The project key is the absolute path with `/` replaced by `-`. For example:
`/Users/terryli/eon/cc-skills` → `-Users-terryli-eon-cc-skills`

---

## Script Invocation Reference

```bash
# Focused goal mode — recommended
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \
  --goal 1 --since 48         # Handoff: last 48 hours
  --goal 2 --since 168        # Error forensics: last week
  --goal 3 --since 720        # Summary: last month

# Debug: show extracted payload without calling MiniMax
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \
  --goal 1 --since 48 --dry --verbose

# Override project dir (if auto-detection fails)
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \
  --goal 2 --since 48 --project-dir ~/.claude/projects/-Users-foo-myrepo

# Skip parent chain tracing (faster, current window only)
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \
  --goal 3 --since 48 --no-chain

# Legacy 50-perspectives mode (single session UUID)
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-debrief.ts \
  <session-uuid>
```

---

## Configuration

| Setting             | Source                                                           | Default                   |
| ------------------- | ---------------------------------------------------------------- | ------------------------- |
| MiniMax API key     | `~/.claude/.secrets/ccterrybot-telegram` (`MINIMAX_API_KEY=...`) | Required                  |
| Model               | Hardcoded                                                        | `MiniMax-M2.5-highspeed`  |
| Max output tokens   | Hardcoded                                                        | 16384 per call            |
| Context budget      | Hardcoded                                                        | 890K chars (~243K tokens) |
| Default time window | `--since`                                                        | 48 hours                  |
| Session chaining    | `--no-chain` to disable                                          | Enabled                   |

---

## Find Recent Sessions (Manual)

```bash
# Sessions for current project (key = cwd with / replaced by -)
ls -lt ~/.claude/projects/$(pwd | tr '/' '-')/*.jsonl 2>/dev/null | head -10

# All projects, most recent first
ls -lt ~/.claude/projects/*/*.jsonl 2>/dev/null | head -20
```

---

## Troubleshooting

| Issue                          | Cause                           | Fix                                                    |
| ------------------------------ | ------------------------------- | ------------------------------------------------------ |
| `Cannot determine project dir` | CWD not a known project         | Use `--project-dir ~/.claude/projects/<key>`           |
| `No sessions found`            | No sessions in time window      | Increase `--since` (e.g., `--since 336` for 2 weeks)   |
| `MINIMAX_API_KEY not found`    | Missing secrets file            | Check `~/.claude/.secrets/ccterrybot-telegram`         |
| `context window exceeds`       | Single session too large        | Use `--dry --verbose` to check size; try `--no-chain`  |
| Goal 1 produces multiple parts | Sessions exceeded single budget | Expected behavior — multiple chunks = maximum coverage |
