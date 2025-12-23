# ADR: Ralph Dual Time Tracking (Runtime + Wall-Clock)

**Date**: 2025-12-22
**Status**: Implemented
**Related**: [Ralph Stop Visibility Observability](/docs/adr/2025-12-22-ralph-stop-visibility-observability.md)

## Context

Ralph Wiggum's time tracking used **wall-clock time** (calendar time since `/ralph:start`). This caused premature session termination when users closed Claude Code CLI overnight:

| Scenario                        | Wall-Clock Behavior        | Expected Behavior                |
| ------------------------------- | -------------------------- | -------------------------------- |
| Start 6 PM, work 2h, close 8 PM | -                          | -                                |
| Reopen 8 AM (12h later)         | "Max runtime (9h) reached" | Should continue (only 2h worked) |

**Root cause**: `get_elapsed_hours()` calculated `time.time() - start_timestamp`, which includes all calendar time including CLI closure periods.

## Decision

Implement **dual time tracking** that separates CLI runtime from wall-clock time:

| Metric         | Purpose                           | Used For                                     |
| -------------- | --------------------------------- | -------------------------------------------- |
| **Runtime**    | CLI active time (excludes pauses) | Limit enforcement (`min_hours`, `max_hours`) |
| **Wall-clock** | Calendar time since start         | Informational display only                   |

### Key Design Choices

1. **Gap Detection Threshold**: 300 seconds (5 minutes)
   - If gap between Stop hook calls > 300s, CLI was closed
   - Gap time is NOT added to accumulated runtime
   - Matches existing `MAX_INTERVAL` constant for idle detection

2. **Long-Running Tools Are Safe**: Stop hook only fires AFTER tool execution completes
   - During a 30-minute ML backtest, hook is dormant
   - When tool completes, hook fires with millisecond gap
   - No false pause detection from long-running operations

3. **State-Based Accumulation**: Runtime stored in session state
   - `accumulated_runtime_seconds`: Total CLI runtime
   - `last_hook_timestamp`: For gap detection between calls

4. **Display Format**: Clear labeled dual display

   ```
   Runtime: 3.2h/9.0h | Wall: 15.0h
   ```

5. **Migration Strategy**: Start fresh (runtime = 0)
   - Simple, no estimation needed
   - Existing sessions initialize with runtime = 0

## Implementation

### New State Fields (`ralph-state.json`)

```python
default_state = {
    # Existing fields...
    # NEW: Runtime tracking (v7.9.0)
    "accumulated_runtime_seconds": 0.0,
    "last_hook_timestamp": 0.0,
}
```

### Config Schema Addition

```python
@dataclass
class LoopLimitsConfig:
    # ...existing fields...
    cli_gap_threshold_seconds: int = 300  # 5 minutes
```

### Runtime Update Logic (`utils.py`)

```python
def update_runtime(state: dict, current_time: float, gap_threshold: int = 300) -> float:
    last_hook = state.get("last_hook_timestamp", 0.0)
    accumulated = state.get("accumulated_runtime_seconds", 0.0)

    if last_hook > 0:
        gap = current_time - last_hook
        if gap < gap_threshold:
            accumulated += gap  # CLI was active
        else:
            logger.info(f"CLI pause detected: {gap:.0f}s gap")  # CLI was closed

    state["last_hook_timestamp"] = current_time
    state["accumulated_runtime_seconds"] = accumulated
    return accumulated
```

### Limit Enforcement Changes

All limit checks now use **runtime** instead of wall-clock:

```python
# BEFORE
elapsed = get_elapsed_hours(session_id, project_dir)
if elapsed >= config["max_hours"]:
    allow_stop(...)

# AFTER
runtime_hours = get_runtime_hours(state)
if runtime_hours >= config["max_hours"]:
    allow_stop(...)
```

## Files Modified

| File                                        | Changes                                                                                                   |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `plugins/ralph/hooks/utils.py`              | Added `update_runtime()`, `get_runtime_hours()`, renamed `get_elapsed_hours()` → `get_wall_clock_hours()` |
| `plugins/ralph/hooks/loop-until-done.py`    | Call `update_runtime()` on each hook, new display format, runtime-based limit checks                      |
| `plugins/ralph/hooks/core/config_schema.py` | Added `cli_gap_threshold_seconds` to `LoopLimitsConfig`                                                   |
| `plugins/ralph/commands/status.md`          | Display both runtime and wall-clock                                                                       |
| `plugins/ralph/README.md`                   | Document dual time tracking                                                                               |

## Consequences

### Positive

- **Accurate limit enforcement**: 9h of actual CLI work, not 9h of calendar time
- **Overnight sessions work correctly**: Close at night, resume in morning
- **User visibility**: Both metrics displayed so users understand the difference
- **Backward compatible**: Existing sessions initialize runtime to 0

### Negative

- **Additional state fields**: Two new fields per session
- **Complexity**: Must track both times everywhere
- **First iteration after pause**: Shows 0.0h runtime (accurate but may surprise users)

### Risks Mitigated

- **Long-running tools**: Stop hook only fires after completion (confirmed safe)
- **Rapid iterations**: Gap detection prevents false pause detection for quick iterations

## Testing

1. Start loop, verify runtime = 0
2. Run for 5 minutes, verify runtime ≈ 5 min
3. Close Claude Code, wait 10 minutes, reopen
4. Verify runtime still ≈ 5 min (gap not counted)
5. Verify wall-clock shows ≈ 15 min
6. Verify limits use runtime, not wall-clock

## References

- [Ralph Plugin README](/plugins/ralph/README.md#dual-time-tracking-v790)
- [Stop Visibility ADR](/docs/adr/2025-12-22-ralph-stop-visibility-observability.md)
