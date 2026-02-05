# mise.toml Hygiene Guard Hook

## Status

Accepted

## Context

mise.toml files in shared repositories face two hygiene issues:

1. **File sprawl**: Root mise.toml files grow unbounded as developers add tasks, eventually becoming unmanageable (>100 lines)
2. **Secrets leakage**: Developers accidentally commit hardcoded secrets (API keys, tokens, passwords) to mise.toml, which is meant to be shared

mise provides solutions for both:

- **Hub-spoke pattern**: Use `[task_config].includes` to reference task files in `.mise/tasks/` directory
- **Local overrides**: Use `.mise.local.toml` (highest precedence, gitignored) for secrets

However, developers often don't know about these patterns until after the damage is done.

## Decision

Implement a PreToolUse hook (`pretooluse-mise-hygiene-guard.ts`) that:

### 1. Blocks secrets in mise.toml

Detects hardcoded secret patterns:

- `api_key`, `secret_key`, `access_token`, `auth_token`
- `password`, `passwd`, `pwd`
- `gh_token`, `github_token`, `npm_token`
- `aws_access_key`, `aws_secret_key`
- `database_password`, `private_key`, `encryption_key`

Allows safe patterns (external references):

- Tera templates: `{{ read_file(...) }}`, `{{ env.VAR }}`, `{{ get_env(...) }}`
- 1Password: `{{ op_read(...) }}`, `op://...`
- Doppler: `doppler secrets`

### 2. Blocks oversized mise.toml (>100 lines)

Triggers only for Write tool (full file content). Suggests hub-spoke refactoring:

```toml
# mise.toml (hub)
[task_config]
includes = [".mise/tasks/dev.toml", ".mise/tasks/release.toml"]
```

### 3. Ignores local files

Files named `mise.local.toml` or `.mise.local.toml` are ignored - these are meant for secrets and local overrides.

## Consequences

### Positive

- Prevents secrets from being committed to shared mise.toml
- Encourages maintainable file organization via hub-spoke pattern
- Educational: provides actionable suggestions with documentation links
- Fail-open: errors in hook don't block workflow

### Negative

- May false-positive on legitimate patterns that look like secrets
- Line count threshold (100) is arbitrary; some projects may need more
- Edit tool can't check line count (only partial content available)

## References

- [mise Task Configuration](https://mise.jdx.dev/tasks/task-configuration.html) - `task_config.includes` documentation
- [mise Configuration](https://mise.jdx.dev/configuration.html) - `mise.local.toml` precedence
- [GitGuardian Secrets Best Practices](https://blog.gitguardian.com/secure-your-secrets-with-env/)

## Implementation

- Hook: `plugins/itp-hooks/hooks/pretooluse-mise-hygiene-guard.ts`
- Tests: `plugins/itp-hooks/hooks/pretooluse-mise-hygiene-guard.test.ts`
- Registration: `plugins/itp-hooks/hooks/hooks.json`
