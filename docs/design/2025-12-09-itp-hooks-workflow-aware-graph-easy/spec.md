---
adr: 2025-12-09-itp-hooks-workflow-aware-graph-easy
source: ~/.claude/plans/cheeky-fluttering-thompson.md
implementation-status: completed
phase: phase-1
last-updated: 2025-12-09
---

# Implementation Spec: Workflow-Aware Graph-Easy Detection

**ADR**: [Workflow-Aware Graph-Easy Detection](/docs/adr/2025-12-09-itp-hooks-workflow-aware-graph-easy.md)

## Summary

Enable inter-hook communication so that when `graph-easy` is invoked via Bash, subsequent Write/Edit operations are automatically allowed without requiring the `<summary>graph-easy source</summary>` block to already be present.

## Implementation Tasks

- [x] Create state directory structure (`~/.claude/hooks/state/`)
- [x] Modify `posttooluse-reminder.sh` to write session flag on graph-easy detection
- [x] Modify `pretooluse-guard.sh` to check for session flag before blocking
- [x] Test the workflow: graph-easy → write → verify allowed
- [x] Test negative case: write without graph-easy → verify blocked

## Files to Modify

1. **`plugins/itp-hooks/hooks/posttooluse-reminder.sh`**
   - Add flag writing inside the graph-easy detection block
   - Create state directory if needed
   - Write timestamp to `{session_id}.graph-easy-used` file

2. **`plugins/itp-hooks/hooks/pretooluse-guard.sh`**
   - Add flag check after plan file exemption, before ASCII check
   - Read and validate flag timestamp (< 30 seconds)
   - Consume (delete) flag after allowing write

## Configuration

| Parameter       | Value                          | Description                            |
| --------------- | ------------------------------ | -------------------------------------- |
| State directory | `~/.claude/hooks/state/`       | Session flag files location            |
| Flag filename   | `{session_id}.graph-easy-used` | Per-session flag file                  |
| Flag expiry     | 30 seconds                     | Window to allow write after graph-easy |
| Flag content    | Unix timestamp                 | When graph-easy was last used          |

## Success Criteria

- [x] Running `graph-easy` via Bash creates flag file in state directory
- [x] Write/Edit to markdown with box chars succeeds when flag is fresh (< 30s)
- [x] Flag is consumed (deleted) after successful write
- [x] Write/Edit to markdown with box chars is blocked when no flag exists
- [x] Expired flags (> 30s) are cleaned up and don't allow writes
- [x] No cross-session interference (flags are session-scoped)

## Testing Plan

```bash
# Test 1: Verify flag creation
SESSION_ID="test-session"
echo '{"tool_name":"Bash","tool_input":{"command":"graph-easy ..."},"session_id":"'$SESSION_ID'"}' | \
  ~/eon/cc-skills/plugins/itp-hooks/hooks/posttooluse-reminder.sh
ls -la ~/.claude/hooks/state/${SESSION_ID}.graph-easy-used

# Test 2: Verify flag allows write (mock - actual test requires hook integration)
# The flag should be present and fresh

# Test 3: Verify flag expiry
# Wait 31 seconds, then attempt write - should block

# Test 4: Verify non-graph-easy workflow still blocks
# Write markdown with box chars without prior graph-easy - should block
```

## Rollback Plan

If issues arise, the flag check can be disabled by:

1. Commenting out the flag check block in `pretooluse-guard.sh`
2. The existing blocking behavior will resume

No data migration needed - flag files are ephemeral and can be deleted.
