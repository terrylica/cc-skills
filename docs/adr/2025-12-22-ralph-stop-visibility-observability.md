# ADR: Ralph Stop Visibility Observability

**Date**: 2025-12-22
**Status**: Implemented
**Related**: [Ralph Eternal Loop](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)

## Context

Session `cbe3a408-25a9-45b7-880d-70c26f19a1f6` ran for 10.2 hours and stopped after exceeding the `max_hours=9` limit. The user had **no visible notification** of why the session ended.

**Root cause**: Architectural asymmetry between stop functions:

| Function             | Behavior                                         | User Visibility |
| -------------------- | ------------------------------------------------ | --------------- |
| `continue_session()` | Returns `{"decision": "block", "reason": "..."}` | Visible         |
| `allow_stop()`       | Returns `{}`                                     | **Silent**      |
| `hard_stop()`        | Returns `{"continue": false}`                    | **Silent**      |

When sessions stopped normally, users couldn't determine if it was intentional completion, timeout, or an error.

## Decision

Implement a 5-layer observability system to ensure stop visibility across all termination paths:

| Layer | Feature                              | Visibility                                      |
| ----- | ------------------------------------ | ----------------------------------------------- |
| 1     | stderr notification                  | Terminal (immediate, visible to user)           |
| 2     | Cache file with session correlation  | Persistent (`~/.claude/ralph-stop-reason.json`) |
| 3     | Progress headers with warnings       | Claude sees in continuation prompt              |
| 4     | `/ralph:status` displays stop reason | On-demand check                                 |
| 5     | Automatic cache clearing             | Fresh slate per session on `/ralph:start`       |

### Key Design Choices

1. **stderr for terminal visibility**: Claude Code ignores stderr, so users see it immediately
2. **Cache file for persistence**: Survives session restart, includes `session_id` for correlation
3. **Both `allow_stop()` AND `hard_stop()`**: All termination paths need visibility
4. **Warning at limits**: Proactive notification in progress header before abrupt stop
5. **Error handling**: Cache write failures logged but don't block stop operation

### Cache Schema

```json
{
  "timestamp": "2025-12-22T21:32:27Z",
  "reason": "Maximum runtime (9h) reached",
  "decision": "stop",
  "type": "normal",
  "session_id": "cbe3a408-25a9-45b7-880d-70c26f19a1f6",
  "project_dir": "/Users/terryli/eon/alpha-forge"
}
```

## Implementation

### Layer 1: utils.py Stop Functions

```python
def _write_stop_cache(reason: str, decision: str, stop_type: str = "normal") -> None:
    """Write stop reason to cache file for observability."""
    stop_cache = Path.home() / ".claude" / "ralph-stop-reason.json"
    stop_cache.write_text(json.dumps({
        "timestamp": datetime.now().isoformat(),
        "reason": reason,
        "decision": decision,
        "type": stop_type,
        "session_id": os.environ.get("CLAUDE_SESSION_ID", "unknown"),
        "project_dir": os.environ.get("CLAUDE_PROJECT_DIR", ""),
    }))

def allow_stop(reason: str | None = None) -> None:
    if reason:
        _write_stop_cache(reason, "stop", "normal")
        print(f"\n[RALPH] Session stopped: {reason}\n", file=sys.stderr)
    print(json.dumps({}))

def hard_stop(reason: str) -> None:
    _write_stop_cache(reason, "hard_stop", "hard")
    print(f"\n[RALPH] HARD STOP: {reason}\n", file=sys.stderr)
    print(json.dumps({"continue": False, "stopReason": reason}))
```

### Layer 3: Progress Headers with Warnings

```python
# Approaching limits warning
if time_to_max < 1.0 or iters_to_max < 5:
    warning = " | **ENDING SOON**"
```

### Layer 4: status.md Enhancement

```bash
STOP_CACHE="$HOME/.claude/ralph-stop-reason.json"
if [[ -f "$STOP_CACHE" ]]; then
    echo "=== Last Stop Reason ==="
    jq -r '.reason' "$STOP_CACHE"
fi
```

### Layer 5: start.md Cache Clearing

```bash
rm -f "$HOME/.claude/ralph-stop-reason.json"
```

## Files Modified

| File                                     | Changes                                                              |
| ---------------------------------------- | -------------------------------------------------------------------- |
| `plugins/ralph/hooks/utils.py`           | Added `_write_stop_cache()`, modified `allow_stop()` + `hard_stop()` |
| `plugins/ralph/hooks/loop-until-done.py` | Enhanced progress headers with warnings                              |
| `plugins/ralph/commands/status.md`       | Fixed state file path bug, added stop reason display                 |
| `plugins/ralph/commands/start.md`        | Added `--production` flag, cache clearing                            |

## Consequences

### Positive

- Users always know why sessions stop (terminal message + persistent cache)
- Claude sees progress warnings before hitting limits
- Post-mortem debugging via `/ralph:status`
- Session correlation enables multi-session tracking

### Negative

- Cache file accumulates across sessions (minimal disk impact)
- stderr output may clutter terminal for very chatty sessions

### Bugs Fixed

- `status.md` was checking `loop-state.json` instead of `ralph-state.json`

## References

- [Ralph Eternal Loop ADR](/docs/adr/2025-12-20-ralph-rssi-eternal-loop.md)
- [Ralph Plugin README](/plugins/ralph/README.md#stop-visibility-observability-v770)
