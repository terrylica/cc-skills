---
status: accepted
date: 2026-01-02
decision-maker: [Terry Li]
consulted: [Write-Path-Auditor, Read-Path-Auditor, Timing-Freshness-Auditor]
research-method: 9-agent-parallel-dctl
clarification-iterations: 4
perspectives: [ProviderToOtherComponents, OperationalService]
---

# ADR: Ralph Guidance Freshness Detection

**Design Spec**: [Implementation Spec](/docs/design/2026-01-02-ralph-guidance-freshness-detection/spec.md)

## Context and Problem Statement

The Ralph autonomous loop system uses guidance (encouraged/forbidden items) to steer AI behavior during long-running sessions. Currently, `/ralph:encourage` and `/ralph:forbid` commands write guidance to `.claude/ralph-config.json`, but there is no timestamp tracking. This causes stale guidance from previous sessions to persist indefinitely.

**Observed Problem**: RSSI-related guidance items added in an earlier session continued appearing in Stop hook output, even though they were no longer relevant to the current task.

**Root Cause**: The guidance system lacks:

1. Timestamp on guidance writes (no way to detect staleness)
2. Stale guidance cleanup on session start
3. Fresh constraint re-scanning during Stop hook iterations

### Before/After

**Before** (stale guidance persists):

```
┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎ Before:                                                                                                               ╎
╎                                                                                                                       ╎
╎ ┌──────────────────┐  writes   ┌───────────────────┐  no timestamp   ┌───────────┐  stale items   ┌─────────────────┐ ╎
╎ │ /ralph:encourage │ ────────> │ ralph-config.json │ ──────────────> │ Stop Hook │ ─────────────> │ AUTONOMOUS MODE │ ╎
╎ └──────────────────┘           └───────────────────┘                 └───────────┘                └─────────────────┘ ╎
╎                                                                                                                       ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

**After** (fresh-wins with timestamp + constraint scanner):

```
┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎ After:                                                                                                                                                        ╎
╎                                                                                                                                                               ╎
╎ ┌──────────────────┐  +timestamp   ┌───────────────────┐  stale check     ┌────────────────────┐       ┌──────────────────┐  fresh only   ┌─────────────────┐ ╎
╎ │ /ralph:encourage │ ────────────> │ ralph-config.json │ ───────────────> │     Stop Hook      │ ────> │ Fresh-Wins Merge │ ────────────> │ AUTONOMOUS MODE │ ╎
╎ └──────────────────┘               └───────────────────┘                  └────────────────────┘       └──────────────────┘               └─────────────────┘ ╎
╎                                                                             ∧                                                                                 ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−    │                     −−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
                                                                          ╎   │                    ╎
                                                                          ╎   │ fresh scan         ╎
                                                                          ╎   │                    ╎
                                                                          ╎ ┌────────────────────┐ ╎
                                                                          ╎ │ constraint-scanner │ ╎
                                                                          ╎ └────────────────────┘ ╎
                                                                          ╎                        ╎
                                                                          └−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source (Before)</summary>

```
graph { flow: east; }
( Before:
  [encourage cmd] { label: "/ralph:encourage"; }
  [config1] { label: "ralph-config.json"; }
  [stop hook1] { label: "Stop Hook"; }
  [output1] { label: "AUTONOMOUS MODE"; }
)
[encourage cmd] -- writes --> [config1]
[config1] -- no timestamp --> [stop hook1]
[stop hook1] -- stale items --> [output1]
```

</details>

<details>
<summary>graph-easy source (After)</summary>

```
graph { flow: east; }
( After:
  [encourage cmd2] { label: "/ralph:encourage"; }
  [config2] { label: "ralph-config.json"; }
  [scanner] { label: "constraint-scanner"; }
  [stop hook2] { label: "Stop Hook"; }
  [merge] { label: "Fresh-Wins Merge"; }
  [output2] { label: "AUTONOMOUS MODE"; }
)
[encourage cmd2] -- +timestamp --> [config2]
[config2] -- stale check --> [stop hook2]
[scanner] -- fresh scan --> [stop hook2]
[stop hook2] -> [merge]
[merge] -- fresh only --> [output2]
```

</details>

## Research Summary

| Agent Perspective        | Key Finding                                      | Confidence |
| ------------------------ | ------------------------------------------------ | ---------- |
| Write-Path-Auditor       | jq appends with deduplication, missing timestamp | High       |
| Read-Path-Auditor        | Fresh read each iteration, no caching            | High       |
| Timing-Freshness-Auditor | NO caching, next iteration sees changes          | High       |

**Critical Discovery**: Schema defines `timestamp: str = ""` in `config_schema.py:234`, but `encourage.md` line 76 does NOT populate it.

## Decision Log

| Decision Area       | Options Evaluated                         | Chosen             | Rationale                                 |
| ------------------- | ----------------------------------------- | ------------------ | ----------------------------------------- |
| Staleness Detection | Manual clear, timestamp-based, on-the-fly | All three combined | Defense in depth                          |
| Timestamp Location  | Separate file, in guidance object         | In guidance object | Single source of truth                    |
| Stale Threshold     | 12h, 24h, session-based                   | 24h                | Balance between freshness and persistence |
| Conflict Resolution | Config wins, fresh wins, merge            | Fresh wins         | Fresh scan is authoritative               |

### Trade-offs Accepted

| Trade-off                | Choice              | Accepted Cost                |
| ------------------------ | ------------------- | ---------------------------- |
| Performance vs Freshness | Fresh scan each run | ~2-5s per iteration overhead |
| Complexity vs Robustness | Three-layer defense | More code to maintain        |

## Decision Drivers

- Stale guidance causes confusion and incorrect AI behavior
- User expects guidance to be session-scoped, not permanent
- Constraint scanning already exists but isn't integrated with Stop hook
- Fresh-wins priority ensures current state is always authoritative

## Considered Options

- **Option A**: Add `--replace` flag to encourage/forbid (manual intervention required)
- **Option B**: Timestamp-based staleness detection only (passive, no re-scan)
- **Option C**: On-the-fly constraint re-scan + timestamp + stale clear (comprehensive) ← Selected

## Decision Outcome

Chosen option: **Option C**, because it provides defense in depth:

1. **Timestamp tracking** enables staleness detection
2. **Stale clear on start** removes legacy guidance
3. **On-the-fly re-scan** ensures fresh constraints override stale config

## Synthesis

**Convergent findings**: All agents agreed data flow is working correctly—the issue is missing metadata (timestamp) for staleness detection.

**Divergent findings**: Agents initially focused on potential caching bugs; investigation revealed no caching exists.

**Resolution**: User confirmed the root cause is accumulation without expiry, and selected comprehensive three-layer fix.

## Consequences

### Positive

- Guidance freshness is guaranteed each Stop hook iteration
- Stale items from previous sessions automatically cleared
- Constraint scanner results integrated into guidance system
- User `/ralph:encourage` commands remain authoritative within session

### Negative

- 2-5 second overhead per Stop hook iteration for constraint scan
- Increased code complexity in `loop-until-done.py`
- macOS-specific date parsing (`date -j -f`) in bash scripts

## Architecture

```
                                ┌────────────────────────────────┐
                                │        /ralph:encourage        │
                                └────────────────────────────────┘
                                  │
                                  │ +timestamp
                                  ∨
┌───────────────┐  +timestamp   ┌────────────────────────────────┐
│ /ralph:forbid │ ────────────> │   .claude/ralph-config.json    │ ──────┐
└───────────────┘               └────────────────────────────────┘       │
                                  │                                      │
                                  │                                      │
                                  ∨                                      │
                                ┌────────────────────────────────┐       │
                                │ Stop Hook (loop-until-done.py) │ <┐    │
                                └────────────────────────────────┘  │    │
                                  │                                 │    │
                                  │                                 │    │
                                  ∨                                 │    │
                                ┌────────────────────────────────┐  │    │
                                │     constraint-scanner.py      │  │    │
                                └────────────────────────────────┘  │    │
                                  │                                 │    │
                                  │                                 │    │
                                  ∨                                 │    │
                                ┌────────────────────────────────┐  │    │
                                │     Fresh-Wins Merge Logic     │ <┼────┘
                                └────────────────────────────────┘  │
                                  │                                 │
                                  │                                 │
                                  ∨                                 │
                                ┌────────────────────────────────┐  │
                                │     AUTONOMOUS MODE Output     │  │
                                └────────────────────────────────┘  │
                                ┌────────────────────────────────┐  │
                                │          /ralph:start          │  │
                                └────────────────────────────────┘  │
                                  │                                 │
                                  │                                 │
                                  ∨                                 │
                                ┌────────────────────────────────┐  │
                                │  Stale Guidance Check (>24h)   │  │
                                └────────────────────────────────┘  │
                                  │                                 │
                                  │                                 │
                                  ∨                                 │
                                ┌────────────────────────────────┐  │
                                │      Clear Stale Guidance      │  │
                                └────────────────────────────────┘  │
                                  │                                 │
                                  │                                 │
                                  ∨                                 │
                                ┌────────────────────────────────┐  │
                                │       Ralph Session Loop       │ ─┘
                                └────────────────────────────────┘
```

<details>
<summary>graph-easy source (Architecture)</summary>

```
graph { flow: south; }
[start] { label: "/ralph:start"; }
[stale check] { label: "Stale Guidance Check (>24h)"; }
[clear] { label: "Clear Stale Guidance"; }
[session] { label: "Ralph Session Loop"; }
[encourage] { label: "/ralph:encourage"; }
[forbid] { label: "/ralph:forbid"; }
[config] { label: ".claude/ralph-config.json"; }
[stop hook] { label: "Stop Hook (loop-until-done.py)"; }
[scanner] { label: "constraint-scanner.py"; }
[merge] { label: "Fresh-Wins Merge Logic"; }
[output] { label: "AUTONOMOUS MODE Output"; }

[start] -> [stale check]
[stale check] -> [clear]
[clear] -> [session]
[session] -> [stop hook]
[encourage] -- +timestamp --> [config]
[forbid] -- +timestamp --> [config]
[config] -> [stop hook]
[stop hook] -> [scanner]
[scanner] -> [merge]
[config] -> [merge]
[merge] -> [output]
```

</details>

## References

- [Constraint Scanning ADR](/docs/adr/2025-12-29-ralph-constraint-scanning.md)
- Schema: `plugins/ralph/hooks/config_schema.py:234`
- Encourage command: `plugins/ralph/commands/encourage.md:76`
