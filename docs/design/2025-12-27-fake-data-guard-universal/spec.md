---
adr: 2025-12-27-fake-data-guard-universal
source: ~/.claude/plans/composed-booping-meadow.md
implementation-status: completed
phase: phase-3
last-updated: 2025-12-28
---

# Fake Data Guard Implementation Specification

**ADR**: [Universal Fake Data Guard PreToolUse Hook](/docs/adr/2025-12-27-fake-data-guard-universal.md)

## Problem Statement

Claude Code creates new Python files with fake/synthetic data patterns (`np.random.randn()`, `Faker()`, etc.) that can lead to:

1. Non-deterministic tests
2. Data quality issues in production
3. Security risks from placeholder credentials
4. Technical debt from forgotten placeholders

## Solution Overview

A PreToolUse hook that detects 69 fake data patterns across 7 categories and shows a permission dialog for user discretion.

| Component | Implementation                           |
| --------- | ---------------------------------------- |
| Hook Type | PreToolUse (`permissionDecision: "ask"`) |
| Runtime   | Bun (MJS modules)                        |
| Patterns  | 69 across 7 categories                   |
| Config    | Project → Global → Defaults hierarchy    |
| Scope     | Write tool only (new files)              |

## File Structure

```
plugins/itp-hooks/hooks/
├── fake-data-patterns.mjs       # Pattern definitions + detection logic
├── pretooluse-fake-data-guard.mjs  # Main hook entry point
├── hooks.json                   # Hook registration documentation
└── tests/
    └── fake-data-guard.test.mjs # 48 unit tests

plugins/itp/scripts/
└── manage-hooks.sh              # Installer (canonical)
```

## Pattern Categories

| Category           | Count  | Examples                                         |
| ------------------ | ------ | ------------------------------------------------ |
| numpy_random       | 15     | `np.random.randn`, `RandomState`, `default_rng`  |
| python_random      | 10     | `random.random()`, `random.randint()`            |
| faker_library      | 4      | `Faker()`, `faker.name()`, `from faker import`   |
| factory_patterns   | 7      | `Factory.create`, `factory_boy`, `_factory`      |
| synthetic_keywords | 21     | `synthetic_data`, `mock_data`, `generate_random` |
| data_generation    | 7      | `make_classification`, `sklearn.datasets.make`   |
| test_data_libs     | 5      | `hypothesis`, `mimesis`, `polyfactory`           |
| **Total**          | **69** |                                                  |

## Hook Flow

```
PreToolUse Hook Flow

+------------------+     +-----------------+     +--------------------+
|  Read JSON from  |     |  tool_name ==   |     |  Load config       |
|  stdin           | --> |  "Write"?       | --> |  (project/global)  |
+------------------+     +-----------------+     +--------------------+
                              │ No                        │
                              ∨                          ∨
                         +--------+             +-------------------+
                         | Allow  |             | enabled == false? |
                         +--------+             +-------------------+
                                                      │ Yes
                                                      ∨
                                                 +--------+
                                                 | Allow  |
                                                 +--------+
                                                      │ No
                                                      ∨
                                               +----------------+
                                               | path excluded? |
                                               +----------------+
                                                      │ No
                                                      ∨
                                               +----------------+
                                               | .py extension? |
                                               +----------------+
                                                      │ Yes
                                                      ∨
                                               +----------------+
                                               | Scan patterns  |
                                               +----------------+
                                                      │
                                                      ∨
                                               +----------------+
                                               | Findings > 0?  |
                                               +----------------+
                                                  │ Yes    │ No
                                                  ∨        ∨
                                             +------+  +-------+
                                             | Ask  |  | Allow |
                                             +------+  +-------+
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "PreToolUse Hook Flow"; flow: south; }

[stdin] { label: "Read JSON from\\nstdin"; }
[check-write] { label: "tool_name ==\\n\"Write\"?"; }
[load-config] { label: "Load config\\n(project/global)"; }
[allow1] { label: "Allow"; }
[check-enabled] { label: "enabled == false?"; }
[allow2] { label: "Allow"; }
[check-path] { label: "path excluded?"; }
[check-py] { label: ".py extension?"; }
[scan] { label: "Scan patterns"; }
[check-findings] { label: "Findings > 0?"; }
[ask] { label: "Ask"; border: bold; }
[allow3] { label: "Allow"; }

[stdin] -> [check-write]
[check-write] -- Yes --> [load-config]
[check-write] -- No --> [allow1]
[load-config] -> [check-enabled]
[check-enabled] -- Yes --> [allow2]
[check-enabled] -- No --> [check-path]
[check-path] -- No --> [check-py]
[check-py] -- Yes --> [scan]
[scan] -> [check-findings]
[check-findings] -- Yes --> [ask]
[check-findings] -- No --> [allow3]
```

</details>

## Configuration Schema

```json
{
  "enabled": true,
  "mode": "ask",
  "patterns": {
    "numpy_random": true,
    "python_random": true,
    "faker_library": true,
    "factory_patterns": true,
    "synthetic_keywords": true,
    "data_generation": true,
    "test_data_libs": true
  },
  "whitelist_comments": ["# noqa: fake-data", "# allow-random"],
  "exclude_paths": ["tests/", "*_test.py", "conftest.py"]
}
```

### Config Hierarchy

1. **Project**: `$CLAUDE_PROJECT_DIR/.claude/fake-data-guard.json`
2. **Global**: `~/.claude/fake-data-guard.json`
3. **Defaults**: All patterns enabled, `ask` mode

## Hook Output Format

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "[FAKE DATA GUARD] Detected fake/synthetic data patterns in model.py:\n\n  numpy_random:\n    - Line 5: 'np.random.randn'\n\nConsider using real data, pre-computed fixtures, or API data instead.\nTo whitelist: add \"# noqa: fake-data\" comment to the line."
  }
}
```

## Installation

```bash
# Via /itp:hooks skill (canonical)
/itp:hooks install

# Preflight checks:
# - jq (required)
# - bun or node (required for .mjs hooks)
```

The installer adds entries to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/itp-hooks/hooks/pretooluse-fake-data-guard.mjs",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

## Validation Commands

```bash
# Run unit tests (48 tests)
bun test plugins/itp-hooks/hooks/tests/

# Verify pattern counts
bun -e "import {PATTERNS} from './plugins/itp-hooks/hooks/fake-data-patterns.mjs'; console.log(Object.entries(PATTERNS).map(([k,v])=>k+': '+v.length).join(', '))"

# Test hook manually
echo '{"tool_name":"Write","tool_input":{"file_path":"test.py","content":"data = np.random.randn(100)"}}' | bun plugins/itp-hooks/hooks/pretooluse-fake-data-guard.mjs

# Check installation status
/itp:hooks status
```

## Success Criteria

| Criterion                       | Status | Evidence                                                    |
| ------------------------------- | ------ | ----------------------------------------------------------- |
| 69 patterns across 7 categories | ✓      | `bun -e "import {PATTERNS}..."` outputs 15+10+4+7+21+7+5=69 |
| Unit tests pass (48 tests)      | ✓      | `bun test plugins/itp-hooks/hooks/tests/` - 48 pass, 0 fail |
| Hook detects np.random.randn    | ✓      | E2E test returns `permissionDecision: "ask"`                |
| Hook detects Faker()            | ✓      | E2E test returns `permissionDecision: "ask"`                |
| Edit tool allowed (not checked) | ✓      | E2E test returns `permissionDecision: "allow"`              |
| Non-Python files allowed        | ✓      | E2E test returns `permissionDecision: "allow"`              |
| Whitelisted lines allowed       | ✓      | `# noqa: fake-data` returns `permissionDecision: "allow"`   |
| Test paths excluded             | ✓      | `tests/`, `*_test.py`, `conftest.py` return `allow`         |
| Clean files allowed             | ✓      | Files without patterns return `permissionDecision: "allow"` |
| Preflight checks bun/node       | ✓      | `manage-hooks.sh` contains `command -v bun` check           |
| Timeouts in milliseconds        | ✓      | 15000, 10000, 5000 verified in manage-hooks.sh              |
| Output format correct           | ✓      | JSON with `hookSpecificOutput.permissionDecision`           |
| Reason contains prefix          | ✓      | Reason starts with `[FAKE DATA GUARD]`                      |
| Reason contains whitelist help  | ✓      | Reason includes `# noqa: fake-data`                         |
| Uninstall removes entries       | ✓      | ITP_MARKER="itp-hooks/hooks/" identifies all entries        |
| ADR created                     | ✓      | `docs/adr/2025-12-27-fake-data-guard-universal.md` exists   |
| Duplicate commands deleted      | ✓      | `plugins/itp-hooks/commands/hooks.md` deleted               |
| Duplicate script deleted        | ✓      | `plugins/itp-hooks/scripts/manage-hooks.sh` deleted         |

## Known Limitations

1. **Shell escaping in tests**: Bash echo with `\n` creates literal newlines that break JSON; use file input or printf
2. **Node fallback**: If bun unavailable, falls back to node (slower but functional)
3. **False positives**: Patterns like `hypothesis` may match non-test code; use whitelist comments

## Related Documents

- [PreToolUse and PostToolUse Hooks ADR](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [ITP Hooks Settings Installer ADR](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
