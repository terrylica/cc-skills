# autonomous-loop Plugin

> Self-revising LOOP_CONTRACT.md pattern for long-horizon autonomous work. V1 Final: multiplicity-safe registry, atomic ownership, PID-reuse defense, generation counters.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Siblings**: [ru](../ru/CLAUDE.md) | **Deep dive**: [tech-stack](./docs/registry-schema.md)

---

## Navigation

- [Back-Compat Notes](#back-compat-notes-single-loop-migration)
- [Architecture Overview](#architecture-overview-4-layer)
- [Skills at a Glance](#skills-at-a-glance)
- [Library Scripts](#library-scripts-all-7)
- [6 Catastrophic Pitfalls](#6-catastrophic-pitfalls--phase-ownership)
- [Troubleshooting Playbook](#troubleshooting-playbook)
- [Deferred to V2](#deferred-to-v2)

---

## Back-Compat Notes (Single-Loop Migration)

**If you have an existing `LOOP_CONTRACT.md` without `loop_id` in the frontmatter:**

1. Run `/autonomous-loop:start` on the contract path
2. The `init_state_dir` function in Phase 5 (state-lib.sh) auto-derives `loop_id` from the file path and adds it to frontmatter (MIG-01)
3. Contract body is unchanged; only frontmatter is mutated (idempotent)
4. The loop is automatically registered in `~/.claude/loops/registry.json`
5. **No manual migration needed** — existing contracts are supported as-is

Single-loop users upgrading to v1: The registry is per-machine, not per-repo. If you have 3 repos each with their own `LOOP_CONTRACT.md`, all 3 are tracked simultaneously in the same registry. The ownership protocol ensures only one can be active at a time per loop_id.

---

## Architecture Overview (4-Layer)

The autonomous-loop system is built on four atomic primitives that collectively defend against 6 catastrophic pitfalls:

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: MACHINE REGISTRY                                      │
│  ~/.claude/loops/registry.json (atomic JSON, fd 9 flock)        │
│  SSoT for all loops on this machine: loop_id, owner_pid,        │
│  generation, state_dir, contract_path, heartbeat freshness      │
└──────────────────────────────┬──────────────────────────────────┘
                               │ (update_loop_field with atomic flock)
┌──────────────────────────────┴──────────────────────────────────┐
│  LAYER 2: OWNER LOCK & PID-REUSE DEFENSE                       │
│  ~/.claude/loops/<loop_id>.owner.lock (flock/lockf, fd 8)      │
│  Ensures: exactly one owner at a time                           │
│  Defends: Pitfall #1 (PID reuse) via owner_start_time_us check │
└──────────────────────────────┬──────────────────────────────────┘
                               │ (acquire_owner_lock / release_owner_lock)
┌──────────────────────────────┴──────────────────────────────────┐
│  LAYER 3: HEARTBEAT & STALENESS DETECTION                      │
│  <state_dir>/heartbeat.json (written by PostToolUse hook)       │
│  Emitted on every tool invocation; last_wake_us used to detect  │
│  stuck loops (>3× expected_cadence → reclaim candidate)         │
└──────────────────────────────┬──────────────────────────────────┘
                               │ (write_heartbeat from hook, staleness_seconds for reclaim)
┌──────────────────────────────┴──────────────────────────────────┐
│  LAYER 4: REVISION LOG & GENERATION COUNTER                    │
│  <state_dir>/revision-log/<session_id>.jsonl                    │
│  Atomic generation increment on reclaim; takeover events logged  │
│  Defends: Pitfall #2 (TOCTOU) via generation epoch detection    │
└─────────────────────────────────────────────────────────────────┘
```

**Design principle**: All four layers are **append-only or atomic-compare-swap**. No overwrites, no partial updates. This guarantees safety under concurrent access and machine crashes.

---

## Skills at a Glance

| Skill     | Purpose                                          | When to Use                                       |
| --------- | ------------------------------------------------ | ------------------------------------------------- |
| `start`   | Scaffold contract, install hook, register loop   | First time: `/autonomous-loop:start`              |
| `status`  | Read loop state, report iteration, owner, health | Mid-loop: `/autonomous-loop:status`               |
| `stop`    | Mark DONE, unregister, unload launchd            | End loop: `/autonomous-loop:stop`                 |
| `setup`   | One-time machine setup (hook install, dirs)      | Once per machine (or after reinstall)             |
| `notify`  | Send notifications (coalesced by loop_id)        | Called by heartbeat-tick.sh (automatic)           |
| `reclaim` | Take ownership of stuck loop (dead owner)        | Emergencies: `/autonomous-loop:reclaim <loop_id>` |

---

## Library Scripts (All 7)

| Script                                            | Exports                                                                                                                       | Used By                              |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `registry-lib.sh`                                 | `derive_loop_id`, `read_registry`, `register_loop`, `enumerate_loops`, `update_loop_field`                                    | All other libs; start skill          |
| `state-lib.sh`                                    | `state_dir_path`, `init_state_dir`, `write_heartbeat`, `read_heartbeat`, `now_us`                                             | start, status, heartbeat-tick        |
| `ownership-lib.sh`                                | `acquire_owner_lock`, `release_owner_lock`, `verify_owner_alive`, `is_reclaim_candidate`, `reclaim_loop`, `staleness_seconds` | start, stop, reclaim, heartbeat-tick |
| `hook-install-lib.sh`                             | `install_hook`, `uninstall_hook`                                                                                              | start, setup                         |
| `launchd-lib.sh`                                  | `generate_plist`, `load_plist`, `unload_plist`                                                                                | start, stop                          |
| `status-lib.sh`                                   | `loop_status`, `format_status_table`                                                                                          | status skill                         |
| `notifications-lib.sh` + `notify-coalesce-lib.sh` | `send_notification`, `coalesce_notifications`                                                                                 | notify skill; heartbeat-tick hook    |

**All scripts source each other as needed** (e.g., state-lib.sh sources registry-lib.sh to read loop entries). Each uses `set -euo pipefail` and exits with 0 on success, 1 on error.

---

## 6 Catastrophic Pitfalls & Phase Ownership

| Pitfall                                | Scenario                                                                                                                                         | Mitigation                                                                                                                                                           | Phase Owner                                         | Evidence                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------- | ---------------------------------------- |
| **#1: PID Reuse**                      | Owner PID 12345 dies; kernel recycles the PID to unrelated process X; X becomes the "owner" by accident                                          | `capture_process_start_time` + tolerance check in `verify_owner_alive`; owner_start_time_us stamped at registration and compared on verify (1s tolerance for jitter) | Phase 4 (ownership-lib.sh)                          | test-ownership.sh test 3                                                       |
| **#2a: TOCTOU (first half)**           | Session A reads entry "generation:0, owner:A"; Session B simultaneously increments to "generation:1, owner:B"; A reads stale copy and acts on it | Atomic flock on registry.json (fd 9) around all read-modify-write operations in `update_loop_field`                                                                  | Phase 2 (registry-lib.sh)                           | test-registry-write.sh: concurrent writes                                      |
| **#2b: TOCTOU (second half)**          | Reclaimer detects dead owner, calls `reclaim_loop`, but original owner wakes up simultaneously and also calls acquire                            | Generation counter in registry; heartbeat-tick hook checks registration generation before writing. Mismatch = stale session                                          | Phase 4 (ownership-lib.sh) + Phase 5 (state-lib.sh) | test-reclaim.sh: concurrent reclaim                                            |
| **#3: Cross-Filesystem Lock Failure**  | `.lock` file on NFS, `flock` atomicity not guaranteed across mounts                                                                              | Use `mktemp` in same dir as heartbeat.json (`state_dir`) then atomic `mv` for heartbeat; don't rely on flock on network mounts                                       | Phase 5 (state-lib.sh, write_heartbeat)             | test-heartbeat-hook.sh: temp + move pattern                                    |
| **#4: Registry Corruption (JSON)**     | Power loss / kill -9 during `jq                                                                                                                  | tee` → partial JSON in registry.json                                                                                                                                 | All writes use atomic `jq -in "input                | ..." $file > $temp && mv $temp $file` pattern (mktemp + mv in same filesystem) | Phase 2 (registry-lib.sh) | test-registry-write.sh: integrity checks |
| **#5: Orphaned Lock**                  | Owner crashes, lock fd 8 held forever → subsequent attempts wait indefinitely                                                                    | Timeouts: flock --wait 5 (5 sec), lockf with retry loop (50× 100ms = 5 sec); heartbeat staleness check (is_reclaim_candidate)                                        | Phase 4 (ownership-lib.sh)                          | test-ownership.sh: timeout + reclaim flow                                      |
| **#6: Hook Not Firing (Silent Stale)** | Heartbeat hook not installed in ~/.claude/settings.json → heartbeat.json never written → loop appears stale forever                              | install_hook (idempotent) verifies hook is registered; loop can't start without it (start skill calls install_hook before init_state_dir)                            | Phase 3 (hook-install-lib.sh)                       | test-hook-install.sh: verify registration                                      |

---

## The Contract File

`LOOP_CONTRACT.md` lives at a path you choose (default: `./LOOP_CONTRACT.md`). Structure:

```yaml
---
name: <short-descriptive-name>
version: 1
loop_id: <auto-derived on first init, 12 hex chars>
iteration: 0
last_updated: <ISO 8601 UTC>
exit_condition: <human-readable termination rule>
max_iterations: 100
---
# Core Directive         # preserved verbatim
## Execution Contract    # Orient / Act / Revise / Persist
## Dynamic Wake-Up       # delay table
## Current State         # rewrite every firing
## Implementation Queue  # prioritized tasks
## Revision Log          # append-only ledger
## Non-Obvious Learnings # preserved across firings
```

**Key invariant**: The contract file is the SSoT for loop state. Every firing reads it fresh, updates it, and persists decisions atomically via git commit. The heartbeat and registry track **ownership and health**, not state. Separation of concerns.

---

## Waker Tier System

**Every firing must end with exactly one of these**:

| Tier                                       | Mechanism                                               | Cost                             | When to Use                                                  |
| ------------------------------------------ | ------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------ |
| **0 — In-turn continuation (default)**     | Next queue item runs in same turn; no waker             | Zero                             | Implementation Queue has ready work AND tokens remain        |
| **1 — `Monitor`**                          | Arm on background script stdout; reactive wake on event | Near-zero (cache stays warm)     | External event is natural readiness signal (file-watch, log) |
| **2 — `ScheduleWakeup` (≤270s)**           | Short timer, stays in 5-min prompt cache TTL            | Cache hit + real-time wait       | Timed external blocker (rate limit, known ETA)               |
| **3 — `ScheduleWakeup` (≥1200s)**          | Long timer, expects cache miss on resume                | Full cache miss + wall-clock gap | Session ends; user away for a while                          |
| **4 — External waker (launchd/watchexec)** | Cross-session waker; fresh claude session launches      | Full cold start                  | Machine rebooted; need automatic resume without user action  |

**Key rule**: Never pick Tier 2 for pacing (Tier 0 beats it). `ScheduleWakeup` is strictly for **external blockers**, not scheduling your own work.

---

## Ownership Protocol

**How a loop transitions between owners:**

1. **Startup (acquire)**: Session A calls `acquire_owner_lock(loop_id)` → blocks if another session holds fd 8 on the lockfile
2. **Ownership**: A reads registry entry, verifies it claims `owner_pid: $$` and `owner_start_time_us` matches current process (with 1s tolerance)
3. **Heartbeat**: On every PostToolUse, A calls `write_heartbeat(loop_id, session_id, iteration)` → updates `state_dir/heartbeat.json`
4. **Reclaim (if stuck)**: B calls `is_reclaim_candidate(loop_id)` → checks if A's owner_pid is dead (kill -0 fails) OR heartbeat is stale (>3× cadence)
5. **Atomic takeover**: B calls `reclaim_loop(loop_id)` → atomically: increments `generation`, updates `owner_pid` / `owner_start_time_us` / `owner_session_id`, appends takeover event to revision-log
6. **Conflict detection**: A's next heartbeat write reads current `generation` from registry; if it mismatches what A saw at startup, A detects it was reclaimed and stops

**Guarantees**:

- Exactly one owner at a time (flock serialization on fd 8)
- Dead owners detected within 3 cadences (staleness check)
- Reclaim is atomic (generation counter prevents TOCTOU conflicts)
- PID reuse defended via start_time_us check (1s tolerance for jitter)

---

## Troubleshooting Playbook

### "Loop won't start" (MIG-05 evidence: contract missing loop_id)

**Symptom**: `/autonomous-loop:start` fails or contract has no `loop_id:` line.

**Diagnosis**:

```bash
grep "^loop_id:" ./LOOP_CONTRACT.md
# If missing or empty → MIG-01 migration needed
```

**Fix**: Call `init_state_dir` via the library:

```bash
PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"
source "$PLUGIN_ROOT/scripts/state-lib.sh"

LOOP_ID=$(derive_loop_id "./LOOP_CONTRACT.md")
init_state_dir "$LOOP_ID" "./LOOP_CONTRACT.md"
```

Result: `loop_id` auto-added to frontmatter; loop registered in registry; ready to start.

### "Stuck owner" (Pitfall #5: orphaned lock)

**Symptom**: `/autonomous-loop:start` hangs on "acquiring lock" for >10 seconds.

**Diagnosis**:

```bash
LOOP_ID="a1b2c3d4e5f6"  # Replace with your loop_id
ps -p $(jq -r ".loops[] | select(.loop_id == \"$LOOP_ID\") | .owner_pid" \
  $HOME/.claude/loops/registry.json) >/dev/null 2>&1
# If process doesn't exist → owner is dead
```

**Fix**: Reclaim the loop:

```bash
/autonomous-loop:reclaim $LOOP_ID
# Confirm the prompt; generation counter increments; ownership transfers
```

### "Registry corrupted" (Pitfall #4: partial JSON)

**Symptom**:

```bash
jq empty "$HOME/.claude/loops/registry.json"
# Error: parse error (invalid JSON)
```

**Diagnosis & Fix**:

```bash
# Back up the corrupted file
cp ~/.claude/loops/registry.json ~/.claude/loops/registry.json.corrupted

# Rebuild from disk (enumerate all contract files in your repos)
# For each contract:
LOOP_ID=$(derive_loop_id "./LOOP_CONTRACT.md")
STATE_DIR="./.loop-state/$LOOP_ID"
if [ -d "$STATE_DIR" ]; then
  # Entry exists on disk; re-register
  ENTRY=$(jq -n \
    --arg loop_id "$LOOP_ID" \
    --arg contract_path "$(realpath ./LOOP_CONTRACT.md)" \
    --arg state_dir "$(realpath $STATE_DIR)" \
    --arg generation "0" \
    '{loop_id: $loop_id, contract_path: $contract_path, state_dir: $state_dir, generation: $generation}')
  register_loop "$ENTRY"
fi
```

Then verify:

```bash
jq empty "$HOME/.claude/loops/registry.json" && echo "✓ Valid"
```

### "Hook not firing" (Pitfall #6: silent stale)

**Symptom**: Heartbeat not updating, loop appears stale after 10+ minutes.

**Diagnosis**:

```bash
# Check if hook is installed
jq '.hooks[] | select(.type == "PostToolUse")' ~/.claude/settings.json | \
  grep -q "heartbeat-tick" && echo "✓ Hook present" || echo "✗ Hook missing"

# Check heartbeat timestamp
LOOP_ID="a1b2c3d4e5f6"
STATE_DIR=$(jq -r ".loops[] | select(.loop_id == \"$LOOP_ID\") | .state_dir" \
  $HOME/.claude/loops/registry.json)
jq '.last_wake_us' "$STATE_DIR/heartbeat.json"
# Compare to current time: date +%s%N | cut -c1-16
```

**Fix**: Reinstall hook:

```bash
PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autonomous-loop"
source "$PLUGIN_ROOT/scripts/hook-install-lib.sh"
install_hook
# Restart Claude Code; next tool invocation fires the hook
```

---

## Deferred to V2

These are explicitly out of v1 scope:

- **LIN-01**: Linux/systemd parity (launchd → systemd.timer automation)
- **LIN-02**: Linux PID capture accuracy (ps lstart parsing on diverse distros)
- **FED-01**: Cross-machine federation (registry replication, lock service over network)

---

## Core Design Principle: Wakers Are Not Pacing

**Every waker mechanism exists for one reason only: to make the main Claude Code session resume.** There is no other point. The loop never executes work outside Claude Code — only inside it. So picking a waker reduces to: what is the cheapest, most honest way to signal "work is ready"?

The classical bug: using a waker as pacing. If iter-N completes and iter-N+1 is ready, **do not** call `ScheduleWakeup(60s)`. Do not call it at all. Chain in-turn instead. `ScheduleWakeup` is for **external blockers**, not for pacing your own work. A firing that produces "scheduled next wake-up, did nothing else" while the Implementation Queue has ready work is a regression.

**Empirical smell-check**: Compute `dead_time = wait_seconds / total_cycle_seconds` across the last 3 firings. If `dead_time > 0.25` across 3+ consecutive firings, you are using the waker as pacing. Fix it by dropping to Tier 0 (in-turn) or Tier 1 (Monitor on a natural event).

---

## Anti-Patterns (Don't Do These)

- Never use `ScheduleWakeup` as pacing (use Tier 0 in-turn instead)
- Never leave dead air between completed iterations
- Never re-issue `/loop` with a new prompt each firing (contract is the SSoT)
- Never store state in memory — contract file is the state
- Never let the revision-log grow unbounded (archive entries >100)
- Never rely on pending ScheduleWakeup from a prior firing if THIS firing did new work (Phase 3 Revise is mandatory)
- Never override loop_id in the contract manually (it's derived deterministically from the path)
- Never call `acquire_owner_lock` from multiple processes in the same session (only one owner per loop_id)

---

## Real-World Case Study

See `docs/design/2026-04-20-autonomous-loop/spec.md` for a full walkthrough of a 37-iteration autonomous quant-research campaign that used a hand-authored version of this pattern (before v1 automation).

Key takeaway: **The contract file is the interface contract**. Subagents, external tools, resumable firings — all read it directly. The revision-log captures decisions atomically. Ownership disputes are resolved by generation counter. This architecture survived 23 days of continuous operation, 4 machine reboots, and 2 session interruptions without missing a beat.
