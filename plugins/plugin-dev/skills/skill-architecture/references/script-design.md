# Script Design for Agentic Consumption

Scripts bundled with skills are executed by Claude Code agents, not humans at a terminal. This reference documents the design principles that make scripts reliable in agentic contexts.

## Core Principles

### 1. No Interactive Prompts

Agent stdin is not connected. Any script that blocks waiting for input will hang the agent indefinitely.

| Pattern                 | Status     | Alternative                           |
| ----------------------- | ---------- | ------------------------------------- |
| `input("Continue? ")`   | Prohibited | Accept `--yes` / `--force` flag       |
| `read -p "Enter value"` | Prohibited | Require as CLI argument               |
| `select` menu           | Prohibited | Accept choice as argument             |
| `confirm()` dialog      | Prohibited | Default to safe action or `--dry-run` |

### 2. `--help` as Primary Agent Interface

The agent reads `--help` output to understand how to invoke a script. Write help text as if it were API documentation.

```
usage: check-deps.py [--format json|text] [--strict] [paths...]

Check project dependencies for version conflicts.

Options:
  --format json|text  Output format (default: json)
  --strict            Fail on warnings too
  --dry-run           Show what would change without modifying files

Exit codes:
  0   All checks passed
  1   Dependency conflicts found
  2   Invalid arguments
```

Include: usage line, description, all flags with defaults, exit codes. Omit: version numbers, author info, decorative formatting.

### 3. Structured Output

Prefer JSON on stdout over free-form text. The agent can parse JSON reliably; it cannot reliably parse prose.

```bash
# stdout: structured data (agent consumes this)
echo '{"status": "ok", "files_changed": 3, "warnings": []}'

# stderr: diagnostics (agent reads for troubleshooting)
echo "Scanning 142 files..." >&2
```

**Rules:**

- stdout = data (JSON, CSV, or single values)
- stderr = progress, warnings, diagnostics
- Never mix data and diagnostics on the same stream

### 4. Idempotency

Running a script twice with the same arguments must produce the same result. The agent may retry on failure or re-run during iteration.

```python
# Good: check before acting
if not path.exists():
    path.mkdir(parents=True)

# Bad: fails on second run
path.mkdir()  # FileExistsError
```

### 5. Meaningful Exit Codes

```
0   Success
1   General failure (with message on stderr)
2   Invalid arguments / usage error
```

Never exit 0 on failure. The agent uses exit codes as the primary success/failure signal.

### 6. Predictable Output Size

Unbounded output floods the agent's context window and degrades performance.

| Pattern                 | Problem            | Fix                                  |
| ----------------------- | ------------------ | ------------------------------------ |
| `find / -name "*.py"`   | Thousands of lines | Limit scope or paginate              |
| Dumping entire DB table | Unbounded          | `LIMIT 100` + `--limit` flag         |
| Full stack traces       | Verbose            | Summarize, full trace on `--verbose` |

**Rule of thumb**: Default output should fit in 50 lines. Offer `--verbose` for more.

### 7. Self-Contained Dependencies

Scripts should declare their own dependencies so the agent can run them without manual setup.

#### Python: PEP 723 Inline Metadata

```python
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "httpx>=0.27",
#     "rich>=13.0",
# ]
# ///

"""Check API endpoint health."""

import json
import sys

import httpx


def main():
    url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080/health"
    try:
        r = httpx.get(url, timeout=10)
        result = {"url": url, "status": r.status_code, "ok": r.is_success}
    except httpx.RequestError as e:
        result = {"url": url, "status": None, "ok": False, "error": str(e)}
        print(json.dumps(result))
        sys.exit(1)

    print(json.dumps(result))
    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
```

Run with: `uv run --python 3.13 scripts/check-health.py https://example.com/health`

#### TypeScript/Bun: Auto-Install

```typescript
#!/usr/bin/env bun
/**
 * Validate JSON schema conformance.
 * Usage: bun run scripts/validate-schema.ts <schema.json> <data.json>
 *
 * Exit codes: 0 = valid, 1 = invalid, 2 = bad arguments
 */

import Ajv from "ajv"; // bun auto-installs on first run

const [schemaPath, dataPath] = Bun.argv.slice(2);

if (!schemaPath || !dataPath) {
  console.error("Usage: validate-schema.ts <schema.json> <data.json>");
  process.exit(2);
}

const schema = await Bun.file(schemaPath).json();
const data = await Bun.file(dataPath).json();
const ajv = new Ajv();
const valid = ajv.validate(schema, data);

const result = {
  valid,
  errors: valid ? [] : ajv.errors,
};

console.log(JSON.stringify(result, null, 2));
process.exit(valid ? 0 : 1);
```

Run with: `bun run scripts/validate-schema.ts schema.json data.json`

### 8. Dry-Run Support

Destructive operations must support `--dry-run` to let the agent preview effects before committing.

```python
def delete_stale_branches(branches: list[str], dry_run: bool = False):
    for branch in branches:
        if dry_run:
            print(json.dumps({"action": "would_delete", "branch": branch}))
        else:
            subprocess.run(["git", "branch", "-D", branch], check=True)
            print(json.dumps({"action": "deleted", "branch": branch}))
```

The agent calls with `--dry-run` first, reviews output, then runs without it.

### 9. Actionable Error Messages

Errors go to stderr and include what went wrong, why, and how to fix it.

```python
# Bad
sys.exit("Error")

# Good
print(
    "Error: config.toml not found at /project/config.toml. "
    "Run 'init-project --dir /project' to create it.",
    file=sys.stderr,
)
sys.exit(1)
```

## Quick Checklist

Use this when reviewing scripts bundled with skills:

- [ ] No interactive prompts (no stdin reads)
- [ ] `--help` documents usage, flags, and exit codes
- [ ] Data on stdout, diagnostics on stderr
- [ ] JSON output by default (or `--format json` option)
- [ ] Idempotent (safe to re-run)
- [ ] Exit 0 only on success
- [ ] Output bounded by default (< 50 lines)
- [ ] Dependencies declared inline (PEP 723 or Bun auto-install)
- [ ] `--dry-run` for destructive operations
- [ ] Error messages include fix guidance

## Reference

- [Progressive Disclosure](./progressive-disclosure.md) - When to use scripts vs references
- [Bash Compatibility](./bash-compatibility.md) - Shell portability for bash scripts
- [Security Practices](./security-practices.md) - Script permission and threat model
