---
adr: 2025-12-09-itp-hooks-plan-file-exemption
source: ~/.claude/plans/streamed-stargazing-rabin.md
implementation-status: completed
phase: phase-2
last-updated: 2025-12-09
---

# Implementation Spec: Plan File Exemption for pretooluse-guard.sh

**ADR**: [Exempt Plan Files from ASCII Diagram Blocking](/docs/adr/2025-12-09-itp-hooks-plan-file-exemption.md)

## Summary

Add a configurable exemption to `pretooluse-guard.sh` that allows plan files (`~/.claude/plans/*.md`) to bypass ASCII diagram blocking. This prevents workflow disruption during Claude's planning phase while maintaining enforcement for production documentation.

## Implementation Tasks

- [x] Add plan file path detection to pretooluse-guard.sh
- [x] Implement `ITP_HOOKS_EXEMPT_PLANS` environment variable check
- [x] Default to exempt with warning when variable not set
- [x] Configure variable in mise.toml as SSoT
- [x] Create ADR documenting the decision
- [x] Create design spec

## Files Modified

1. **`plugins/itp-hooks/hooks/pretooluse-guard.sh`**
   - Added path check for `/.claude/plans/.*\.md$`
   - Added environment variable detection using `${VAR+x}` pattern
   - Warning message when variable not set (guides toward mise SSoT)

2. **`~/.config/mise/config.toml`** (user configuration)
   - Added `ITP_HOOKS_EXEMPT_PLANS = "true"` in `[env]` section

## Configuration

| Variable                 | Default                        | Description                                        |
| ------------------------ | ------------------------------ | -------------------------------------------------- |
| `ITP_HOOKS_EXEMPT_PLANS` | `true` (with warning if unset) | Set to `"false"` to enforce blocking on plan files |

## Success Criteria

- [x] Plan files with ASCII tables/diagrams can be written without blocking
- [x] Non-plan markdown files still enforce ASCII diagram source requirement
- [x] Warning message appears when environment variable not explicitly set
- [x] Setting `ITP_HOOKS_EXEMPT_PLANS=false` re-enables blocking for plan files
- [x] mise.toml serves as SSoT for the configuration

## Testing

```bash
# Test 1: Plan file should be allowed (with mise configured)
ITP_HOOKS_EXEMPT_PLANS=true
# Write to ~/.claude/plans/test.md with box chars → should succeed

# Test 2: Plan file should warn when not configured
unset ITP_HOOKS_EXEMPT_PLANS
# Write to ~/.claude/plans/test.md → should succeed with warning

# Test 3: Plan file should block when explicitly disabled
ITP_HOOKS_EXEMPT_PLANS=false
# Write to ~/.claude/plans/test.md with box chars → should block

# Test 4: Non-plan files still enforced
# Write to /docs/test.md with box chars → should block (no source block)
```

## Future Considerations

- **Workflow-aware tracking**: Consider implementing session-based state tracking so that when `graph-easy` is used via Bash, subsequent Write/Edit operations are automatically allowed (regardless of source block presence)
- **Path configuration**: Could extend to allow user-configurable exempt paths beyond `~/.claude/plans/`
