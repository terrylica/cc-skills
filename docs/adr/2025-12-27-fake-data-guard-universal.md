---
status: implemented
date: 2025-12-27
decision-maker: Terry Li
consulted: [claude-code-guide]
research-method: documentation-review
---

# ADR: Universal Fake Data Guard PreToolUse Hook

## Context and Problem Statement

When Claude Code creates new Python files, it often generates fake/synthetic data using patterns like `np.random.randn()`, `Faker()`, or `mock_data = {}`. This is problematic for production codebases where:

1. **Reproducibility concerns**: Random data makes tests non-deterministic
2. **Data quality issues**: Synthetic data doesn't reflect real-world distributions
3. **Security risks**: Fake credentials or API keys may accidentally be committed
4. **Technical debt**: Placeholder data often remains long after it should be replaced

### Before/After

**Before**: No enforcement - fake data patterns go unnoticed

```
Before: No Fake Data Detection

+-----------------------+     +-----------------------------+     +------------------------+
|   Claude creates      |     |   No validation or          |     |   Fake data in         |
|   new Python file     | --> |   awareness                 | --> |   production code      |
+-----------------------+     +-----------------------------+     +------------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Before: No Fake Data Detection"; flow: east; }

[create] { label: "Claude creates\\nnew Python file"; }
[no-check] { label: "No validation or\\nawareness"; }
[issues] { label: "Fake data in\\nproduction code"; }

[create] -> [no-check] -> [issues]
```

</details>

**After**: Permission dialog gives user discretion

```
After: Fake Data Guard Active

+-----------------------+     +-----------------------------+     +------------------------+
|   Claude creates      |     |   PreToolUse detects        |     |   User decides:        |
|   new Python file     | --> |   patterns, shows dialog    | --> |   Allow or Deny        |
+-----------------------+     +-----------------------------+     +------------------------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "After: Fake Data Guard Active"; flow: east; }

[create] { label: "Claude creates\\nnew Python file"; }
[guard] { label: "PreToolUse detects\\npatterns, shows dialog"; }
[decide] { label: "User decides:\\nAllow or Deny"; }

[create] -> [guard] -> [decide]
```

</details>

## Decision Drivers

- Need to catch fake data patterns before they enter the codebase
- Must not block legitimate use cases (test files, whitelisted lines)
- Should work universally across all projects
- Must allow user discretion (permission dialog) rather than hard blocking
- Integration with existing `/itp:hooks install` workflow

## Considered Options

- **Option A**: Hard block all fake data patterns
- **Option B**: Permission dialog for user discretion (chosen)
- **Option C**: PostToolUse reminder only (non-blocking)

## Decision Outcome

Chosen option: **Option B (Permission Dialog)**, because:

1. Users can make informed decisions about each case
2. Legitimate uses (seeded random for reproducibility) can be allowed
3. Non-intrusive: only triggers on new Python files (Write tool, not Edit)
4. Configurable: per-project and global configuration support

### Implementation Details

**Hook location**: `plugins/itp-hooks/hooks/pretooluse-fake-data-guard.mjs`

**Pattern categories** (69 total patterns):

| Category           | Count | Examples                                         |
| ------------------ | ----- | ------------------------------------------------ |
| numpy_random       | 15    | `np.random.randn`, `RandomState`, `default_rng`  |
| python_random      | 10    | `random.random()`, `random.randint()`            |
| faker_library      | 4     | `Faker()`, `faker.name()`, `from faker import`   |
| factory_patterns   | 7     | `Factory.create`, `factory_boy`, `_factory`      |
| synthetic_keywords | 21    | `synthetic_data`, `mock_data`, `generate_random` |
| data_generation    | 7     | `make_classification`, `sklearn.datasets.make`   |
| test_data_libs     | 5     | `hypothesis`, `mimesis`, `polyfactory`           |

**Exclusions** (no detection):

- Test files: `tests/`, `*_test.py`, `conftest.py`
- Edit tool: Only Write (new files) is checked
- Whitelisted lines: `# noqa: fake-data` or `# allow-random`

**Configuration hierarchy**:

1. Project: `$PROJECT_DIR/.claude/fake-data-guard.json`
2. Global: `~/.claude/fake-data-guard.json`
3. Defaults (all patterns enabled, `ask` mode)

## Installation

```bash
# Installs all itp-hooks including fake-data-guard
/itp:hooks install

# Check status
/itp:hooks status

# Uninstall
/itp:hooks uninstall
```

**Preflight**: Installer checks for `bun` or `node` (required for `.mjs` hooks).

## Consequences

### Positive

- Catches fake data patterns early in development
- User retains control via permission dialog
- Configurable per-project and globally
- Excludes test files by default
- Whitelist escape hatch for legitimate uses

### Negative

- Requires bun or node runtime
- May produce false positives for legitimate patterns
- Additional permission prompts during development

## Technical Notes

**Exit behavior**: Uses `permissionDecision: "ask"` to show permission dialog (not exit code 2 hard block).

**Performance**: ~5ms execution time (Bun runtime).

**Testing**: 48 unit tests covering all pattern categories and edge cases.

```bash
bun test plugins/itp-hooks/hooks/tests/
```

## References

- [PreToolUse and PostToolUse Hooks ADR](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [ITP Hooks Settings Installer ADR](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
