---
title: Link Checker Plugin Extraction
adr: /docs/adr/2025-12-11-link-checker-plugin-extraction.md
status: implemented
created: 2025-12-11
---

# Link Checker Plugin Implementation Specification

**ADR**: [Link Checker Plugin Extraction](/docs/adr/2025-12-11-link-checker-plugin-extraction.md)

## Overview

Extract universal link validation from `claude-orchestrator`'s `check-links-hybrid.sh` (1,041 lines) into a standalone cc-skills marketplace plugin.

## Target Structure

```text
plugins/link-checker/
  plugin.json                     # Plugin manifest
  hooks/
    hooks.json                    # Hook configuration
    stop-link-check.py            # Main hook (PEP 723)
  lib/
    lychee_runner.py              # Lychee subprocess wrapper
    path_linter.py                # Path policy validation
    ulid_gen.py                   # ULID generator (copied)
    event_logger.py               # Optional tracing (copied)
  config/
    lychee.toml                   # Default lychee config
  README.md                       # User documentation
  SKILL.md                        # Skill definition
```

## Component Specifications

### 1. plugin.json

```json
{
  "name": "link-checker",
  "version": "1.0.0",
  "description": "Universal link validation using lychee for Claude Code sessions",
  "hooks": "./hooks/hooks.json"
}
```

### 2. hooks/hooks.json

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "uv run ${CLAUDE_PLUGIN_ROOT}/hooks/stop-link-check.py",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

### 3. hooks/stop-link-check.py

Main entry point with PEP 723 inline dependencies.

**Inline Dependencies**:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "python-ulid>=2.7.0",
# ]
# ///
```

**Core Logic**:

1. Read JSON input from stdin (hook payload)
2. Check for loop prevention flag (`stop_hook_active`)
3. Discover markdown files in workspace
4. Run lychee validation via `lychee_runner.py`
5. Run path policy validation via `path_linter.py`
6. Output JSON results to stdout
7. Optionally write detailed results to file

**Input Schema** (from Claude Code Stop hook):

```json
{
  "session_id": "string",
  "cwd": "string (workspace path)",
  "stop_hook_active": "boolean (loop prevention)"
}
```

**Output Schema**:

```json
{
  "status": "pass | fail | error | skipped",
  "error_count": 0,
  "lychee_errors": 0,
  "path_violations": 0,
  "results_file": "/workspace/.link-check-results.md",
  "correlation_id": "ULID"
}
```

### 4. lib/lychee_runner.py

Subprocess wrapper for lychee CLI.

**Functions**:

- `run_lychee(files: list[Path], config_path: Path | None) -> LycheeResult`
- `parse_lychee_output(stdout: str, stderr: str) -> list[LinkError]`
- `find_config(workspace: Path) -> Path | None` (cascade: repo -> workspace -> plugin default)

**Config Resolution Order**:

1. `{workspace}/.lycheerc.toml`
2. `{workspace}/lychee.toml`
3. `~/.claude/.lycheerc.toml`
4. `${CLAUDE_PLUGIN_ROOT}/config/lychee.toml`

### 5. lib/path_linter.py

Validates markdown link paths against policies.

**Functions**:

- `lint_paths(files: list[Path], workspace: Path) -> list[PathViolation]`
- `check_absolute_paths(content: str) -> list[str]` (detect `/absolute/paths`)
- `check_relative_escapes(content: str) -> list[str]` (detect `../../` escapes)

**Policy Rules**:

| Rule                 | Description                        | Severity |
| -------------------- | ---------------------------------- | -------- |
| NO_ABSOLUTE_PATHS    | Links should be repo-relative      | Warning  |
| NO_PARENT_ESCAPES    | `../` should not escape repository | Error    |
| NO_BROKEN_ANCHORS    | `#section` anchors must exist      | Error    |
| MARKETPLACE_RELATIVE | Plugin files must use `./` paths   | Error    |

### 6. lib/ulid_gen.py

Copy from orchestrator with minimal modifications.

**Source**: `~/.claude/automation/claude-orchestrator/runtime/lib/ulid_gen.py`

**Functions**:

- `generate_ulid() -> str`
- `ulid_timestamp(ulid: str) -> datetime`

### 7. lib/event_logger.py

Optional tracing for debugging. Copy from orchestrator with configurable DB path.

**Source**: `~/.claude/automation/claude-orchestrator/runtime/lib/event_logger.py`

**Modifications**:

- DB path from env var: `LINK_CHECKER_DB_PATH`
- Default: `${XDG_STATE_HOME:-~/.local/state}/link-checker/events.db`

### 8. config/lychee.toml

Default configuration bundled with plugin.

**Key Settings**:

```toml
# Timeout for HTTP requests
timeout = 30

# Skip these patterns
exclude = [
  "^https://localhost",
  "^file://",
  "^mailto:",
]

# Accept these status codes
accept = [200, 204, 301, 302]

# GitHub rate limiting
max_concurrency = 4

# Cache settings
cache = true
```

## Integration Points

### With Claude Code

- **Hook Event**: Stop (session end)
- **Loop Prevention**: Check `stop_hook_active` in input
- **Exit Codes**: 0 = success/skipped, 1 = errors found

### With claude-orchestrator (Optional)

The orchestrator can consume plugin output by:

1. Reading JSON from stdout
2. Reading detailed results file
3. Correlating via ULID

This enables gradual migration without breaking existing workflows.

## Testing Strategy

### Unit Tests

```bash
# Test lychee runner
uv run pytest tests/test_lychee_runner.py

# Test path linter
uv run pytest tests/test_path_linter.py
```

### Integration Test

```bash
# Simulate Stop hook
cd /path/to/workspace
echo '{"cwd": "'"$(pwd)"'", "session_id": "test"}' | \
  uv run plugins/link-checker/hooks/stop-link-check.py
```

### Manual Validation

```bash
# Check plugin loads
claude --print-plugins | grep link-checker

# Trigger Stop hook manually
# (create session, make changes, exit)
```

## Migration from Orchestrator

### Phase 1: Parallel Operation

1. Install link-checker plugin
2. Keep orchestrator hook active
3. Compare outputs for consistency

### Phase 2: Orchestrator Consumption

1. Modify orchestrator to read plugin output
2. Disable orchestrator's own link checking
3. Keep Telegram notifications via plugin output

### Phase 3: Full Independence

1. Remove link-checking code from orchestrator
2. Plugin operates standalone
3. Any consumer can use JSON output

## Dependencies

### Required

- Python 3.11+
- uv (package manager)
- lychee (Rust link checker)
- git (for workspace detection)

### Python (PEP 723 inline)

- python-ulid>=2.7.0

## Security Considerations

- No network access except lychee's link checking
- No file writes except optional results file
- No credential access required
- Sandbox-compatible execution

## Error Handling

| Error                | Behavior                       | Exit Code |
| -------------------- | ------------------------------ | --------- |
| lychee not installed | Log warning, return skipped    | 0         |
| No markdown files    | Return pass (nothing to check) | 0         |
| lychee timeout       | Log error, return error status | 0         |
| Invalid JSON input   | Log error, return error status | 1         |
| Path lint violations | Return fail with details       | 0         |
| Link check failures  | Return fail with details       | 0         |

## Success Metrics

- [ ] Plugin installs via cc-skills marketplace
- [ ] Works without claude-orchestrator installed
- [ ] JSON output consumable by external tools
- [ ] Lychee validation matches orchestrator behavior
- [ ] Path linting catches policy violations
- [ ] Documentation complete (README.md, SKILL.md)
