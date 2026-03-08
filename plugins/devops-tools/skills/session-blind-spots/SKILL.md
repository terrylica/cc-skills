---
name: session-blind-spots
description: Diverse-perspective consensus blind spot analysis of Claude Code sessions via MiniMax 2.5 highspeed. Runs 50 parallel reviews from orthogonal specialist lenses, then distills into confidence-ranked findings. Recursive parent tracing + sibling discovery for maximum lookback within budget. TRIGGERS - blind spots, session review, what did I miss, session debrief, retrospective, missed issues, session analysis.
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, Agent
---

## Execution Model — MANDATORY

**You MUST use the Agent tool to execute this skill.** Do NOT run the analysis in the main conversation — spawn a `general-purpose` Agent instead. This keeps the main context clean (the script runs ~60s with 50 parallel MiniMax calls and produces large output).

### How to invoke

1. If the user didn't provide a session UUID, find the most recent session first (see "Find Recent Sessions" below), then ask the user which session to analyze.
2. Spawn an Agent with the full instructions from this skill and the resolved session UUID. The agent prompt should include: the bun command to run, the `--shots` flag only if the user explicitly requested fewer, and instructions to present the output as-is.
3. When the Agent returns, present a concise summary of findings to the user — CRITICAL and WARNING items first, then the Priority Action Plan.

Example Agent invocation:

```
Agent(
  description: "Session blind spot analysis",
  prompt: "Run session blind spot analysis for session <UUID>. Execute: bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts <UUID> ... [full command with flags]. Present the output directly — do not summarize or filter. If the command fails, show the error and suggest troubleshooting steps.",
  run_in_background: true
)
```

---

# Session Blind Spots

Send a Claude Code session transcript to MiniMax 2.5 highspeed for independent diverse-perspective consensus review. Each shot uses a distinct specialist reviewer lens (not copies of the same prompt). A distillation pass merges, deduplicates, and ranks findings by how many perspectives independently surfaced each issue.

## How It Works

1. **Recursive chain tracing** — Follows `parentSessionId` and continuation references recursively (up to 10 levels deep: parent → grandparent → …)
2. **Sibling discovery** — Finds sessions in the same project directory modified within 24h of the primary session
3. **Budget-aware inclusion** — When the full chain exceeds the 890K char budget, drops oldest ancestors first (not middle-trim), preserving the most recent and relevant context
4. **Rich extraction** — Turns with user/assistant text, tool calls, file paths touched, errors encountered
5. **Noise stripping** — Removes system reminders, skill listings, base64 data, deferred tool blocks
6. **Adaptive fidelity** — 5 progressive truncation levels to maximize signal within MiniMax's context budget
7. **Diverse perspectives** — Fires N parallel MiniMax calls, each with a unique specialist reviewer lens
8. **Consensus distillation** — Feeds all N results into a final MiniMax call that merges, deduplicates, and ranks by cross-perspective agreement

## 50 Specialist Perspectives

Each perspective is an orthogonal reviewer lens that focuses on one specific class of issues:

| #   | Perspective                      | Focus                                                  |
| --- | -------------------------------- | ------------------------------------------------------ |
| 1   | Completeness Tracker             | Unfulfilled user requests, abandoned tasks             |
| 2   | Security Auditor                 | Credentials exposure, injection vectors, permissions   |
| 3   | Verification Engineer            | Changes never tested or validated                      |
| 4   | Side-Effect Hunter               | Orphaned processes, dirty git state, leaked files      |
| 5   | Architecture Critic              | Over/under-engineering, wrong abstractions             |
| 6   | Error Flow Analyst               | Silent failures, missing error handling, race conds    |
| 7   | User Intent Decoder              | Misunderstandings, missed implicit expectations        |
| 8   | Regression Hunter                | Fixes that broke other things, changed contracts       |
| 9   | Process Auditor                  | Wrong branch, skipped commits, bypassed hooks          |
| 10  | Documentation Staleness Detector | Stale docs, outdated examples, wrong references        |
| 11  | Concurrency & Timing Analyst     | Race conditions, lock issues, timing bugs              |
| 12  | Dependency Chain Auditor         | Missing imports, circular deps, unpinned versions      |
| 13  | Performance & Resource Analyst   | Memory leaks, O(n²), unbounded growth                  |
| 14  | Cross-System Impact Analyst      | Ripple effects to other services/configs               |
| 15  | Idempotency Checker              | Operations unsafe to run twice                         |
| 16  | Configuration Drift Detector     | SSoT violations, duplicated settings                   |
| 17  | Rollback Feasibility Analyst     | Irreversible operations without backup                 |
| 18  | Platform Portability Reviewer    | macOS-only assumptions, hardcoded paths                |
| 19  | Technical Debt Accountant        | Quick fixes, copy-paste, untracked TODOs               |
| 20  | Data Integrity Analyst           | Data loss, truncation, encoding corruption             |
| 21  | API Contract Reviewer            | Breaking changes, missing versioning, schema drift     |
| 22  | Observability Gap Detector       | Missing logging, metrics, alerting, tracing            |
| 23  | Failure Mode Analyst             | Graceful degradation, circuit breakers, resilience     |
| 24  | Input Validation Sentinel        | Missing boundary validation, injection vectors         |
| 25  | Resource Cleanup Inspector       | Unclosed handles, leaked listeners, orphaned temps     |
| 26  | Naming & Semantics Reviewer      | Misleading names, inconsistent terminology             |
| 27  | Permission & Scope Auditor       | Over-permissioned tokens, broad file access            |
| 28  | Caching Correctness Analyst      | Stale caches, invalidation bugs, key collisions        |
| 29  | Test Coverage Gap Finder         | Untested code paths, missing edge case tests           |
| 30  | Logging Hygiene Auditor          | PII in logs, missing context, log level misuse         |
| 31  | Encoding & Serialization Analyst | UTF-8 issues, JSON edge cases, date serialization      |
| 32  | Rate Limit & Quota Tracker       | API rate limits, quota exhaustion, backpressure        |
| 33  | Authentication Flow Auditor      | Token refresh, session expiry, auth state lifecycle    |
| 34  | Network Resilience Analyst       | Timeout handling, DNS failures, connection pooling     |
| 35  | Git History Hygiene Auditor      | Large files, secrets in history, messy commits         |
| 36  | Boundary Condition Analyst       | Off-by-one, empty arrays, zero, NaN, max values        |
| 37  | Async Lifecycle Manager          | Unresolved promises, fire-and-forget, event leaks      |
| 38  | Environment Assumptions Detector | Missing tool checks, hardcoded paths, locale issues    |
| 39  | Cost & Billing Analyst           | Expensive API calls, wasted compute, unbounded spend   |
| 40  | Semantic Versioning Compliance   | Breaking changes without major bump, changelog gaps    |
| 41  | State Machine Validator          | Invalid transitions, missing states, state corruption  |
| 42  | Deprecation Tracker              | Deprecated APIs, unmaintained packages, old patterns   |
| 43  | Filesystem Safety Reviewer       | rm -rf risks, disk space, symlink attacks              |
| 44  | Migration Safety Reviewer        | Schema changes, format changes, backward compat        |
| 45  | Internationalization Blind Spot  | Locale assumptions, hardcoded strings, CJK handling    |
| 46  | License & Compliance Auditor     | GPL mixing, ToS violations, missing LICENSE files      |
| 47  | Signal & Shutdown Handler        | SIGTERM handling, graceful shutdown, cleanup on exit   |
| 48  | Secrets Rotation Analyst         | Expiry, rotation schedule, revocation, scope audit     |
| 49  | UX Consistency Reviewer          | CLI flag naming, error formats, progress indicators    |
| 50  | Dependency Freshness Auditor     | Outdated packages, abandoned libs, security advisories |

Default: all 50 perspectives. Use `--shots N` to limit (e.g., `--shots 5` for quick scan).

## Why Diverse Perspectives?

Same prompt N times is near-deterministic — different perspectives are orthogonal by design:

- **Higher recall** — Security Auditor catches credentials; Verification Engineer catches untested changes
- **Lower false positives** — Findings seen from 2+ perspectives are more credible
- **Confidence ranking** — "Seen by 5/10 perspectives" is near-certain; "1/10" is speculative
- **Cheap** — MiniMax is fast and inexpensive; 50 parallel perspectives complete in ~60s

## Usage

**IMPORTANT: Do NOT pass `--shots` unless the user explicitly requests fewer perspectives. The script defaults to all 50 perspectives. Never reduce this on your own — the user wants maximum coverage.**

### Run Analysis

```bash
# Standard invocation — runs all 50 perspectives (DO NOT add --shots)
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  <session-uuid>

# ONLY if user explicitly asks for fewer:
# bun run ... <session-uuid> --shots 5

# Dry run — show extracted payload without calling MiniMax
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  7873f9b4-b8f9-4746-b617-917b2e9f14a2 --dry --verbose

# Skip session chain tracing
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  7873f9b4-b8f9-4746-b617-917b2e9f14a2 --no-chain

# By full path
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  ~/.claude/projects/-Users-terryli-eon-cc-skills/7873f9b4-b8f9-4746-b617-917b2e9f14a2.jsonl
```

### Find Recent Sessions

```bash
# List recent session files sorted by modification time
ls -lt ~/.claude/projects/*//*.jsonl 2>/dev/null | head -10

# Find sessions for current project
ls -lt ~/.claude/projects/-Users-terryli-eon-cc-skills/*.jsonl | head -5
```

## Configuration

| Setting            | Source                                                           | Default                       |
| ------------------ | ---------------------------------------------------------------- | ----------------------------- |
| MiniMax API key    | `~/.claude/.secrets/ccterrybot-telegram` (`MINIMAX_API_KEY=...`) | Required                      |
| Model              | Hardcoded in script                                              | `MiniMax-M2.5-highspeed`      |
| Max output tokens  | Hardcoded in script                                              | 16384                         |
| Max structured log | Hardcoded in script                                              | 890K chars (~222K tokens)     |
| Parallel shots     | `--shots N` flag                                                 | 50 (max: 50)                  |
| Session chaining   | `--no-chain` flag                                                | Enabled                       |
| Chain depth        | Hardcoded in script                                              | 10 levels (recursive parents) |
| Sibling window     | Hardcoded in script                                              | 24 hours (same project dir)   |
| Budget strategy    | Automatic                                                        | Drop oldest ancestors first   |

## Context Budget

MiniMax M2.5 empirical context ceiling: **951K content chars (~260K tokens)**. Official docs claim 204,800 tokens but 260K works in practice. Prompt caching is automatic (no way to disable via API).

The script reserves headroom for system prompt, framing, and output tokens:

| Component       | Budget      |
| --------------- | ----------- |
| Structured log  | 890K chars  |
| System prompt   | ~1.5K chars |
| Session summary | ~10K chars  |
| Output tokens   | 16K tokens  |

### Adaptive Fidelity Levels

When full-fidelity content exceeds the budget, the script progressively reduces detail:

| Level       | Tool Input | Tool Result | Assistant Text | Behavior                  |
| ----------- | ---------- | ----------- | -------------- | ------------------------- |
| L0          | Full       | Full        | Full           | No truncation             |
| L1          | 2000 chars | 2000 chars  | Full           | Trim tool I/O             |
| L2          | 600 chars  | 800 chars   | Full           | More aggressive tool trim |
| L3          | 300 chars  | 400 chars   | 3000 chars     | Also trim assistant text  |
| L4          | 150 chars  | 200 chars   | 1500 chars     | Aggressive all-around     |
| Middle-trim | —          | —           | —              | Keep beginning + end      |

User text is never truncated below 4000 chars (user intent is most important).

## Output Format

Each finding follows this structure:

```
### [CRITICAL|WARNING|INFO] Finding title
- Perspectives: <which reviewers reported this>
- Confidence: <N>/<total> perspectives flagged this
- Turn: T<number>
- Evidence: "<quoted from transcript>"
- Risk: <what goes wrong>
- Fix: <specific command or file edit>
```

Ends with "Priority Action Plan" — 3-5 actions ranked by cross-perspective agreement.

## JSONL Parsing Hardening

The parser handles several edge cases discovered through testing across 40+ real sessions (50KB–96MB):

- **Self-referential poisoning prevention** — Only searches user-role text blocks for continuation markers, never raw JSON lines. Prevents false parent chain detection when session transcripts contain code with marker strings and unrelated UUIDs.
- **Image block handling** — Replaces base64 image data (up to 1.9MB per image) with `[image: type, size]` placeholders. MiniMax can't process images, and base64 would waste context budget.
- **Queue-operation extraction** — Captures queued user messages (typed while assistant was busy) as `[queued message]` turns. These contain real user intent not visible in regular user turns.
- **Last-prompt extraction** — Captures `last-prompt` entries (final user message before session end) that may not appear as regular turns.
- **Memory-efficient parsing** — Line-by-line iteration without splitting entire file into array (saves ~40% memory on 96MB files).
- **Agent subagent filtering** — Excludes `agent-*` files from sibling discovery (they contain tool-level execution, not user-facing conversation).
- **Empty session skipping** — Sessions under 1KB are excluded from sibling discovery (aborted/empty sessions contribute no turns).

## Limitations

- MiniMax 2.5 highspeed accepts ~260K tokens — very large sessions are adaptively trimmed
- Session chain tracing only works when parent sessions exist on disk
- Each perspective is independent — no cross-perspective learning during the review phase
- Prompt caching is automatic and cannot be disabled via API
- Not a substitute for proper testing or code review
- Distillation quality depends on review quality — garbage in, garbage out

## Troubleshooting

| Issue                       | Cause                             | Fix                                                                             |
| --------------------------- | --------------------------------- | ------------------------------------------------------------------------------- |
| `MINIMAX_API_KEY not found` | Missing or malformed secrets file | Check `~/.claude/.secrets/ccterrybot-telegram` contains `MINIMAX_API_KEY=<key>` |
| `No session JSONL found`    | Wrong UUID or project dir         | Use full path instead, or `ls ~/.claude/projects/` to find it                   |
| `context window exceeds`    | Payload too large for MiniMax     | Use `--dry` to check size; reduce `--shots` or use `--no-chain`                 |
| `All review shots failed`   | All N parallel calls hit errors   | Check API key, rate limits, or reduce payload with `--no-chain`                 |
| Echo/reproduction           | MiniMax confused by transcript    | Already mitigated with anti-echo prompt boundaries                              |
