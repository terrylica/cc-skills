---
status: superseded
date: 2026-01-11
superseded_date: 2026-02-28
---

# ADR: gh issue create --body-file Requirement

## Status

**Superseded** (2026-02-28) — Original premise disproved by controlled experiments.

## Context

When creating GitHub issues with long bodies using inline `--body` with heredocs:

```bash
gh issue create --title "Feature" --body "$(cat <<'EOF'
... long content (500+ characters) ...
EOF
)"
```

The command was believed to fail silently:

- Issue URL is returned (appears successful)
- Issue does not actually exist in the repository
- No error message displayed

This was reported during exp-066 research session where issues #23 and #24 were "created" with returned URLs, but neither existed when checked with `gh issue list`.

## Decision

~~Implement a PreToolUse hook that soft-blocks `gh issue create` commands using inline `--body` and requires `--body-file` instead.~~

**Superseded**: Hook removed, inline `--body` is now permitted.

## Supersession (2026-02-28)

Controlled experiments on 2026-02-28 tested three methods with ~6KB and ~63KB bodies:

| Method                | Body Size | Result  | Content Integrity                |
| --------------------- | --------- | ------- | -------------------------------- |
| `--body-file`         | 6KB       | Success | Full                             |
| `--body "$VAR"`       | 6KB       | Success | Full                             |
| `--body "$(heredoc)"` | 6KB       | Success | Full                             |
| `--body "$VAR"`       | 63KB      | Success | Full (near API 65536-char limit) |

**Findings**:

- Both `--body` and `--body-file` hit the same GitHub API endpoint
- GitHub API limit is 65,536 characters (applies equally to both methods)
- macOS `ARG_MAX` is ~1MB (well above typical issue bodies)
- The original exp-066 failures were likely caused by network/auth/rate-limit issues, not the heredoc pattern

**Actions taken**:

- Hook (`gh-issue-body-file-guard.mjs`) and test file deleted
- All documentation references updated to remove the requirement
- Hook removed from `hooks.json`

## References

- Issue #5: Original hook request
- exp-066 session: Original (false positive) evidence
- [GitHub API body limit discussion](https://github.com/orgs/community/discussions/27190)
