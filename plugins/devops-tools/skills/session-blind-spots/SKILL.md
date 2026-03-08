---
name: session-blind-spots
description: Diverse-perspective consensus blind spot analysis of Claude Code sessions via MiniMax 2.5 highspeed. Runs 10-20 parallel reviews from orthogonal specialist lenses, then distills into confidence-ranked findings. Traces session chains for full history. TRIGGERS - blind spots, session review, what did I miss, session debrief, retrospective, missed issues, session analysis.
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion
---

# Session Blind Spots

Send a Claude Code session transcript to MiniMax 2.5 highspeed for independent diverse-perspective consensus review. Each shot uses a distinct specialist reviewer lens (not copies of the same prompt). A distillation pass merges, deduplicates, and ranks findings by how many perspectives independently surfaced each issue.

## How It Works

1. **Session chain tracing** — Follows parent session references in JSONL to build full history
2. **Rich extraction** — Turns with user/assistant text, tool calls, file paths touched, errors encountered
3. **Noise stripping** — Removes system reminders, skill listings, base64 data, deferred tool blocks
4. **Adaptive fidelity** — 5 progressive truncation levels to maximize signal within MiniMax's context budget
5. **Diverse perspectives** — Fires N parallel MiniMax calls, each with a unique specialist reviewer lens
6. **Consensus distillation** — Feeds all N results into a final MiniMax call that merges, deduplicates, and ranks by cross-perspective agreement

## 20 Specialist Perspectives

Each perspective is an orthogonal reviewer lens that focuses on one specific class of issues:

| #   | Perspective                      | Focus                                                |
| --- | -------------------------------- | ---------------------------------------------------- |
| 1   | Completeness Tracker             | Unfulfilled user requests, abandoned tasks           |
| 2   | Security Auditor                 | Credentials exposure, injection vectors, permissions |
| 3   | Verification Engineer            | Changes never tested or validated                    |
| 4   | Side-Effect Hunter               | Orphaned processes, dirty git state, leaked files    |
| 5   | Architecture Critic              | Over/under-engineering, wrong abstractions           |
| 6   | Error Flow Analyst               | Silent failures, missing error handling, race conds  |
| 7   | User Intent Decoder              | Misunderstandings, missed implicit expectations      |
| 8   | Regression Hunter                | Fixes that broke other things, changed contracts     |
| 9   | Process Auditor                  | Wrong branch, skipped commits, bypassed hooks        |
| 10  | Documentation Staleness Detector | Stale docs, outdated examples, wrong references      |
| 11  | Concurrency & Timing Analyst     | Race conditions, lock issues, timing bugs            |
| 12  | Dependency Chain Auditor         | Missing imports, circular deps, unpinned versions    |
| 13  | Performance & Resource Analyst   | Memory leaks, O(n²), unbounded growth                |
| 14  | Cross-System Impact Analyst      | Ripple effects to other services/configs             |
| 15  | Idempotency Checker              | Operations unsafe to run twice                       |
| 16  | Configuration Drift Detector     | SSoT violations, duplicated settings                 |
| 17  | Rollback Feasibility Analyst     | Irreversible operations without backup               |
| 18  | Platform Portability Reviewer    | macOS-only assumptions, hardcoded paths              |
| 19  | Technical Debt Accountant        | Quick fixes, copy-paste, untracked TODOs             |
| 20  | _(Reserved for future)_          |                                                      |

Default: 10 perspectives per run (rotated). Use `--shots 20` for all 20.

## Why Diverse Perspectives?

Same prompt N times is near-deterministic — different perspectives are orthogonal by design:

- **Higher recall** — Security Auditor catches credentials; Verification Engineer catches untested changes
- **Lower false positives** — Findings seen from 2+ perspectives are more credible
- **Confidence ranking** — "Seen by 5/10 perspectives" is near-certain; "1/10" is speculative
- **Cheap** — MiniMax is fast and inexpensive; 10 parallel perspectives complete in ~25s

## Usage

### Run Analysis

```bash
# Default: 10 diverse perspectives → consensus distillation
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  7873f9b4-b8f9-4746-b617-917b2e9f14a2

# All 20 perspectives for maximum coverage
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  7873f9b4-b8f9-4746-b617-917b2e9f14a2 --shots 20

# Single perspective (no consensus, faster but less reliable)
bun run $HOME/eon/cc-skills/plugins/devops-tools/scripts/session-blind-spots.ts \
  7873f9b4-b8f9-4746-b617-917b2e9f14a2 --shots 1

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

| Setting            | Source                                                           | Default                   |
| ------------------ | ---------------------------------------------------------------- | ------------------------- |
| MiniMax API key    | `~/.claude/.secrets/ccterrybot-telegram` (`MINIMAX_API_KEY=...`) | Required                  |
| Model              | Hardcoded in script                                              | `MiniMax-M2.5-highspeed`  |
| Max output tokens  | Hardcoded in script                                              | 16384                     |
| Max structured log | Hardcoded in script                                              | 890K chars (~222K tokens) |
| Parallel shots     | `--shots N` flag                                                 | 10 (max: 20)              |
| Session chaining   | `--no-chain` flag                                                | Enabled                   |

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
