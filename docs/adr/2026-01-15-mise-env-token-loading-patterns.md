---
status: accepted
date: 2026-01-15
decision-maker: Terry Li
consulted: [Claude Opus 4.5]
research-method: incident-investigation
---

<!-- PROCESS-STORM-OK: This ADR documents anti-patterns for educational purposes -->

# mise [env] Token Loading: read_file vs exec

**Related**: [mise [env] Centralized Config](/docs/adr/2025-12-08-mise-env-centralized-config.md) | [GitHub Multi-Account Auth](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-17-github-multi-account-authentication.md)

## Context and Problem Statement

GitHub API rate limiting occurs intermittently across all accounts (paid and unpaid) despite tokens being configured in mise `[env]`. Investigation revealed that subprocess calls don't inherit mise environment variables, and certain mise template patterns exacerbate the problem.

### Root Cause Analysis

| Issue                      | Pattern                          | Impact                                    |
| -------------------------- | -------------------------------- | ----------------------------------------- |
| `exec()` spawns subprocess | `{{ exec(command='cat file') }}` | Extra process on every mise load          |
| Token not inherited        | `uvx`, `cargo`, subprocesses     | Falls back to unauthenticated (60 req/hr) |
| Fallback cascade           | gh CLI subprocess calls          | Creates process storm recursion           |

### The Vicious Cycle

```
Rate limit hit → Subprocess polls GitHub → GH_TOKEN not inherited
       ↓
Falls back to gh CLI auth subprocess → Creates process storm
       ↓
git-credential helper can't find token → Falls back to Keychain
       ↓
Uses wrong account or unauthenticated → MORE rate limit hits
```

## Decision

### 1. Use `read_file()` instead of `exec()` for token loading

```toml
# CORRECT: read_file() - no subprocess, just reads file
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"

# WRONG: exec() - spawns subprocess on every mise load
GH_TOKEN = "{{ exec(command='cat ~/.claude/.secrets/gh-token-terrylica') }}"
```

### 2. Set both `GH_TOKEN` and `GITHUB_TOKEN`

Some tools check `GITHUB_TOKEN`, others check `GH_TOKEN`:

```toml
[env]
GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
GITHUB_TOKEN = "{{ read_file(path=env.HOME ~ '/.claude/.secrets/gh-token-terrylica') | trim }}"
```

### 3. Wrap subprocess-spawning tools with `mise x --`

For MCP servers or other tools that spawn subprocesses:

```json
{
  "ast-grep": {
    "command": "mise",
    "args": ["x", "--", "uvx", "--python", "3.13", "--from", "git+..."],
    "cwd": "."
  }
}
```

This ensures `GH_TOKEN` is inherited by the subprocess.

### 4. Never use gh CLI auth subprocess as fallback

The Process Storm Guard blocks this pattern for good reason:

```python
# WRONG: Creates credential helper recursion
# token = subprocess.run(["gh", "auth", "token"], ...)  # DO NOT USE

# CORRECT: Read from environment only
token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
if not token:
    raise ValueError("GH_TOKEN not set - check mise [env] configuration")
```

## Template Syntax Reference

| Syntax        | Purpose              | Example               |
| ------------- | -------------------- | --------------------- | ------------------------ |
| `~`           | String concatenation | `env.HOME ~ '/path'`  |
| `read_file()` | Read file contents   | `read_file(path=...)` |
| `             | trim`                | Remove whitespace     | `read_file(...) \| trim` |
| `env.HOME`    | Home directory       | `/Users/terryli`      |
| `config_root` | mise.toml directory  | Current project root  |

## Validation Checklist

When creating new `mise.toml` files:

- [ ] Use `read_file()` not `exec()` for secrets
- [ ] Set both `GH_TOKEN` and `GITHUB_TOKEN`
- [ ] Use `env.HOME ~` for absolute paths (not `~` shorthand)
- [ ] Add `| trim` to remove trailing newlines
- [ ] Wrap subprocess tools with `mise x --` in `.mcp.json`
- [ ] Never implement gh CLI auth fallback in code

## Consequences

### Positive

- Eliminates intermittent rate limiting across all accounts
- Reduces process spawning overhead
- Consistent token inheritance in subprocess contexts

### Negative

- Must remember two different patterns (`read_file` vs `exec`)
- `.mcp.json` files become more verbose with `mise x --` wrapper

## References

- Process Storm Guard: `~/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/pretooluse-process-storm-guard.mjs`
- Token storage: `~/.claude/.secrets/gh-token-*`
- Example fix: `~/eon/trading-fitness/mise.toml` (commit 9d54a95)
