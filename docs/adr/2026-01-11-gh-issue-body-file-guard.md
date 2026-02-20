---
status: accepted
date: 2026-01-11
---

# ADR: gh issue create --body-file Requirement

## Status

Accepted

## Context

When creating GitHub issues with long bodies using inline `--body` with heredocs:

```bash
gh issue create --title "Feature" --body "$(cat <<'EOF'
... long content (500+ characters) ...
EOF
)"
```

The command often fails silently:

- Issue URL is returned (appears successful)
- Issue does not actually exist in the repository
- No error message displayed

This was discovered during exp-066 research session where issues #23 and #24 were "created" with returned URLs, but neither existed when checked with `gh issue list`. Only after switching to `--body-file` did issue #25 actually persist.

## Decision

Implement a PreToolUse hook that soft-blocks `gh issue create` commands using inline `--body` and requires `--body-file` instead.

**Hook location**: `plugins/gh-tools/hooks/gh-issue-body-file-guard.mjs`

**Block type**: Soft block (`permissionDecision: deny`) - user can override if needed for short content.

**Runtime**: Bun (`.mjs` with `#!/usr/bin/env bun`)

## Consequences

### Positive

- Prevents silent failures when creating issues with long bodies
- Provides clear guidance on the reliable pattern
- Soft block allows override for legitimate short-body use cases

### Negative

- Slightly more complex workflow (write to file first)
- Additional temp file cleanup required

## Reliable Pattern

```bash
# 1. Write content to temp file
cat > /tmp/issue-body.md << 'EOF'
## Summary
Long issue content here...
EOF

# 2. Create issue with --body-file
gh issue create --title "Feature Request" --body-file /tmp/issue-body.md

# 3. Clean up
rm /tmp/issue-body.md
```

## References

- Issue #5: Hook Request
- exp-066 session: Issues #23, #24 silent failure evidence
- [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md)
