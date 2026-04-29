# Phase 37: Waker Hardening + launchd Collision Defense - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning (after Phase 36 completes)
**Mode:** Pre-authored

<domain>
## Phase Boundary

Make `claude --resume` spawn impossible unless five invariants hold. Fix the cwd-on-resume bug where `dirname(state_dir)` was used instead of `dirname(contract_path)`. Detect launchd Label collisions in `generate_plist` and resolve them safely. Every refusal becomes a typed provenance event plus a user-visible notification.

</domain>

<decisions>
## Implementation Decisions

### Locked

- Five-check invariant gate runs INSIDE the registry lock (`_with_registry_lock`) so observed state is consistent.
- Refuse-by-default: any uncertainty → no spawn. The worst outcome is "loop didn't auto-resume" (user notices via doctor); never "loop resumed wrong session".
- Label collision resolution: archive existing plist to `state_dir/orphans/<unixts>/`, `launchctl bootout`, then regenerate. Never overwrite a loaded plist silently.
- All notifications go through existing `notifications-lib.sh` (no new notification surface in this phase).

### Claude's Discretion

- Whether to add a `--dry-run` flag to spawn for testing (probably yes — small).
- Exact format of `state_dir/orphans/<ts>/` directory (just `<ts>/<old-plist-filename>` is enough).

</decisions>

<code_context>

## Files to Read Before Editing

- `plugins/autonomous-loop/scripts/waker.sh` — `spawn_claude_resume` function; replace cwd computation; add invariant gate
- `plugins/autonomous-loop/scripts/launchd-lib.sh` — `generate_plist` function; add collision detection + archive
- `plugins/autonomous-loop/scripts/registry-lib.sh` — `_with_registry_lock` for atomic invariant check
- `plugins/autonomous-loop/scripts/notifications-lib.sh` — `emit_notification` API (existing)
- `plugins/autonomous-loop/scripts/provenance-lib.sh` — `emit_provenance` (from Phase 35)

</code_context>

<five_check_invariant>

## The Five-Check Invariant

```
spawn_claude_resume(loop_id) acquires registry lock and verifies ALL of:

  (a) session_id =~ ^[0-9a-f-]{36}$        # real UUID
  (b) heartbeat.json exists AND
      heartbeat.cwd starts_with dirname(contract_path)   # proof of life from inside contract dir
  (c) heartbeat.bound_cwd == dirname(contract_path)      # no cwd drift
  (d) launchctl list | grep -c "$LABEL" == 1             # no collision
  (e) registry generation == observed_generation         # no concurrent reclaim

If any fails → emit_provenance "spawn_refused" with reason=<which check> + emit_notification + return 0
If all pass → cd "$(dirname "$contract_path")" && nohup claude --resume "$session_id" >> spawn.log 2>&1 &
```

</five_check_invariant>

<tests>

## Test Coverage

- `test-spawn-invariant.sh` — 6 cases (one per check + happy path):
  1. Invalid UUID → refused, provenance has `spawn_refused_invalid_session_id`
  2. No heartbeat → refused, `spawn_refused_no_heartbeat`
  3. Heartbeat from wrong cwd → refused, `spawn_refused_cwd_mismatch`
  4. cwd drift detected → refused, `spawn_refused_cwd_drift`
  5. Label collision (two launchctl entries) → refused, `spawn_refused_label_collision`
  6. All invariants hold → spawn proceeds, `spawn_succeeded` event, claude process spawned (mocked)
- `test-plist-collision.sh` — 3 cases:
  1. No existing plist → `generate_plist` writes cleanly
  2. Existing UNloaded plist → archived to orphans, regenerated
  3. Existing LOADED plist → unloaded, archived, regenerated, reloaded

</tests>
