# Requirements — v4.10.0 Autonomous Loop Anti-Fragility

<!-- # SSoT-OK -->

> Anti-fragile session→loop binding for the `autonomous-loop` plugin. Eliminates cross-contamination between Claude Code sessions sharing the same folder, makes every state mutation auditable, and gives operators a self-diagnostic doctor.
>
> Driving evidence (2026-04-29 incident analysis):
>
> - JSONL `1c58cfbc-…` recorded two distinct cwds (cross-worktree contamination)
> - Registry stored `owner_session_id: "unknown"` for every entry (broken `$CLAUDE_SESSION_ID` capture in skill Bash subprocess)
> - Zero `heartbeat.json` files written despite installed PostToolUse hook
> - One zombie launchd job (`f14e7c6d1ef1`) firing every 15 min into a registry with no entry for it
> - One orphan registry entry (`c864c05b8010`) with no plist, dangling owner_pid

## Goals

1. Cross-contamination becomes structurally impossible (defense-in-depth, refuse-by-default).
2. Every state mutation is logged to an append-only provenance ledger.
3. Operators get a self-diagnostic GREEN/YELLOW/RED report from inside Claude.
4. Recovery from corrupted state is automatic and idempotent.

## Non-Goals

- Re-architecting `loop_id` derivation (still `sha256(realpath(contract))[:12]`).
- Changing `LOOP_CONTRACT.md` user-facing schema.
- Multi-machine coordination (registry remains per-machine).

---

## Requirements

### Provenance (PROV)

- [ ] **PROV-01** — Append-only `<state_dir>/provenance.jsonl` ledger; one JSONL line per state mutation.
- [ ] **PROV-02** — Global mirror at `~/.claude/loops/global-provenance.jsonl` capped at 10k lines via rotation.
- [ ] **PROV-03** — Schema-versioned line shape: `{ts_iso, ts_us, event, loop_id, agent, session_id, cwd_observed, cwd_bound, registry_generation, owner_pid_before, owner_pid_after, reason, decision, schema_version}`.
- [ ] **PROV-04** — All state mutations write provenance BEFORE registry write (intent record survives partial failure).

### Hook-Time Binding (BIND)

- [ ] **BIND-01** — `SessionStart` hook (`hooks/session-bind.sh`) installed in `~/.claude/settings.json` alongside existing `PostToolUse`. Reads `{session_id, cwd, source}` from stdin JSON payload.
- [ ] **BIND-02** — On SessionStart with cwd under any registered contract dir: atomic compare-and-swap binds `owner_session_id` if currently empty/`unknown`/`pending-bind`. Logs `bind_first` / `bind_resume` / `observer` to provenance.
- [ ] **BIND-03** — `heartbeat-tick.sh` rewritten to read `session_id` and `cwd` from stdin payload (not env var). Records `bound_cwd` on first tick after bind. Detects cwd drift on subsequent ticks; flags `cwd_drift_detected: true` in heartbeat.json + provenance event.
- [ ] **BIND-04** — `skills/start/SKILL.md` drops broken `$CLAUDE_SESSION_ID` capture; sets `owner_session_id: "pending-bind"`. Collision check before scaffolding: if registry has live owner for the same `loop_id`, prompts user via `AskUserQuestion` (reclaim / sidecar / abort).

### Waker Hardening (WAKE)

- [ ] **WAKE-01** — `spawn_claude_resume` validates `session_id` matches UUID regex; refuses spawn on mismatch with typed `spawn_refused_invalid_session_id` provenance event.
- [ ] **WAKE-02** — Spawn cd's to `dirname(contract_path)` (not `dirname(state_dir)`); fixes cwd drift on resume.
- [ ] **WAKE-03** — `generate_plist` detects launchd Label collision via `launchctl list`; if existing entry, archive old plist to `state_dir/orphans/`, unload, regenerate.
- [ ] **WAKE-04** — Five-check pre-spawn invariant: (a) valid UUID; (b) ≥1 heartbeat with cwd under contract dir; (c) `bound_cwd == dirname(contract_path)`; (d) launchd Label has exactly one entry; (e) no conflicting registry binding.
- [ ] **WAKE-05** — Every spawn refusal emits typed provenance event AND user-facing notification. No silent drops.

### Doctor & Self-Heal (DOC)

- [ ] **DOC-01** — `/autonomous-loop:doctor` skill produces per-loop GREEN/YELLOW/RED report with remediation hints. Optional `--fix` mode for safe auto-remediation (unload orphan plists, archive corrupted entries — never spawns).
- [ ] **DOC-02** — Doctor cross-references registry ↔ heartbeat ↔ `launchctl list` ↔ `~/.claude/projects/<sanitized-cwd>/*.jsonl`. Detects: orphan plists, stale owners, label collisions, multi-cwd JSONL contamination, missing heartbeats, duplicate bindings.
- [ ] **DOC-03** — `heal-self.sh` is idempotent self-migration. Archives entries with `owner_session_id ∈ {"unknown", "unknown-session", ""}` to `~/.claude/loops/registry.archive.jsonl`. Runs once per registry-version bump on every fresh SessionStart (gated by content hash).
- [ ] **DOC-04** — `status` skill surfaces last 10 provenance events per loop + doctor verdict (one-line GREEN/YELLOW/RED) at top of output.

---

## Traceability

| REQ-ID      | Phase                                                 |
| ----------- | ----------------------------------------------------- |
| PROV-01..04 | Phase 35: Provenance Foundation                       |
| BIND-01..04 | Phase 36: Hook-Time Binding                           |
| WAKE-01..05 | Phase 37: Waker Hardening + launchd Collision Defense |
| DOC-01..04  | Phase 38: Doctor & Self-Heal                          |
