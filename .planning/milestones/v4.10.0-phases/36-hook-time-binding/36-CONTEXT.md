# Phase 36: Hook-Time Binding - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning (after Phase 35 completes)
**Mode:** Pre-authored

<domain>
## Phase Boundary

Move session→loop binding from skill-Bash-subprocess (where `$CLAUDE_SESSION_ID` is empty — confirmed by anthropics/claude-code#47018) to hook-time, where Claude Code passes a JSON payload on stdin including `session_id`. Install a new `SessionStart` hook that authoritatively binds `owner_session_id`. Rewrite `heartbeat-tick.sh` to read stdin instead of env vars. Detect cwd drift on every heartbeat tick.

</domain>

<decisions>
## Implementation Decisions

### Locked

- `SessionStart` hook is the binding event. Per Anthropic docs, it fires on both fresh `claude` launches AND `claude --resume`, with a `source` field distinguishing them.
- Session IDs are read from stdin JSON (`{session_id, cwd, source, transcript_path, hook_event_name}`). Env vars `$CLAUDE_SESSION_ID` are NOT used.
- `owner_session_id="pending-bind"` is the canonical placeholder set by `start` skill. The SessionStart hook replaces it atomically on first match.
- Multi-session same-folder: only the FIRST session in a folder becomes owner. Subsequent sessions log `observer` to provenance and do NOT bind.
- `bound_cwd` field added to heartbeat.json on first tick; subsequent ticks compare current cwd against bound_cwd; mismatch → `cwd_drift_detected: true` + provenance event.

### Claude's Discretion

- Whether to use `additionalContext` JSON output to surface binding state into the session (low value; skip unless trivial).
- Exact retry behavior when registry lock contention happens during atomic compare-and-swap (5×100ms retry is fine; same as existing libs).

</decisions>

<code_context>

## Files to Read Before Editing

- `plugins/autonomous-loop/hooks/heartbeat-tick.sh` — full rewrite of stdin parsing; preserve all error-trap and logging structure
- `plugins/autonomous-loop/scripts/hook-install-lib.sh` — extend `install_hook` to install BOTH PostToolUse and SessionStart
- `plugins/autonomous-loop/skills/start/SKILL.md` — drop env-var capture; add collision check via AskUserQuestion
- `plugins/autonomous-loop/skills/setup/SKILL.md` — make sure setup installs both hooks
- `plugins/autonomous-loop/scripts/registry-lib.sh` — `update_loop_field` is the atomic CAS primitive

### Hook Stdin Schema (verified against Anthropic docs)

```json
{
  "session_id": "abc123-uuid-...",
  "cwd": "/Users/terryli/eon/some-project",
  "source": "startup|resume|clear|compact",
  "transcript_path": "/path/to/transcript.jsonl",
  "hook_event_name": "SessionStart"
}
```

### Settings.json Hook Registration Shape

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/.../hooks/session-bind.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

</code_context>

<binding_state_machine>

## Binding State Transitions

```
owner_session_id state → action on SessionStart match

  ""               → bind_first (CAS to current session_id)
  "unknown"        → bind_first (legacy, treat as empty)
  "pending-bind"   → bind_first (canonical placeholder from start skill)
  <my session_id>  → bind_resume (refresh ts; log idempotent)
  <other-alive>    → observer (do nothing; log observer event)
  <other-dead>     → stale_owner_detected (DO NOT auto-reclaim;
                     log event; require explicit user reclaim)
```

</binding_state_machine>

<tests>

## Test Coverage

- `test-session-bind.sh` — 5 cases:
  1. Fresh session in folder with `pending-bind` registry entry → bound (CAS verified)
  2. Same session resumes → idempotent re-bind with refreshed timestamp
  3. Two parallel sessions race for binding → exactly one wins (CAS atomic; loser logs observer)
  4. Session in folder with dead-owner registry entry → no auto-reclaim; logs `stale_owner_detected`
  5. Session in folder with live-other-owner → logs observer; never modifies registry
- `test-heartbeat-stdin.sh` — 3 cases:
  1. PostToolUse stdin payload populated → heartbeat written
  2. cwd drift mid-session (cwd changes from bound_cwd) → flag set + provenance event
  3. Empty stdin (degraded) → graceful no-op exit 0

</tests>
