---
name: doppler-secret-validation
description: Validate and test Doppler secrets. TRIGGERS - add to Doppler, store secret, validate token, test credentials.
allowed-tools: Read, Bash
---

# Doppler Secret Validation

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Overview

Workflow for securely adding, validating, and testing API tokens and credentials in Doppler secrets management.

## When to Use This Skill

Use this skill when:

- User provides API tokens or credentials (PyPI, GitHub, AWS, etc.)
- User mentions "add to Doppler", "store secret", "validate token"
- User wants to test authentication before production use
- User needs to verify secret storage and retrieval

## Workflow

### Step 1: Test Token Format (Before Adding to Doppler)

Before storing in Doppler, validate token format:

```bash
# Check token format, length, prefix
python3 -c "token = 'TOKEN_VALUE'; print(f'Prefix: {token[:20]}...'); print(f'Length: {len(token)}')"
```

**Common token formats**:

- PyPI: `pypi-...` (179 chars)
- GitHub: `ghp_...` (40+ chars)
- AWS: 20-char access key + 40-char secret

### Step 2: Add Secret to Doppler

```bash
doppler secrets set SECRET_NAME="value" --project PROJECT --config CONFIG
```

**Example**:

```bash
doppler secrets set PYPI_TOKEN="pypi-AgEI..." \
  --project claude-config --config prd
```

**Important**: CLI doesn't support `--note`. Add notes via dashboard:

1. <https://dashboard.doppler.com>
2. Navigate: PROJECT → CONFIG → SECRET_NAME
3. Edit → Add descriptive note

### Step 3: Validate Storage

Use the bundled validation script:

```bash
/usr/bin/env bash << 'VALIDATE_EOF'
ROOT="$(cc-plugin-root devops-tools)"
cd "$ROOT/skills/doppler-secret-validation"
uv run scripts/validate_secret.py \
  --project PROJECT \
  --config CONFIG \
  --secret SECRET_NAME
VALIDATE_EOF
```

This validates:

1. Secret exists in Doppler
2. Secret retrieval works
3. Environment injection works via `doppler run`

**Example**:

```bash
uv run scripts/validate_secret.py \
  --project claude-config \
  --config prd \
  --secret PYPI_TOKEN
```

### Step 4: Test API Authentication

Use the bundled auth test script (adapt test_api_authentication() for specific API):

```bash
/usr/bin/env bash << 'CONFIG_EOF'
ROOT="$(cc-plugin-root devops-tools)"
doppler run --project PROJECT --config CONFIG -- \
  "$ROOT/skills/doppler-secret-validation/scripts/test_api_auth.py" \
    --secret SECRET_NAME \
    --api-url API_ENDPOINT
CONFIG_EOF
```

**Example (PyPI)**:

```bash
doppler run --project claude-config --config prd -- \
  uv run scripts/test_api_auth.py \
    --secret PYPI_TOKEN \
    --api-url https://upload.pypi.org/legacy/
```

### Step 5: Document Usage

After validation, document the usage pattern for the user:

```bash
/usr/bin/env bash << 'CONFIG_EOF_2'
# Pattern 1: Doppler run (recommended for CI/scripts)
doppler run --project PROJECT --config CONFIG -- COMMAND

# Pattern 2: Manual export (for troubleshooting)
export SECRET_NAME=$(doppler secrets get SECRET_NAME \
  --project PROJECT --config CONFIG --plain)
CONFIG_EOF_2
```

### Step 5b: Directory-Scoped Doppler Config (Local Development)

For per-directory credentials, bind the directory to a Doppler project/config once with `doppler setup`; every later `doppler run` in that directory picks it up without `--project`/`--config`:

```bash
cd ~/project && doppler setup --project myproject --config prd --no-interactive
doppler run -- COMMAND
```

**GitHub tokens are the exception**: do not inject `GH_TOKEN`/`GITHUB_TOKEN` from Doppler into a directory (ADR 2026-06-21). GitHub multi-account auth is driven by the repo's `origin` host-alias, and a token resolves fresh per-repo via `~/.claude/tools/bin/gh-token-for-repo`.

## Common Patterns

### Multiple Configs (dev, stg, prd)

Add secret to multiple environments:

```bash
# Production
doppler secrets set TOKEN="prod-value" --project foo --config prd

# Development
doppler secrets set TOKEN="dev-value" --project foo --config dev
```

### Verify Secret Across Configs

```bash
/usr/bin/env bash << 'CONFIG_EOF_3'
for config in dev stg prd; do
  echo "=== $config ==="
  doppler secrets get TOKEN --project foo --config $config --plain | head -c 20
  echo "..."
done
CONFIG_EOF_3
```

## Security Guidelines

1. **Never log full secrets**: Use `${SECRET:0:20}...` masking
2. **Prefer doppler run**: Scopes secrets to single command
3. **Use --plain only for piping**: Human-readable view masks secrets
4. **Separate configs per environment**: dev/stg/prd isolation

## Bundled Resources

- **scripts/validate_secret.py** - Complete validation suite (existence, retrieval, injection)
- **scripts/test_api_auth.py** - Template for API authentication testing
- **references/doppler-patterns.md** - Common CLI patterns and examples

## Reference

- Doppler docs: <https://docs.doppler.com/docs>
- CLI install: `brew install dopplerhq/cli/doppler`
- See [doppler-patterns.md](./references/doppler-patterns.md) for comprehensive patterns

---

## Troubleshooting

| Issue                       | Cause                          | Solution                                                                                    |
| --------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------- |
| Secret not found            | Wrong project/config specified | Verify with `doppler secrets ls --project X --config`                                       |
| Auth test fails with 401    | Token expired or invalid       | Regenerate token, re-add to Doppler                                                         |
| doppler run hangs           | CLI waiting for input          | Add `--no-interactive` flag                                                                 |
| Token prefix mismatch       | Wrong token type used          | Check expected format (pypi-, ghp-, AKIA, etc.)                                             |
| Validation script not found | Wrong directory context        | Use `cc-plugin-root devops-tools` to find the plugin root, then `cd` to the skill directory |
| Secret retrieval empty      | Secret name typo               | List secrets: `doppler secrets ls --project X`                                              |
| Multiple configs confusion  | Secrets differ across envs     | Use explicit --config flag for each command                                                 |

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
