# autoloop Plugin

> Self-revising LOOP_CONTRACT.md pattern for long-horizon autonomous work. V1 Final: multiplicity-safe registry, atomic ownership, PID-reuse defense, generation counters.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Deep dive**: [tech-stack](./docs/registry-schema.md)

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

1. Run `/autoloop:start` on the contract path
2. The `init_state_dir` function in Phase 5 (state-lib.sh) auto-derives `loop_id` from the file path and adds it to frontmatter (MIG-01)
3. Contract body is unchanged; only frontmatter is mutated (idempotent)
4. The loop is automatically registered in `~/.claude/loops/registry.json`
5. **No manual migration needed** — existing contracts are supported as-is

Single-loop users upgrading to v1: The registry is per-machine, not per-repo. If you have 3 repos each with their own `LOOP_CONTRACT.md`, all 3 are tracked simultaneously in the same registry. The ownership protocol ensures only one can be active at a time per loop_id.

---

## Architecture Overview (4-Layer)

The autoloop system is built on four atomic primitives that collectively defend against 6 catastrophic pitfalls:

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

Verify with: `ls plugins/autoloop/skills/` (expected: doctor reclaim setup start status stop)

| Skill     | Purpose                                                    | When to Use                                |
| --------- | ---------------------------------------------------------- | ------------------------------------------ |
| `start`   | Scaffold contract, install hooks, register loop            | First time: `/autoloop:start`              |
| `status`  | Read loop state, report iteration, owner, health           | Mid-loop: `/autoloop:status`               |
| `stop`    | Mark DONE, unregister, unload launchd                      | End loop: `/autoloop:stop`                 |
| `setup`   | One-time machine setup (hook install, dirs)                | Once per machine (or after reinstall)      |
| `reclaim` | Take ownership of stuck loop (dead owner)                  | Emergencies: `/autoloop:reclaim <loop_id>` |
| `doctor`  | Diagnose fleet health, surface stale/orphaned loops, --fix | Periodic audits or after suspected crash   |

---

## Library Scripts (13 .sh files)

Verify with: `ls plugins/autoloop/scripts/`. Library scripts (the `*-lib.sh` files) define functions sourced by skills and hooks; standalone scripts (`heal-self.sh`, `migrate-from-autonomous-loop.sh`, `waker.sh`) are executable directly.

| Script                            | Role | Exports / Purpose                                                                                                                                                                                   | Used By                                                      |
| --------------------------------- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `registry-lib.sh`                 | lib  | `derive_loop_id`, `read_registry`, `register_loop`, `enumerate_loops`, `update_loop_field`, `_with_registry_lock`                                                                                   | All other libs; start skill                                  |
| `state-lib.sh`                    | lib  | `state_dir_path`, `init_state_dir`, `write_heartbeat`, `read_heartbeat`, `now_us`, `set_contract_field`, `init_contract_frontmatter_v2`, `slugify`, `compute_short_hash`, `migrate_legacy_contract` | start, status, heartbeat-tick, session-bind, /autoloop:start |
| `ownership-lib.sh`                | lib  | `acquire_owner_lock`, `release_owner_lock`, `verify_owner_alive`, `is_reclaim_candidate`, `reclaim_loop`, `staleness_seconds`                                                                       | start, stop, reclaim, heartbeat-tick                         |
| `hook-install-lib.sh`             | lib  | `install_hook`, `install_session_bind`, `install_pacing_veto`, `install_empty_firing`, `install_all_hooks`, `uninstall_*`                                                                           | start, setup                                                 |
| `launchd-lib.sh`                  | lib  | `generate_plist`, `load_plist`, `unload_plist`                                                                                                                                                      | start, stop                                                  |
| `status-lib.sh`                   | lib  | `loop_status`, `format_status_table`                                                                                                                                                                | status skill                                                 |
| `doctor-lib.sh`                   | lib  | Fleet-diagnostic helpers — orphan detection, cross-validation, --fix actions                                                                                                                        | doctor skill                                                 |
| `provenance-lib.sh`               | lib  | `emit_provenance` — append JSONL events to per-loop + global provenance logs                                                                                                                        | session-bind, heartbeat-tick, ownership-lib                  |
| `notifications-lib.sh`            | lib  | `send_notification` — emit Pushover / Telegram notifications                                                                                                                                        | notify, heartbeat-tick                                       |
| `notify-coalesce-lib.sh`          | lib  | `coalesce_notifications` — dedupe by loop_id within a window                                                                                                                                        | notify, heartbeat-tick                                       |
| `heal-self.sh`                    | exec | Idempotent registry self-heal: archive entries with no owner binding > 1h                                                                                                                           | session-bind hook (gated by registry hash)                   |
| `migrate-from-autonomous-loop.sh` | exec | One-shot rewriter for legacy `~/.claude/settings.json` paths after the v17 rename                                                                                                                   | /autoloop:setup; manual                                      |
| `waker.sh`                        | exec | launchd bridge — invoked by per-loop launchd plist to trigger an external waker                                                                                                                     | launchd job                                                  |

**All libs source each other as needed** (e.g., state-lib.sh sources registry-lib.sh). Each uses `set -euo pipefail` and exits with 0 on success, 1 on error.

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

## On-Disk Layout (Wave 3, schema_version: 2)

New contracts live under a hidden `.autoloop/` subdirectory keyed by campaign slug + 6-hex short hash. Multiple campaigns can coexist in the same project cwd; each gets its own slot.

```
<project_cwd>/
├── .autoloop/
│   ├── odb-research--a1b2c3/
│   │   ├── CONTRACT.md              ← the live contract (the /loop prompt)
│   │   ├── PROVENANCE.md            ← human+AI-readable owner+history index
│   │   └── state/
│   │       ├── heartbeat.json
│   │       └── revision-log/<session_id>.jsonl
│   └── flaky-ci-watcher--d4e5f6/    ← second concurrent campaign
│       └── ...
└── .gitignore                       ← auto-appended `.autoloop/`
```

**Why this layout**:

- Each campaign is fully self-contained: contract, provenance ledger, state, and revision log all sit together. Easy to inspect, archive, or rsync.
- Multi-campaign coexistence in one cwd is first-class — different campaigns get different `loop_id`s deterministically because their paths differ.
- The `<slug>--<hash>` directory name is self-explanatory enough that an AI agent can `ls .autoloop/` and immediately tell which campaigns are present, when each was created, and which is "theirs" (cross-referencing `created_in_session` in the frontmatter).
- `.autoloop/` lives inside the project — survives `cp -r`, ships in tarballs, gets `git clean -dXf`'d cleanly. State that lives in `~/.claude/loops/registry.json` is the SSoT for ownership; the per-campaign dir is the storage for everything else.

**Short hash** (`short_hash` in the registry) = `sha256(creator_session_id + ":" + created_at_utc + ":" + legacy_loop_id)[:6]`. Independent of contract path, so the path can be derived from the slug + hash without circular dependency.

**Auto-migration**: when `/autoloop:start` runs in a directory containing a legacy `<cwd>/LOOP_CONTRACT.md`, the `migrate_legacy_contract` function (in `scripts/state-lib.sh`) detects it and performs the move atomically: contract → `.autoloop/<slug>--<hash>/CONTRACT.md`, state dir → `.autoloop/<slug>--<hash>/state/`, registry-entry split (old marked `migrated_to=<new>`, new entry created with `migrated_from=<old>`). Idempotent; the second call is a no-op.

**Legacy layout still works**: contracts at `<cwd>/LOOP_CONTRACT.md` with state at `<git-toplevel>/.loop-state/<loop_id>/` continue to function. `state_dir_path` detects the path pattern and routes accordingly. Migration is opportunistic — it only fires when the user explicitly invokes `/autoloop:start`.

---

## The Contract File (schema_version: 2)

`LOOP_CONTRACT.md` (legacy layout) or `.autoloop/<slug>--<hash>/CONTRACT.md` (v2). Structure:

```yaml
---
name: <short-descriptive-name>
version: 1
schema_version: 2 # signals v2 fields below are populated
iteration: 0
last_updated: <ISO 8601 UTC>
exit_condition: <human-readable termination rule>
max_iterations: 100
# Immutable birth record (auto-stamped at start; never mutated)
loop_id: <12 hex>
campaign_slug: <kebab-case slug from `name`>
created_at_utc: <ISO 8601>
created_in_session: <session-uuid; bound on first SessionStart>
created_at_cwd: <absolute realpath>
created_at_git_branch: <branch>
created_at_git_commit: <sha>
# Mutable owner mirror (registry is SSoT; these track for offline readers)
owner_session_id: <uuid>
owner_pid: <int>
owner_started_us: <epoch_us>
generation: <int>
last_heartbeat_us: <epoch_us>
last_heartbeat_session_id: <uuid>
# Cross-links
state_dir: <absolute path>
revision_log_path: <absolute path>
# Staleness hint
expected_cadence: hourly # continuous | event-driven | hourly | daily | <N>s
status: active # active | paused | completed | orphaned
---
# Core Directive         # preserved verbatim
## Provenance & Ownership # decision tree for any AI agent reading this file
## Execution Contract    # Orient / Act / Revise / Persist
## Dynamic Wake-Up       # delay table
## Current State         # rewrite every firing
## Implementation Queue  # prioritized tasks
## Revision Log          # append-only ledger
## Non-Obvious Learnings # preserved across firings
```

**Key invariant**: The **registry** at `~/.claude/loops/registry.json` is the SSoT for ownership decisions. The contract frontmatter is a **read-cache** — written best-effort by `set_contract_field` (in `scripts/state-lib.sh`) AFTER the registry write succeeds. If a crash interleaves, the frontmatter mirror is stale but the registry remains authoritative. Consumers (offline readers, doctor, post-mortem agents) should treat divergence as "trust the registry; the contract is stale".

**Where the mirror is written**:

| Hook / Function     | Mirrors                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `init_state_dir`    | All immutable birth fields (loop*id, campaign_slug, created*\*) at scaffold time, idempotent — only writes missing fields |
| `session-bind.sh`   | `owner_session_id`, `owner_started_us`, `created_in_session` (only if pending) on first SessionStart binding              |
| `heartbeat-tick.sh` | `last_heartbeat_us`, `last_heartbeat_session_id`, `iteration`, `generation` after every PostToolUse heartbeat write       |
| `reclaim_loop`      | `owner_session_id`, `owner_pid`, `owner_started_us`, `generation` after atomic registry takeover                          |

**Legacy contracts** (`schema_version: 1` or absent) remain readable. Status reporters print `(legacy)` and skip the v2 fields. They are not auto-upgraded by Wave 2 — that's deferred to Wave 3 (which moves the contract path and rotates loop_id anyway).

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

**Symptom**: `/autoloop:start` fails or contract has no `loop_id:` line.

**Diagnosis**:

```bash
grep "^loop_id:" ./LOOP_CONTRACT.md
# If missing or empty → MIG-01 migration needed
```

**Fix**: Call `init_state_dir` via the library:

```bash
PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop"
source "$PLUGIN_ROOT/scripts/registry-lib.sh"
source "$PLUGIN_ROOT/scripts/state-lib.sh"

LOOP_ID=$(derive_loop_id "./LOOP_CONTRACT.md")
init_state_dir "$LOOP_ID" "./LOOP_CONTRACT.md"
```

Result: `loop_id` auto-added to frontmatter; loop registered in registry; ready to start.

### "Stuck owner" (Pitfall #5: orphaned lock)

**Symptom**: `/autoloop:start` hangs on "acquiring lock" for >10 seconds.

**Diagnosis**:

```bash
LOOP_ID="a1b2c3d4e5f6"  # Replace with your loop_id
ps -p $(jq -r ".loops[] | select(.loop_id == \"$LOOP_ID\") | .owner_pid" \
  $HOME/.claude/loops/registry.json) >/dev/null 2>&1
# If process doesn't exist → owner is dead
```

**Fix**: Reclaim the loop:

```bash
/autoloop:reclaim $LOOP_ID
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
PLUGIN_ROOT="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/autoloop"
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

- Never use `ScheduleWakeup` as pacing (use Tier 0 in-turn instead). Recognized in-the-wild failure: a firing wrote "Next wake at 08:29:00Z (~247s, cache-warm)" with 4 actionable queue items still ready — "cache-warm" is not a blocker, it's a side-property of Tier 2. The pre-decision gate in `templates/LOOP_CONTRACT.template.md` (Phase 4) requires you to _name_ the external signal you're waiting for in writing before any `ScheduleWakeup` call. If you can't name one, you're pacing — go Tier 0.
- Never leave dead air between completed iterations
- Never re-issue `/loop` with a new prompt each firing (contract is the SSoT)
- Never store state in memory — contract file is the state
- Never let the revision-log grow unbounded (archive entries >100)
- Never rely on pending ScheduleWakeup from a prior firing if THIS firing did new work (Phase 3 Revise is mandatory)
- Never override loop_id in the contract manually (it's derived deterministically from the path)
- Never call `acquire_owner_lock` from multiple processes in the same session (only one owner per loop_id)
- Never write a timestamp labeled UTC computed from local time. Always use `date -u` (or `date -u -v +Ns` / `date -u -d '+N seconds'` for future times). The contract, registry, heartbeat, and statusline are all UTC; a mislabeled local-time entry silently mismatches every clock and can spuriously trigger reclaim via stale-heartbeat detection. Real-world incident: an iter-N revision-log line "Next firing at 01:11 UTC" written from PDT 01:11 (= 08:11 UTC) made the next firing read 7 hours in the past.

---

## Real-World Case Study

See `docs/design/2026-04-20-autonomous-loop/spec.md` (preserved at original path for historical context) for a full walkthrough of a 37-iteration autonomous quant-research campaign that used a hand-authored version of this pattern (before v1 automation).

Key takeaway: **The contract file is the interface contract**. Subagents, external tools, resumable firings — all read it directly. The revision-log captures decisions atomically. Ownership disputes are resolved by generation counter. This architecture survived 23 days of continuous operation, 4 machine reboots, and 2 session interruptions without missing a beat.
