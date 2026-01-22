---
status: implemented
date: 2026-01-22
decision-maker: Terry Li
consulted: [lifecycle-reference.md, uv workspace documentation]
research-method: multi-perspective-subagent-analysis
---

# ADR: pyproject.toml Root-Only Policy

## Context and Problem Statement

Claude Code repeatedly ignored PostToolUse hook reminders while editing pyproject.toml files with invalid configurations:

1. Created pyproject.toml in sub-directories instead of monorepo root
2. Added `path = "../../../external-pkg"` references escaping the monorepo boundary
3. Continued despite "PostToolUse:Edit hook error" messages appearing in transcript

**Root cause analysis**: PostToolUse hooks are informational-only (tool already executed). The `decision: "block"` field only ensures visibility, not enforcement.

## Decision Drivers

- Must PREVENT mistakes, not just remind after-the-fact
- Consistent with uv workspace best practices
- Belt-and-suspenders: PreToolUse blocks, PostToolUse catches edge cases
- Portable monorepo structure (no external path dependencies)

## Considered Options

### Option A: PreToolUse Hard Block Only

Implement PreToolUse guard that blocks pyproject.toml outside git root.

**Pros**: Prevents mistake entirely
**Cons**: No backup if guard has edge case bugs

### Option B: PostToolUse Reminder Only (Current State)

Continue with PostToolUse reminders that Claude may ignore.

**Pros**: Non-disruptive
**Cons**: Doesn't actually prevent mistakes (proven failure mode)

### Option C: Both PreToolUse + PostToolUse (Selected)

PreToolUse blocks obvious violations; PostToolUse catches edge cases.

**Pros**: Defense in depth, maximum coverage
**Cons**: Slightly more complex

## Decision Outcome

**Chosen option**: Option C - Both PreToolUse hard block + PostToolUse soft reminder.

### Policies Enforced

| Policy                   | PreToolUse | PostToolUse | Description                                     |
| ------------------------ | ---------- | ----------- | ----------------------------------------------- |
| Root-only pyproject.toml | ✅ Block   | —           | pyproject.toml only at git root                 |
| Path boundary validation | ✅ Block   | ✅ Remind   | [tool.uv.sources] path must not escape git root |
| Hoisted dev dependencies | ✅ Block   | —           | [dependency-groups] only at workspace root      |

### Detection Patterns

**Root-only policy**:

```javascript
// Block: pyproject.toml not at git root
!isAtGitRoot(filePath, gitRoot);
```

**Path escape detection**:

```javascript
// Block: path references resolving outside git root
const relativePath = relative(gitRoot, resolvedPath);
relativePath.startsWith("..") || relativePath.startsWith("/");
```

### Valid vs Invalid Examples

| Pattern                                         | Valid? | Reason           |
| ----------------------------------------------- | ------ | ---------------- |
| `rangebar = { git = "https://github.com/..." }` | ✅     | External via Git |
| `sibling = { workspace = true }`                | ✅     | Workspace member |
| `local = { path = "packages/lib" }`             | ✅     | Within monorepo  |
| `escape = { path = "../../../external" }`       | ❌     | Escapes git root |
| `packages/foo/pyproject.toml`                   | ❌     | Not at root      |

## Implementation

### Files Modified

| File                                | Change                               |
| ----------------------------------- | ------------------------------------ |
| `pretooluse-hoisted-deps-guard.mjs` | Added root-only + path escape checks |
| `posttooluse-reminder.ts`           | Added path escape reminder as backup |
| Unit tests                          | Added coverage for new patterns      |

### Hook Priority

PreToolUse checks in order:

1. Root-only policy (blocks non-root pyproject.toml)
2. Path boundary validation (blocks escaping paths)
3. Hoisted deps (blocks sub-package [dependency-groups])

## Consequences

### Positive

- Claude CANNOT write pyproject.toml outside git root
- Claude CANNOT add `path = "../../../"` escaping monorepo
- Defense in depth catches edge cases

### Negative

- May block legitimate use cases (escape hatch: user can manually edit)
- Requires git repository context (non-git directories allow anything)

## References

- [UV Workspaces](https://docs.astral.sh/uv/concepts/projects/workspaces/)
- [UV Dependencies](https://docs.astral.sh/uv/concepts/projects/dependencies/)
- [PostToolUse Hook Visibility ADR](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md)
